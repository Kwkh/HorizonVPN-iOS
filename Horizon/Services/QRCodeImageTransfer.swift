import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// Read only a bounded amount from the single user-selected photo, without copying it to disk.
struct QRCodeImageTransfer: Transferable, Sendable {
    let data: Data
    nonisolated init(data: Data) { self.data = data }
    nonisolated static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let handle = try FileHandle(forReadingFrom: received.file)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: 20 * 1024 * 1024 + 1) ?? Data()
            guard !data.isEmpty, data.count <= 20 * 1024 * 1024 else { throw SubscriptionQRCode.Failure.unreadableImage }
            return QRCodeImageTransfer(data: data)
        }
    }
}
