import Foundation
import CoreImage
import ImageIO
import CoreTransferable
import UniformTypeIdentifiers

/// Only the user-requested image is exported; no temporary URL or credential file is written.
nonisolated struct SubscriptionQRShare: Transferable, Sendable {
    enum Failure: Error, Equatable { case unavailable, tooLong, rendering }
    let png: Data
    let pattern: SubscriptionQRPattern

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.png }
            .suggestedFileName("Horizon-subscription.png")
    }

    static func sourceURL(_ storedURL: String?) throws -> String {
        guard let storedURL, !storedURL.isEmpty else { throw Failure.unavailable }
        _ = try SubscriptionDownloader.validatedURL(storedURL)
        // Preserve the saved payload exactly, including percent escapes and query order.
        return storedURL
    }

    @concurrent static func generate(sourceURL: String) async throws -> SubscriptionQRShare {
        try Task.checkCancellation()
        let payload = try Self.sourceURL(sourceURL)
        // QR byte capacity at correction level M. Real capacity may be lower for a given encoder.
        guard payload.utf8.count <= 2331 else { throw Failure.tooLong }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { throw Failure.rendering }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let code = filter.outputImage, !code.extent.isEmpty else { throw Failure.tooLong }
        let context = CIContext(options: [.useSoftwareRenderer: true])
        guard let raw = context.createCGImage(code, from: code.extent), raw.width == raw.height else { throw Failure.rendering }
        let rawDimension = raw.width
        var grayscale = [UInt8](repeating: 255, count: rawDimension * rawDimension)
        try grayscale.withUnsafeMutableBytes { buffer in
            guard let bitmap = CGContext(data: buffer.baseAddress, width: rawDimension, height: rawDimension,
                bitsPerComponent: 8, bytesPerRow: rawDimension, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue) else { throw Failure.rendering }
            bitmap.interpolationQuality = .none
            bitmap.draw(raw, in: CGRect(x: 0, y: 0, width: rawDimension, height: rawDimension))
        }
        // CoreImage includes its own quiet border. Normalize to the actual module grid
        // before applying locator geometry and our four-module transparent quiet zone.
        var minX = rawDimension, minY = rawDimension, maxX = -1, maxY = -1
        for y in 0..<rawDimension {
            for x in 0..<rawDimension where grayscale[y * rawDimension + x] < 128 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        let dimension = maxX - minX + 1
        guard (21...177).contains(dimension), (dimension - 21).isMultiple(of: 4),
              maxY - minY + 1 == dimension else { throw Failure.rendering }
        var grid: [UInt8] = []
        grid.reserveCapacity(dimension * dimension)
        for y in minY...maxY {
            grid.append(contentsOf: grayscale[(y * rawDimension + minX)...(y * rawDimension + maxX)])
        }
        let pattern = SubscriptionQRPattern(dimension: dimension, grayscale: grid)
        let scale = max(1, 1024 / pattern.fullDimension)
        let pixels = pattern.fullDimension * scale
        guard let bitmap = CGContext(data: nil, width: pixels, height: pixels,
            bitsPerComponent: 8, bytesPerRow: pixels * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Failure.rendering }
        bitmap.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
        // Fill all paths together so neighboring modules don't acquire compositing seams.
        for path in pattern.paths() { bitmap.addPath(path) }
        bitmap.fillPath()
        guard let cgImage = bitmap.makeImage() else { throw Failure.rendering }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.rendering
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.rendering }
        try Task.checkCancellation()
        return SubscriptionQRShare(png: output as Data, pattern: pattern)
    }
}
