#if os(macOS)
import SwiftUI
import AppKit
import QuartzCore

struct MacScrollingTrafficPlot: NSViewRepresentable {
    let points: [TrafficPoint]
    let running: Bool
    let reduceMotion: Bool
    let ceiling: Double
    let logarithmic: Bool

    func makeNSView(context: Context) -> MacTrafficPlotSurface { MacTrafficPlotSurface() }
    func updateNSView(_ view: MacTrafficPlotSurface, context: Context) {
        view.configure(points: points, running: running, reduceMotion: reduceMotion,
                       ceiling: ceiling, logarithmic: logarithmic)
    }
    static func dismantleNSView(_ view: MacTrafficPlotSurface, coordinator: Void) { view.stop() }
}

/// Retains two Bézier paths, moving them in display-synchronized frames instead
/// of rebuilding a SwiftUI Canvas every tick. Telemetry keeps its real cadence.
final class MacTrafficPlotSurface: NSView {
    private let upload = CAShapeLayer()
    private let download = CAShapeLayer()
    private var points: [TrafficPoint] = []
    private var clock: CADisplayLink?
    private var enabled = false
    private var reduced = false
    private var geometryDirty = true
    private var geometryEnd: Double = 0
    private var geometrySize: CGSize = .zero
    private var axis = TrafficPlotGeometry.Axis()
    private var renderedAxis = TrafficPlotGeometry.Axis.Value()
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let backing = CALayer()
        backing.masksToBounds = true
        backing.isGeometryFlipped = true
        layer = backing
        wantsLayer = true
        for shape in [download, upload] {
            shape.fillColor = nil
            shape.lineWidth = 1.8
            shape.lineCap = .round
            shape.lineJoin = .round
            backing.addSublayer(shape)
        }
        download.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
        upload.strokeColor = NSColor.white.withAlphaComponent(0.38).cgColor
        NotificationCenter.default.addObserver(self, selector: #selector(powerChanged),
            name: .NSProcessInfoPowerStateDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged(_:)),
            name: NSWindow.didChangeOcclusionStateNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(points: [TrafficPoint], running: Bool, reduceMotion: Bool,
                   ceiling: Double, logarithmic: Bool) {
        axis.select(ceiling: ceiling.isFinite && ceiling > 0 ? ceiling : 1_000_000,
                    logarithmic: logarithmic, at: ProcessInfo.processInfo.systemUptime,
                    animated: enabled && running && !reduceMotion && window != nil)
        if self.points != points {
            self.points = points.filter { $0.id.isFinite && $0.upload.isFinite && $0.download.isFinite }
            geometryDirty = true
        }
        enabled = running
        reduced = reduceMotion
        synchronizeClock()
        // Deliver data on the next display frame when running, never mid-frame.
        if clock == nil { render(at: ProcessInfo.processInfo.systemUptime) }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        geometryDirty = true
        synchronizeClock()
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        geometryDirty = true
        if clock == nil { render(at: ProcessInfo.processInfo.systemUptime) }
    }
    override func layout() {
        super.layout()
        if geometrySize != bounds.size {
            geometrySize = bounds.size
            geometryDirty = true
        }
        if clock == nil { render(at: ProcessInfo.processInfo.systemUptime) }
    }
    func stop() { clock?.invalidate(); clock = nil }
    private func synchronizeClock() {
        guard enabled, !reduced, let window, window.occlusionState.contains(.visible) else {
            stop(); return
        }
        guard clock == nil else { return }
        let link = displayLink(target: MacTrafficDisplayTarget(self), selector: #selector(MacTrafficDisplayTarget.tick(_:)))
        clock = link
        updateFrameRate()
        link.add(to: .main, forMode: .common)
    }
    @objc private func powerChanged() { updateFrameRate() }
    @objc private func visibilityChanged(_ notification: Notification) {
        guard let changed = notification.object as? NSWindow, changed === window else { return }
        synchronizeClock()
    }
    private func updateFrameRate() {
        let rate: Float = ProcessInfo.processInfo.isLowPowerModeEnabled ? 30 : 60
        clock?.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
    }
    fileprivate func step(_ link: CADisplayLink) {
        let lead = min(1.0 / 15, max(0, link.targetTimestamp - CACurrentMediaTime()))
        render(at: ProcessInfo.processInfo.systemUptime + lead)
    }
    func render(at now: Double) {
        guard bounds.width > 0, bounds.height > 4 else { return }
        let end = now - TrafficPlotGeometry.presentationDelay
        let currentAxis = axis.value(at: now)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if geometryDirty || geometrySize != bounds.size || currentAxis != renderedAxis
            || end - geometryEnd >= TrafficPlotGeometry.window {
            geometryDirty = false
            geometrySize = bounds.size
            renderedAxis = currentAxis
            geometryEnd = end
            let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            upload.contentsScale = scale
            download.contentsScale = scale
            upload.path = path(end: end, axis: currentAxis, value: { $0.upload })
            download.path = path(end: end, axis: currentAxis, value: { $0.download })
        }
        let transform = CATransform3DMakeTranslation(-bounds.width * (end - geometryEnd) / TrafficPlotGeometry.window, 0, 0)
        upload.transform = transform
        download.transform = transform
        CATransaction.commit()
    }
    private func path(end: Double, axis: TrafficPlotGeometry.Axis.Value, value: (TrafficPoint) -> Double) -> CGPath {
        let samples = points.map { CGPoint(x: $0.id, y: value($0)) }
        let vertices = TrafficPlotGeometry.plotVertices(samples, baseline: 0, end: end).map {
            CGPoint(x: TrafficPlotGeometry.x(uptime: $0.x, end: end, width: bounds.width),
                    y: bounds.height - 2 - TrafficPlotGeometry.normalizedHeight(rate: $0.y,
                        ceiling: axis.ceiling, logarithmicWeight: axis.logarithmicWeight) * (bounds.height - 4))
        }
        let path = CGMutablePath()
        path.move(to: vertices[0])
        for segment in TrafficPlotGeometry.roundedSegments(vertices) {
            path.addQuadCurve(to: segment.end, control: segment.control)
        }
        return path
    }
}

private final class MacTrafficDisplayTarget: NSObject {
    weak var owner: MacTrafficPlotSurface?
    init(_ owner: MacTrafficPlotSurface) { self.owner = owner }
    @objc func tick(_ link: CADisplayLink) { owner?.step(link) }
}
#endif
