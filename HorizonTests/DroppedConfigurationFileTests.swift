import XCTest
import UniformTypeIdentifiers
@testable import Horizon

final class DroppedConfigurationFileTests: XCTestCase {
    private func fixture(_ data: Data) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("Sample.yaml")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return url
    }
    func testCopySurvivesSourceRemovalAndCleansUp() throws {
        let data = Data("proxies: []".utf8)
        let source = try fixture(data)
        let file = try DroppedConfigurationFile.stage(source, suggestedName: "../../Example.yaml")
        defer { file.remove() }
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(try Data(contentsOf: file.url), data)
        XCTAssertEqual(file.url.lastPathComponent, "Example.yaml")
        file.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path))
    }
    func testRejectsEmptyOversizedAndDirectories() throws {
        let empty = try fixture(Data())
        XCTAssertThrowsError(try DroppedConfigurationFile.stage(empty, suggestedName: nil))
        let large = try fixture(Data(repeating: 65, count: PrototypeConfiguration.maximumBytes + 1))
        XCTAssertThrowsError(try DroppedConfigurationFile.stage(large, suggestedName: nil))
        XCTAssertThrowsError(try DroppedConfigurationFile.stage(large.deletingLastPathComponent(), suggestedName: nil))
    }
    @MainActor func testProviderFileRepresentation() async throws {
        let data = Data("proxies: []".utf8)
        let source = try fixture(data)
        let provider = NSItemProvider()
        provider.suggestedName = "Subscription.yaml"
        provider.registerFileRepresentation(forTypeIdentifier: UTType.yaml.identifier, fileOptions: [], visibility: .all) { completion in
            completion(source, false, nil)
            return nil
        }
        let file = try await DroppedConfigurationFile.load(provider)
        defer { file.remove() }
        XCTAssertEqual(try Data(contentsOf: file.url), data)
        XCTAssertEqual(file.url.lastPathComponent, "Subscription.yaml")
    }
    @MainActor func testFileURLProvider() async throws {
        let data = Data("proxies: []".utf8)
        let source = try fixture(data)
        let provider = NSItemProvider(item: source as NSURL, typeIdentifier: UTType.fileURL.identifier)
        let file = try await DroppedConfigurationFile.load(provider)
        defer { file.remove() }
        XCTAssertEqual(try Data(contentsOf: file.url), data)
    }
    @MainActor func testDroppedFileUsesPreviewWithoutAutoSavingOrConnecting() async throws {
        let source = try fixture(Data(PrototypeSelfCheck.fixture.utf8))
        let file = try DroppedConfigurationFile.stage(source, suggestedName: "Dropped.yaml")
        defer { file.remove() }
        let repository = SubscriptionRepository(storage: MemorySubscriptionStorage())
        let tunnel = TunnelController(repository: repository, permitsNetwork: false,
            network: NetworkAvailability(initialStatus: .available, monitorSystem: false))
        await tunnel.refresh()
        let prepared = await tunnel.prepareImport(file.url)
        XCTAssertTrue(prepared)
        XCTAssertEqual(tunnel.importPreview?.fileName, "Dropped.yaml")
        XCTAssertTrue(tunnel.subscriptions.isEmpty)
        XCTAssertFalse(tunnel.isTunnelActive)
        let saved = await tunnel.confirmImport(makeCurrent: false)
        XCTAssertTrue(saved)
        XCTAssertEqual(tunnel.subscriptions.count, 1)
        XCTAssertFalse(tunnel.isTunnelActive)
        tunnel.cancelImport()
    }

}
