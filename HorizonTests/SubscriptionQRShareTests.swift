import Foundation
import Testing
import ImageIO
import CoreGraphics
import SwiftUI
@testable import Horizon

struct SubscriptionQRShareTests {
    @Test func moduleGridAlignsToPhysicalPixelsOnPhoneAndTablet() {
        for density: CGFloat in [2, 3] {
            for dimension in [29, 45, 97, 185] {
                let layout = SubscriptionQRPattern.pixelLayout(size: CGSize(width: 337, height: 360), dimension: dimension, displayScale: density)
                #expect(abs(layout.unit * density - (layout.unit * density).rounded()) < 0.0001)
                #expect(abs(layout.origin.x * density - (layout.origin.x * density).rounded()) < 0.0001)
                #expect(abs(layout.origin.y * density - (layout.origin.y * density).rounded()) < 0.0001)
                #expect(layout.origin.x >= 0 && layout.origin.y >= 0)
                #expect(layout.origin.x + layout.unit * CGFloat(dimension) <= 337)
            }
        }
    }

    @MainActor @Test func actualCanvasHasNoDarkSeamsInsidePartlyRevealedModules() async throws {
        let share = try await SubscriptionQRShare.generate(sourceURL: "https://example.invalid/sub?token=FICTIONAL-SEAMS")
        let pattern = share.pattern
        for density: CGFloat in [2, 3] {
            let side: CGFloat = 337
            let artwork = SubscriptionQRCodeCanvas(paths: pattern.paths().map { Path($0) }, dimension: pattern.fullDimension,
                progress: 0.9, reduceMotion: false)
                .frame(width: side, height: side)
                .environment(\.displayScale, density)
            let renderer = ImageRenderer(content: artwork)
            renderer.scale = density
            let image = try #require(renderer.cgImage)
            var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
            try pixels.withUnsafeMutableBytes { buffer in
                let context = try #require(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            let layout = SubscriptionQRPattern.pixelLayout(size: CGSize(width: side, height: side), dimension: pattern.fullDimension, displayScale: density)
            let unit = Int((layout.unit * density).rounded())
            let originX = Int((layout.origin.x * density).rounded()), originY = Int((layout.origin.y * density).rounded())
            var seams = 0, missingModules = 0
            for module in pattern.modules {
                let x = originX + (module.x + SubscriptionQRPattern.quietZone) * unit
                let y = originY + (module.y + SubscriptionQRPattern.quietZone) * unit
                let centerAlpha = Int(pixels[((y + unit / 2) * image.width + x + unit / 2) * 4 + 3])
                if centerAlpha < 200 { missingModules += 1 }
                for (dx, dy) in [(0, 0), (unit - 1, 0), (0, unit - 1), (unit - 1, unit - 1)] {
                    let edgeAlpha = Int(pixels[((y + dy) * image.width + x + dx) * 4 + 3])
                    if abs(edgeAlpha - centerAlpha) > 1 { seams += 1 }
                }
            }
            #expect(missingModules == 0)
            #expect(seams == 0)
        }
    }

    @Test func imageContainsOnlyWhiteModulesAndTransparentBackground() async throws {
        let share = try await SubscriptionQRShare.generate(sourceURL: "https://example.invalid/sub?token=FICTIONAL")
        let source = try #require(CGImageSourceCreateWithData(share.png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        var opaqueCount = 0, transparentCount = 0, invalidCount = 0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = pixels[offset + 3]
            if alpha == 0 { transparentCount += 1 }
            else {
                opaqueCount += 1
                // Premultiplied white always has RGB == alpha.
                if pixels[offset] != alpha || pixels[offset + 1] != alpha || pixels[offset + 2] != alpha {
                    invalidCount += 1
                }
            }
        }
        #expect(opaqueCount > 0 && transparentCount > 0)
        #expect(invalidCount == 0)
        #expect(pixels[3] == 0) // The quiet zone must not become an opaque plate.
    }

    @Test func constructionStartsEmptyEndsCompleteAndNeverReverses() {
        for group in 0..<SubscriptionQRPattern.groupCount {
            #expect(SubscriptionQRPattern.opacity(progress: 0, group: group) == 0)
            #expect(SubscriptionQRPattern.opacity(progress: 1, group: group) == 1)
            var previous = 0.0
            for step in 0...100 {
                let opacity = SubscriptionQRPattern.opacity(progress: Double(step) / 100, group: group)
                #expect(opacity >= previous && opacity <= 1)
                previous = opacity
            }
        }
        #expect(SubscriptionQRPattern.opacity(progress: 0.3, group: 0) > SubscriptionQRPattern.opacity(progress: 0.3, group: 31))
    }

    @Test func codesRemainReadableAtDifferentDensities() async throws {
        for length in [20, 250, 650] {
            let url = "https://example.invalid/sub?token=" + String(repeating: "test-ONLY-1234567890", count: length / 20)
            let share = try await SubscriptionQRShare.generate(sourceURL: url)
            #expect(try QRCodeImageReader.read(share.png) == url)
            // All three positioning patterns retain their exact module grid.
            let n = share.pattern.dimension
            for (x, y) in [(0, 0), (n - 7, 0), (0, n - 7)] {
                for dy in 0..<7 {
                    for dx in 0..<7 {
                        let filled = dx == 0 || dx == 6 || dy == 0 || dy == 6 || ((2...4).contains(dx) && (2...4).contains(dy))
                        let module = share.pattern.modules.first { $0.x == x + dx && $0.y == y + dy }
                        #expect((module != nil) == filled)
                    }
                }
            }
        }
    }

    @Test func exportedImageCanBeImportedWithoutChangingCredentials() async throws {
        let url = "https://example.invalid/sub?token=FICTIONAL%2B%2F%3D&name=%E4%B8%96%E7%95%8C&x=1&x=2"
        let share = try await SubscriptionQRShare.generate(sourceURL: url)
        #expect(share.png.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]))
        let decoded = try QRCodeImageReader.read(share.png)
        #expect(decoded == url)
    }

    @Test func latestSourceGeneratesDifferentUsableImage() async throws {
        let first = "https://example.invalid/sub?token=FICTIONAL-OLD"
        let latest = "https://example.invalid/sub?token=FICTIONAL-NEW"
        let old = try await SubscriptionQRShare.generate(sourceURL: first)
        let new = try await SubscriptionQRShare.generate(sourceURL: latest)
        #expect(old.png != new.png)
        #expect(try QRCodeImageReader.read(new.png) == latest)
    }

    @Test func missingAndUnsupportedSourcesCannotBeShared() {
        for source: String? in [nil, "", "http://example.invalid/sub", "ss://example.invalid", "https://user:password@example.invalid/sub"] {
            #expect(throws: (any Error).self) { try SubscriptionQRShare.sourceURL(source) }
        }
    }

    @Test func oversizedLinkFailsExplicitlyInsteadOfTruncatingToken() async {
        do {
            _ = try await SubscriptionQRShare.generate(sourceURL: "https://example.invalid/sub?token=" + String(repeating: "a", count: 2500))
            Issue.record("An oversized link must not be truncated or exported")
        } catch {
            #expect(error as? SubscriptionQRShare.Failure == .tooLong)
        }
    }

    @MainActor @Test func sourceIsReadFromLatestSavedRecordWithoutChangingConfiguration() async throws {
        let repository = SubscriptionRepository(storage: MemorySubscriptionStorage())
        let source = Data(PrototypeSelfCheck.fixture.utf8)
        let id = try repository.add(.init(source: source), fileName: "Example.yaml",
            nodeCount: 1, groupCount: 1, ruleCount: 1, makeCurrent: false)
        let tunnel = TunnelController(repository: repository, permitsNetwork: false,
            network: NetworkAvailability(initialStatus: .available, monitorSystem: false))
        await #expect(throws: (any Error).self) { try await tunnel.loadSubscriptionShareURL(id) }
        let latest = "https://example.invalid/sub?token=FICTIONAL-LATEST"
        try repository.replace(id, expected: repository.record(id), source: source,
            choices: [:], sourceURL: latest, nodeCount: 1, groupCount: 1, ruleCount: 1)
        let before = try repository.library()
        #expect(try await tunnel.loadSubscriptionShareURL(id) == latest)
        let after = try repository.library()
        #expect(after.entries == before.entries)
        #expect(after.activeID == before.activeID)
        #expect(!tunnel.isTunnelActive && !tunnel.hasProfile)
    }
}
