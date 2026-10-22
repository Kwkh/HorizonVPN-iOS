import Foundation
import CoreGraphics

/// Module geometry is shared by the animated artwork and the exported PNG.
nonisolated struct SubscriptionQRPattern: Sendable {
    nonisolated struct Module: Sendable {
        let x: Int
        let y: Int
        let group: Int

        var rect: CGRect {
            CGRect(x: x + SubscriptionQRPattern.quietZone, y: y + SubscriptionQRPattern.quietZone, width: 1, height: 1)
        }
    }
    static let quietZone = 4
    static let groupCount = 32
    let dimension: Int
    let modules: [Module]
    var fullDimension: Int { dimension + Self.quietZone * 2 }

    init(dimension: Int, grayscale: [UInt8]) {
        self.dimension = dimension
        var modules: [Module] = []
        for y in 0..<dimension {
            for x in 0..<dimension where grayscale[y * dimension + x] < 128 {
                // Choose once per generation, independently of position; rendering reuses it.
                let group = Int.random(in: 0..<Self.groupCount)
                modules.append(.init(x: x, y: y, group: group))
            }
        }
        self.modules = modules
    }

    func paths() -> [CGPath] {
        let groups = (0..<Self.groupCount).map { _ in CGMutablePath() }
        for module in modules {
            groups[module.group].addRect(module.rect)
        }
        return groups
    }

    static func pixelLayout(size: CGSize, dimension: Int, displayScale: CGFloat) -> (unit: CGFloat, origin: CGPoint) {
        let density = max(1, displayScale)
        let available = min(size.width, size.height) * density
        let pixelsPerModule = floor(available / CGFloat(dimension))
        let unit = pixelsPerModule >= 1 ? pixelsPerModule / density : available / CGFloat(dimension) / density
        let side = CGFloat(dimension) * unit
        let origin = CGPoint(x: floor((size.width - side) * density / 2) / density,
                             y: floor((size.height - side) * density / 2) / density)
        return (unit, origin)
    }

    static func opacity(progress: Double, group: Int) -> Double {
        let delay = 0.65 * Double(group) / Double(Self.groupCount - 1)
        let local = min(1, max(0, (progress - delay) / 0.35))
        return 1 - pow(1 - local, 3)
    }
}
