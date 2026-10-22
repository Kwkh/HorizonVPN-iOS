import SwiftUI

/// Deterministic orbital field: one asynchronous canvas, no per-particle Views or timers.
struct ParticleFieldView: View {
    var connected: Bool
    var animating: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var motion: ParticleMotion
    private let count = 240
    private var running: Bool { animating && !reduceMotion }

    init(connected: Bool, animating: Bool) {
        self.connected = connected
        self.animating = animating
        _motion = State(initialValue: ParticleMotion(connected: connected))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: lowPower ? 1.0 / 20 : 1.0 / 60,
                                paused: !running)) { _ in
            let frame = motion.frame(at: ProcessInfo.processInfo.systemUptime)
            let t = frame.time
            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) * 0.34
                let resting = scheme == .dark ? ClashStyle.blue : Color.gray
                let color = resting.mix(with: ClashStyle.accent(scheme), by: frame.connection)
                for ring in 0..<3 {
                    var orbit = Path()
                    let r = radius * (0.82 + Double(ring) * 0.21)
                    orbit.addEllipse(in: CGRect(x: center.x - r, y: center.y - r * 0.52,
                        width: r * 2, height: r * 1.04))
                    var layer = context
                    layer.translateBy(x: center.x, y: center.y)
                    layer.rotate(by: .radians(Double(ring) * 1.05 + t * 0.022))
                    layer.translateBy(x: -center.x, y: -center.y)
                    layer.stroke(orbit, with: .color(color.opacity(0.10)), lineWidth: 0.6)
                }
                for i in 0..<count {
                    let seed = Double(i)
                    let band = i % 3
                    let phase = seed * 2.39996323 + frame.phase * (band == 1 ? -1 : 1)
                    let breathing = 1 + 0.035 * sin(t * 0.7 + seed)
                    let r = radius * (0.70 + 0.30 * fract(seed * 0.6180339)) * breathing
                    let tilt = Double(band) * 1.05 + t * 0.022
                    let a = cos(phase) * r, b = sin(phase) * r * 0.52
                    let x = center.x + a * cos(tilt) - b * sin(tilt)
                    let y = center.y + a * sin(tilt) + b * cos(tilt)
                    let depth = (sin(phase) + 1) / 2
                    let diameter = 0.75 + depth * 1.75
                    let point = CGRect(x: x, y: y, width: diameter, height: diameter)
                    context.fill(Path(ellipseIn: point), with: .color(color.opacity(0.15 + depth * 0.72)))
                    if i % 12 == 0 {
                        let halo = point.insetBy(dx: -5, dy: -5)
                        context.fill(Path(ellipseIn: halo), with: .radialGradient(
                            Gradient(colors: [color.opacity(0.15), .clear]), center: CGPoint(x: x, y: y), startRadius: 0, endRadius: 7))
                    }
                }
                for i in 0..<36 {
                    let seed = Double(i)
                    let x = fract(seed * 0.754877 + t * 0.001) * size.width
                    let y = fract(seed * 0.56984 - t * 0.002) * size.height
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: .color(color.opacity(0.20)))
                }
            }
        }
        .onAppear { updateMotion(settle: true) }
        .onChange(of: connected) { _, _ in updateMotion() }
        .onChange(of: running) { _, _ in updateMotion() }
        .onDisappear {
            motion.update(connected: connected, running: false, at: ProcessInfo.processInfo.systemUptime)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
    private func updateMotion(settle: Bool = false) {
        motion.update(connected: connected, running: running,
                      at: ProcessInfo.processInfo.systemUptime, settle: settle || !running)
    }
    private func fract(_ value: Double) -> Double { value - floor(value) }
}
