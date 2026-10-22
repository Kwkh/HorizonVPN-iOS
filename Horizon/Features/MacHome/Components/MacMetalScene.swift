#if os(macOS)
import SwiftUI
import MetalKit

// The renderer keeps its existing UIKit-facing API; these narrow adapters make
// the same geometry, shaders, clocks and particle pass available on AppKit.
extension MTKView {
    var contentScaleFactor: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }
    func setNeedsDisplay() { needsDisplay = true }
}
final class HorizonWallContactGesture {
    var location: CGPoint?
    func point(in view: MTKView) -> CGPoint? { location }
}
@MainActor final class GuideDeviceMotion {
    let offset = SIMD2<Float>.zero
    func run(enabled: Bool) async {}
}

struct MacMetalScene: NSViewRepresentable {
    let phase: HorizonMotion.Phase
    let progress: HorizonSceneProgress
    var active = true
    var animate = true
    var brickScale: Float = 1.5
    var globeScale: Float = 1.3
    var homeGlobeFraming = false
    var wallHoverEnabled = false
    var wallExclusion = CGRect.null
    var introductionID: UUID?
    var holdIntroduction = false
    var skipIntroduction = false
    var guideClock: HorizonSceneClock?
    func makeNSView(context: Context) -> MacMetalSurface {
        let view = MacMetalSurface(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm; view.depthStencilPixelFormat = .depth32Float; view.sampleCount = 4
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.renderer = HorizonRenderer(view: view, progress: progress)
        view.delegate = view.renderer
        return view
    }
    func updateNSView(_ view: MacMetalSurface, context: Context) {
        if !active { view.cancelContact() }
        view.homeGlobeFraming = homeGlobeFraming && introductionID == nil && guideClock == nil
        view.wallExclusion = wallExclusion
        view.renderer?.configure(view: view, phase: phase, active: active, animate: animate,
            brickScale: brickScale, globeScale: globeScale, introductionID: introductionID,
            skipIntroduction: skipIntroduction, holdIntroduction: holdIntroduction,
            guideRotation: guideClock.map { -0.4 + $0.elapsed() * 0.055 }, guideTime: guideClock?.elapsed(), guideClock: guideClock)
        view.wallHoverEnabled = wallHoverEnabled && active && phase == .idle && introductionID == nil && guideClock == nil
        view.updateWallHover()
    }
    static func dismantleNSView(_ view: MacMetalSurface, coordinator: Void) {
        view.cancelContact(); view.isPaused = true; view.delegate = nil; view.renderer = nil
    }
}
final class MacMetalSurface: MTKView {
    var renderer: HorizonRenderer?
    var homeGlobeFraming = false
    private var start: CGPoint?
    private var globe = false
    private var contact = HorizonWallContactGesture()
    var wallHoverEnabled = false
    var wallExclusion = CGRect.null
    private var pointerTracking: NSTrackingArea?
    private var resignObserver: NSObjectProtocol?
    override var isFlipped: Bool { true }
    // The shared renderer requests 60 Hz normally and 30 Hz when constrained.
    // The Mac home scene can use up to 120 Hz on ProMotion; MTKView caps this
    // to the display's cadence. Keep intro, power/thermal limits and mobile as-is.
    override var preferredFramesPerSecond: Int {
        get { super.preferredFramesPerSecond }
        set {
            let rate = newValue == 60 && homeGlobeFraming ? 120 : newValue
            if super.preferredFramesPerSecond != rate { super.preferredFramesPerSecond = rate }
        }
    }
    func framedHomeGlobe(scale: Float, aspect: Float) -> SIMD4<Float>? {
        guard homeGlobeFraming else { return nil }
        return MacHomeGlobeFraming.globe(scale: scale, aspect: aspect, height: Float(bounds.height),
            buttonTop: wallExclusion.isNull ? nil : Float(wallExclusion.minY))
    }
    override func mouseDown(with event: NSEvent) {
        cancelContact()
        let point = convert(event.locationInWindow, from: nil); start = point
        if renderer?.containsGlobe(point, in: self) == true { globe = true; renderer?.beginGlobeDrag(in: self); return }
        updateWallHover(at: point)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        if globe { renderer?.dragGlobe(CGPoint(x: point.x-start.x, y: point.y-start.y), in: self) }
        else { updateWallHover(at: point) }
    }
    override func mouseUp(with event: NSEvent) {
        if globe { renderer?.endGlobeDrag(in: self) }
        start = nil; globe = false
        updateWallHover(at: convert(event.locationInWindow, from: nil))
    }
    override func mouseEntered(with event: NSEvent) { updateWallHover(at: convert(event.locationInWindow, from: nil)) }
    override func mouseMoved(with event: NSEvent) { updateWallHover(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { releaseWallHover() }
    override func updateTrackingAreas() {
        if let pointerTracking { removeTrackingArea(pointerTracking) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self, userInfo: nil)
        pointerTracking = area; addTrackingArea(area)
        super.updateTrackingAreas()
        updateWallHover()
    }
    func updateWallHover() {
        guard let window else { releaseWallHover(); return }
        updateWallHover(at: convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }
    private func updateWallHover(at point: CGPoint) {
        guard wallHoverEnabled, window?.isKeyWindow == true, !globe,
              visibleRect.contains(point), !wallExclusion.contains(point),
              renderer?.containsWall(point, in: self) == true else { releaseWallHover(); return }
        contact.location = point
        renderer?.trackWallContact(contact, in: self)
    }
    private func releaseWallHover() { contact.location = nil; renderer?.endWallContact() }
    func cancelContact() {
        if globe { renderer?.endGlobeDrag(in: self) }
        releaseWallHover(); start = nil; globe = false
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        if let window {
            resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.cancelContact() }
                }
        } else { cancelContact(); isPaused = true }
    }
    override func viewDidHide() { super.viewDidHide(); cancelContact() }
    deinit {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }
}
#endif
