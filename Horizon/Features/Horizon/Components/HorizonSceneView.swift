import SwiftUI
import MetalKit

struct HorizonSceneView: UIViewRepresentable {
    @Environment(AppSettings.self) private var settings
    let progress: HorizonSceneProgress
    let phase: HorizonMotion.Phase
    let active: Bool
    let animate: Bool
    var interactiveJourney: Double? = nil
    var introductionID: UUID? = nil
    var skipIntroduction = false
    var holdIntroduction = false
    var guideRotation: Double? = nil
    var guideTime: Double? = nil
    var guideClock: HorizonSceneClock? = nil
    var introCamera: HorizonIntroCamera? = nil
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> HorizonMetalView {
        let view = HorizonMetalView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.sampleCount = 4
        view.clearColor = MTLClearColorMake(0,0,0,1)
        view.isOpaque = true; view.isUserInteractionEnabled = true
        view.isPaused = true
        context.coordinator.renderer = HorizonRenderer(view: view, progress: progress)
        view.delegate = context.coordinator.renderer
        view.interactionRenderer = context.coordinator.renderer
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.panGlobe(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        context.coordinator.pan = pan
        let contact = HorizonWallContactGesture(target:context.coordinator,action:#selector(Coordinator.contactWall(_:)))
        contact.cancelsTouchesInView = false
        contact.delaysTouchesBegan = false
        contact.delaysTouchesEnded = false
        contact.delegate = context.coordinator
        view.addGestureRecognizer(contact)
        context.coordinator.wallContact = contact
        contact.contactChanged = { [weak coordinator = context.coordinator] gesture in
            coordinator?.contactWall(gesture)
        }
        contact.quickTap = { [weak coordinator = context.coordinator, weak view] point in
            guard let view else { return }
            coordinator?.renderer?.pulseWall(at: view.convert(point, from: nil), in: view)
        }
        if context.coordinator.renderer == nil {
            let label = UILabel(); label.text = settings.text("3D · 暂不可用", "3D · Unavailable"); label.textColor = .white
            label.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(label)
            NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: view.centerXAnchor),label.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
        }
        return view
    }
    func updateUIView(_ view: HorizonMetalView, context: Context) {
        if context.coordinator.renderer == nil {
            (view.subviews.first { $0 is UILabel } as? UILabel)?.text = settings.text("3D · 暂不可用", "3D · Unavailable")
        }
        context.coordinator.wallContact?.isEnabled = active && phase == .idle
            && introductionID == nil && interactiveJourney == nil
        context.coordinator.pan?.isEnabled = active && phase == .connected && introductionID == nil
        context.coordinator.renderer?.configure(view: view,phase: phase,active: active,animate: animate, brickScale: Float(settings.brickScale), globeScale: Float(settings.globeScale), interactiveJourney: interactiveJourney,
            introductionID: introductionID, skipIntroduction: skipIntroduction,
            holdIntroduction: holdIntroduction, guideRotation: guideRotation, guideTime: guideTime,
            guideClock:guideClock, introCamera:introCamera)
        if context.coordinator.renderer == nil, let introductionID {
            // A device without the Metal resources must still reach the usable home.
            DispatchQueue.main.async { progress.completedIntroduction = introductionID }
        }
    }
    static func dismantleUIView(_ view: HorizonMetalView, coordinator: Coordinator) {
        view.isPaused = true; view.delegate = nil; view.interactionRenderer = nil
        if let pan = coordinator.pan { view.removeGestureRecognizer(pan) }
        if let contact = coordinator.wallContact {
            contact.isEnabled = false
            contact.contactChanged = nil
            contact.quickTap = nil
            view.removeGestureRecognizer(contact)
        }
        coordinator.renderer = nil
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var renderer: HorizonRenderer?
        weak var pan: UIPanGestureRecognizer?
        weak var wallContact: HorizonWallContactGesture?
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let view = gestureRecognizer.view as? MTKView else { return false }
            if gestureRecognizer === wallContact {
                return renderer?.containsWall(touch.location(in:view),in:view) == true
            }
            return renderer?.containsGlobe(touch.location(in: view), in: view) == true
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer === wallContact { return true }
            return renderer?.canRotateGlobe == true
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === pan, let scroll = other.view as? UIScrollView, other == scroll.panGestureRecognizer,
                  let view = gestureRecognizer.view else { return false }
            // A drag starting on the globe wins; touches elsewhere go straight to scrolling.
            return view.isDescendant(of: scroll)
        }
        @objc func contactWall(_ gesture: HorizonWallContactGesture) {
            guard let view = gesture.view as? MTKView else { return }
            #if DEBUG
            if ProcessInfo.processInfo.environment["CLASH_HORIZON_PREVIEW"] == "1" {
                print("HORIZON_WALL_CONTACT",gesture.state.rawValue)
            }
            #endif
            switch gesture.state {
            case .possible, .began, .changed: renderer?.trackWallContact(gesture,in:view)
            case .ended, .cancelled, .failed: renderer?.endWallContact()
            default: break
            }
        }
        @objc func panGlobe(_ pan: UIPanGestureRecognizer) {
            guard let view = pan.view as? MTKView else { return }
            #if DEBUG
            if ProcessInfo.processInfo.environment["CLASH_HORIZON_PREVIEW"] == "1" {
                let delta = pan.translation(in: view)
                print("HORIZON_PREVIEW_PAN", pan.state.rawValue, Int(delta.x), Int(delta.y))
            }
            #endif
            switch pan.state {
            case .began:
                renderer?.beginGlobeDrag(in: view)
                renderer?.dragGlobe(pan.translation(in: view), in: view)
            case .changed: renderer?.dragGlobe(pan.translation(in: view), in: view)
            case .ended, .cancelled, .failed: renderer?.endGlobeDrag(in: view)
            default: break
            }
        }
    }
}
