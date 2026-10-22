import AppKit
import QuartzCore

@main struct CheckMacTraffic {
    @MainActor static func main() {
        _ = NSApplication.shared
        let now = ProcessInfo.processInfo.systemUptime
        let points = (0..<60).map { index in
            TrafficPoint(id: now - 60 + Double(index), date: Date(),
                upload: Double(index % 7) * 100_000, download: Double(index % 11) * 80_000, segment: 0)
        }
        for size in [CGSize(width: 220, height: 64), CGSize(width: 900, height: 110)] {
            let view = MacTrafficPlotSurface(frame: CGRect(origin: .zero, size: size))
            view.configure(points: points, running: false, reduceMotion: false, ceiling: 1_000_000, logarithmic: false)
            view.layoutSubtreeIfNeeded()
            precondition(view.layer!.bounds.size == size)
            view.render(at: now)
            let layers = view.layer!.sublayers!.compactMap { $0 as? CAShapeLayer }
            precondition(layers.count == 2)
            let original = layers.map { $0.path! }
            let startOffsets = layers.map { $0.transform.m41 }
            var costs = [Double]()
            for frame in 1...1800 {
                let time = now + Double(frame) / 60
                let start = CACurrentMediaTime()
                view.render(at: time)
                costs.append((CACurrentMediaTime() - start) * 1000)
                for index in layers.indices {
                    // Cache identity, not merely equal shape: ordinary frames do
                    // not allocate/rebuild the Bézier path or invoke SwiftUI.
                    precondition(layers[index].path === original[index])
                    let expected = startOffsets[index] - size.width * (time - now) / TrafficPlotGeometry.window
                    precondition(abs(layers[index].transform.m41 - expected) < 0.000_001)
                    precondition(layers[index].animationKeys()?.isEmpty ?? true)
                }
            }
            costs.sort()
            print("PASS \(Int(size.width))px: 1800 continuous frames, two retained paths; CPU render p95 \(costs[1710]) ms (not measured display FPS)")
            for path in original {
                var curves = 0
                path.applyWithBlock { element in
                    if element.pointee.type == .addQuadCurveToPoint { curves += 1 }
                    else { precondition(element.pointee.type == .moveToPoint) }
                }
                precondition(curves > 60)
            }
            // A normal one-second reply rebuilds once and subsequent frames reuse it.
            let extended = points + [.init(id: now, date: Date(), upload: 700_000, download: 200_000, segment: 0)]
            view.configure(points: extended, running: false, reduceMotion: true, ceiling: 1_000_000, logarithmic: false)
            view.render(at: now + 31)
            let updated = layers.map { $0.path! }
            precondition(updated[0] !== original[0])
            view.render(at: now + 31 + 1.0 / 60)
            precondition(layers[0].path === updated[0])
            view.setFrameSize(CGSize(width: size.width / 2, height: size.height))
            view.layoutSubtreeIfNeeded()
            precondition(view.layer!.bounds.size == view.bounds.size)
            view.render(at: now + 32)
            precondition(layers[0].path !== updated[0])
            // Disconnection and long idle periods keep the tail covering the clip.
            view.configure(points: [], running: false, reduceMotion: true, ceiling: 1_000_000, logarithmic: false)
            for elapsed in [59.0, 61, 130, 600] {
                view.render(at: now + elapsed)
                for layer in layers {
                    let box = layer.path!.boundingBoxOfPath
                    precondition(box.minX + layer.transform.m41 <= 0)
                    precondition(box.maxX + layer.transform.m41 >= view.bounds.width)
                }
            }
            view.stop()
            print("PASS sample insertion, Bézier-only geometry, resize, reduced-motion static rendering and idle-tail coverage")
        }
        print("No VPN, network, real subscription, Keychain or cloud operation was performed.")
    }
}
