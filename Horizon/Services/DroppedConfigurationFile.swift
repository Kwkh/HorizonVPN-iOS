import Foundation
import UniformTypeIdentifiers

/// Materialize the provider's temporary file before its callback returns.
/// Only bounded configuration bytes are copied; never retain the source URL.
enum DroppedConfigurationFile {
    struct Staged: Sendable {
        let url: URL
        nonisolated func remove() { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    }
    enum Failure: Error { case unreadable, tooLarge }

    @MainActor static func load(_ provider: NSItemProvider) async throws -> Staged {
        let name = provider.suggestedName
        let fileType = provider.registeredTypeIdentifiers.first {
            $0 != UTType.fileURL.identifier && UTType($0)?.conforms(to: .data) == true
        }
        return try await withCheckedThrowingContinuation { continuation in
            if let fileType {
                provider.loadFileRepresentation(forTypeIdentifier: fileType) { url, _ in
                    guard let url else { continuation.resume(throwing: Failure.unreadable); return }
                    do { continuation.resume(returning: try stage(url, suggestedName: name)) }
                    catch { continuation.resume(throwing: error) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let value = item as? URL { url = value }
                    else if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                    else { url = nil }
                    guard let url else { continuation.resume(throwing: Failure.unreadable); return }
                    do { continuation.resume(returning: try stage(url, suggestedName: name)) }
                    catch { continuation.resume(throwing: error) }
                }
            } else { continuation.resume(throwing: Failure.unreadable) }
        }
    }

    nonisolated static func stage(_ source: URL, suggestedName: String?) throws -> Staged {
        guard source.isFileURL else { throw Failure.unreadable }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { throw Failure.unreadable }
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: PrototypeConfiguration.maximumBytes + 1) ?? Data()
        guard !data.isEmpty else { throw Failure.unreadable }
        guard data.count <= PrototypeConfiguration.maximumBytes else { throw Failure.tooLarge }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HorizonDrop-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let rawName = ((suggestedName ?? source.lastPathComponent) as NSString).lastPathComponent
        let name = rawName.isEmpty || rawName == "." || rawName == ".." ? "Configuration.yaml" : rawName
        let destination = folder.appendingPathComponent(name)
        do { try data.write(to: destination, options: [.atomic, .completeFileProtection]) }
        catch { try? FileManager.default.removeItem(at: folder); throw error }
        return Staged(url: destination)
    }
}
