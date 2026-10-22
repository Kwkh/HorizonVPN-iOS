import Foundation
import ImageIO
import Vision
import CoreML
import CoreImage

/// Downsample locally before barcode recognition. Nothing is cached, logged or uploaded.
enum QRCodeImageReader {
    nonisolated static func read(_ data: Data) throws -> String {
        try Task.checkCancellation()
        guard data.count <= 20 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048
              ] as CFDictionary) else { throw SubscriptionQRCode.Failure.unreadableImage }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        #if targetEnvironment(simulator)
        // Simulator GPU inference can be unavailable; use Vision's supported CPU devices.
        if let stages = try? request.supportedComputeStageDevices {
            for (stage, devices) in stages {
                if let cpu = devices.first(where: { if case .cpu = $0 { true } else { false } }) {
                    request.setComputeDevice(cpu, for: stage)
                }
            }
        }
        #endif
        // If Vision cannot run, the QR-only detector below still gets a chance.
        try? VNImageRequestHandler(cgImage: image).perform([request])
        try Task.checkCancellation()
        var payloads = (request.results ?? []).compactMap(\.payloadStringValue)
        // QR-only fallback for clear codes missed by Vision on some OS/device combinations.
        if payloads.isEmpty,
           let detector = CIDetector(ofType: CIDetectorTypeQRCode,
               context: CIContext(options: [.useSoftwareRenderer: true]),
               options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) {
            payloads = detector.features(in: CIImage(cgImage: image)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        }
        try Task.checkCancellation()
        return try SubscriptionQRCode.uniqueLink(in: payloads)
    }
}
