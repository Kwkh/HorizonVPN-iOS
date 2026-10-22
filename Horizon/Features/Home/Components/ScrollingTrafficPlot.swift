import SwiftUI
import UIKit

/// Two persistent shape layers. The display clock translates the whole plot independently
/// of the one-second telemetry cadence; sample insertion never starts a SwiftUI transition.
struct ScrollingTrafficPlot: UIViewRepresentable {
    let points: [TrafficPoint]
    let uploadColor: Color
    let downloadColor: Color
    let running: Bool
    let reduceMotion: Bool
    var ceiling: Double = 1_000_000
    var logarithmic = false

    func makeUIView(context: Context) -> TrafficPlotSurface { TrafficPlotSurface() }
    func updateUIView(_ view: TrafficPlotSurface, context: Context) {
        view.configure(points: points, upload: UIColor(uploadColor), download: UIColor(downloadColor),
                       running: running, reduceMotion: reduceMotion, ceiling: ceiling, logarithmic: logarithmic)
    }
    static func dismantleUIView(_ view: TrafficPlotSurface, coordinator: Void) { view.stop() }
}

final class TrafficPlotSurface: UIView {
    private let upload = CAShapeLayer()
    private let download = CAShapeLayer()
    private var points: [TrafficPoint] = []
    private var displayLink: CADisplayLink?
    private var enabled = false
    private var reduced = false
    private var geometryDirty = true
    private var geometryEnd: Double = 0
    private var geometrySize: CGSize = .zero
    private var axis = TrafficPlotGeometry.Axis()
    private var renderedAxis = TrafficPlotGeometry.Axis.Value()
    private var lowPower = false
    #if DEBUG
    private var metrics = TrafficPlotMetrics()
    #endif

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        clipsToBounds = true
        isUserInteractionEnabled = false
        for shape in [download, upload] {
            shape.fillColor = nil
            shape.lineWidth = 1.8
            shape.lineCap = .round
            shape.lineJoin = .round
            layer.addSublayer(shape)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(powerChanged),
            name: .NSProcessInfoPowerStateDidChange, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func configure(points: [TrafficPoint], upload: UIColor, download: UIColor,
                   running: Bool, reduceMotion: Bool, ceiling: Double, logarithmic: Bool) {
        let nextCeiling = ceiling.isFinite && ceiling > 0 ? ceiling : 1_000_000
        axis.select(ceiling: nextCeiling, logarithmic: logarithmic,
                    at: ProcessInfo.processInfo.systemUptime,
                    animated: enabled && running && !reduceMotion && window != nil)
        if self.points != points {
            self.points = points.filter { $0.id.isFinite && $0.upload.isFinite && $0.download.isFinite }
            geometryDirty = true
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.upload.strokeColor = upload.cgColor
        self.download.strokeColor = download.cgColor
        CATransaction.commit()
        // Reading IPC history must not pause and then jump the presentation clock.
        // Previously plotted history keeps scrolling while a reply is pending.
        enabled = running
        reduced = reduceMotion
        synchronizeClock()
        // While animating, updates are committed on the next display frame, not mid-frame.
        if displayLink == nil { render(at: ProcessInfo.processInfo.systemUptime) }
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        geometryDirty = true
        synchronizeClock()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if geometrySize != bounds.size {
            geometrySize = bounds.size
            geometryDirty = true
        }
        if displayLink == nil { render(at: ProcessInfo.processInfo.systemUptime) }
    }
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        #if DEBUG
        metrics.pause()
        #endif
    }
    private func synchronizeClock() {
        guard enabled, !reduced, window != nil else { stop(); return }
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: WeakDisplayTarget(self), selector: #selector(WeakDisplayTarget.tick(_:)))
        displayLink = link
        updateFrameRate()
        link.add(to: .main, forMode: .common)
    }
    @objc private func powerChanged() { updateFrameRate() }
    private func updateFrameRate() {
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let rate: Float = lowPower ? 30 : 60
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
    }
    fileprivate func step(_ link: CADisplayLink) {
        // Same monotonic timebase as the extension, projected to this display frame.
        let lead = min(1.0 / 15, max(0, link.targetTimestamp - CACurrentMediaTime()))
        let now = ProcessInfo.processInfo.systemUptime + lead
        #if DEBUG
        let start = CACurrentMediaTime()
        #endif
        render(at: now)
        #if DEBUG
        metrics.record(renderSeconds: CACurrentMediaTime() - start, timestamp: link.timestamp,
                       interval: link.targetTimestamp - link.timestamp)
        #endif
    }
    func render(at now: Double) {
        guard bounds.width > 0, bounds.height > 4 else { return }
        let end = now - TrafficPlotGeometry.presentationDelay
        let currentAxis = axis.value(at: now)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Idle data can remain identical for minutes. Replenish the offscreen
        // zero tail before its cached endpoint scrolls into the visible window.
        if geometryDirty || currentAxis != renderedAxis || end - geometryEnd >= TrafficPlotGeometry.window {
            geometryDirty = false
            renderedAxis = currentAxis
            geometryEnd = end
            let contentsScale = window?.screen.scale ?? traitCollection.displayScale
            upload.contentsScale = contentsScale
            download.contentsScale = contentsScale
            upload.path = path(end: end, axis: currentAxis, value: { $0.upload })
            download.path = path(end: end, axis: currentAxis, value: { $0.download })
        }
        let dx = -bounds.width * (end - geometryEnd) / TrafficPlotGeometry.window
        let transform = CATransform3DMakeTranslation(dx, 0, 0)
        upload.transform = transform
        download.transform = transform
        CATransaction.commit()
    }
    private func path(end: Double, axis: TrafficPlotGeometry.Axis.Value, value: (TrafficPoint) -> Double) -> CGPath {
        let path = CGMutablePath()
        let baseline = bounds.height - 2
        let height = bounds.height - 4
        func position(_ time: Double, _ rate: Double) -> CGPoint {
            CGPoint(x: TrafficPlotGeometry.x(uptime: time, end: end, width: bounds.width),
                    y: baseline - TrafficPlotGeometry.normalizedHeight(rate: rate, ceiling: axis.ceiling,
                        logarithmicWeight: axis.logarithmicWeight) * height)
        }
        // Construct idle guards in time coordinates, independent of frame width
        // and scrolling phase; all joins then use the same quadratic Bézier path.
        let samples = points.map { CGPoint(x: $0.id, y: value($0)) }
        let vertices = TrafficPlotGeometry.plotVertices(samples, baseline: 0, end: end)
            .map { position($0.x, $0.y) }
        path.move(to: vertices[0])
        for segment in TrafficPlotGeometry.roundedSegments(vertices) {
            path.addQuadCurve(to: segment.end, control: segment.control)
        }
        return path
    }
}

private final class WeakDisplayTarget: NSObject {
    weak var owner: TrafficPlotSurface?
    init(_ owner: TrafficPlotSurface) { self.owner = owner }
    @objc func tick(_ link: CADisplayLink) { owner?.step(link) }
}
