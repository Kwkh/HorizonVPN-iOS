import Foundation
import CoreGraphics
import simd

/// Fixed illustrative objects in one world, viewed through a continuous dolly move.
/// These are UI demonstrations, not nodes or traffic from the user's configuration.
enum HorizonGuideGeometry {
    struct Face { let points: [SIMD3<Float>]; var chapter: Int = 0 }
    static let spacing: Float = 7
    static let faces: [Face] = {
        var result: [Face] = []
        for index in 0..<3 {
            result += box(center:.zero,size:[1.0,1.65,0.10]).map { face in
                Face(points:face.points.map { cardPoint(index,local:$0) })
            }
        }
        for row in 0..<4 {
            for column in 0..<7 {
                result += box(center: [14+Float(column-3)*0.75+(row % 2 == 0 ? 0 : 0.18), Float(row)*0.38-1.4, 0], size: [0.70,0.34,0.28]).map { Face(points: $0.points, chapter: 2) }
            }
        }
        return result
    }()
    // Follow the wall dimensions, with a small lead-in above its top edge.
    static let wallSwipeEndpoints: (top: SIMD3<Float>, bottom: SIMD3<Float>) = {
        let points = faces.filter { $0.chapter == 2 }.flatMap(\.points)
        let front = (points.map(\.z).max() ?? 0) + 0.01
        return ([14, (points.map(\.y).max() ?? 0) + 0.18, front],
                [14, points.map(\.y).min() ?? 0, front])
    }()
    static let particles: [SIMD3<Float>] = {
        let chapters: [SIMD3<Float>] = (0..<180).map { index in
            let seed = Float(index+1)
            return [hash(seed)*24-5, hash(seed+37)*7-3.5, hash(seed+71)*7-5]
        }
        // Extend the same world to the welcome camera; don't reseed chapter dots.
        let welcome: [SIMD3<Float>] = (0..<72).map { index in
            let seed = Float(index+181)
            return [hash(seed)*7-12, hash(seed+37)*7-3.5, hash(seed+71)*7-5]
        }
        return chapters+welcome
    }()
    // Three corners at distinct depths, with the lower hub as the fourth
    // non-coplanar vertex. Keep the open, three-spoke silhouette.
    static let nodes: [SIMD3<Float>] = [[5.55,0.72,0.55], [7.12,1.34,-1.65], [8.30,0.38,1.05]]
    static let hub: SIMD3<Float> = [7,-0.42,0.12]
    static let globe = SIMD4<Float>(14,0.75,-2.2,1.65)

    static func cardPoint(_ index: Int, local: SIMD3<Float>) -> SIMD3<Float> {
        let yaw: [Float] = [-0.22,0.07,0.25]
        let pitch: [Float] = [0.07,-0.05,0.09]
        let roll: [Float] = [0.045,-0.025,-0.055]
        let orientation = simd_quatf(angle:yaw[index],axis:[0,1,0])
            * simd_quatf(angle:pitch[index],axis:[1,0,0])
            * simd_quatf(angle:roll[index],axis:[0,0,1])
        return [Float(index-1)*1.2,Float(index % 2)*0.24,-Float(index)*0.28] + orientation.act(local)
    }

    static func particle(_ original: SIMD3<Float>, index: Int, time: Float) -> SIMD3<Float> {
        let seed = Float(index)
        // Continuous paths, with no wrapping/reseeding at a viewport boundary.
        return original + [sin(time*0.38+seed)*0.48,
                           sin(time*0.29+seed*0.73)*0.42,
                           cos(time*0.24+seed*0.41)*0.30]
    }
    static func parallax(_ offset: SIMD2<Float>) -> SIMD3<Float> {
        [offset.x*1.40,offset.y*1.00,0]
    }
    static func camera(focus: Double) -> (eye: SIMD3<Float>, target: SIMD3<Float>) {
        let focus = Float(min(2, max(-1, focus)))
        let wave = sin((focus-floor(focus)) * .pi)
        let travel = wave*wave
        return ([focus*spacing+0.18, 0.8+0.3*travel, 6.4+0.7*travel], [focus*spacing,0,0])
    }
    static func bridge(focus: Double, entry: Double, tilt: SIMD2<Float>, progress: Double,
                       aspect: Float) -> (eye: SIMD3<Float>, target: SIMD3<Float>, globe: SIMD4<Float>) {
        let t = Float(min(1,max(0,progress)))
        var from = camera(focus:focus)
        from.eye.z += Float(1-entry)*1.2
        from.eye += parallax(tilt)
        let destination = HorizonGeometry.camera(journey:1)
        let offset = SIMD3<Float>(14,0,0)
        var sphere = HorizonGeometry.introductionGlobe(aspect:aspect)
        sphere.x += 14
        return (from.eye+(destination.eye+offset-from.eye)*t,
                from.target+(destination.target+offset-from.target)*t,
                globe+(sphere-globe)*t)
    }
    private static func box(center: SIMD3<Float>, size: SIMD3<Float>) -> [Face] {
        let a=center-size/2, b=center+size/2
        let points: [SIMD3<Float>] = [[a.x,a.y,a.z],[b.x,a.y,a.z],[b.x,b.y,a.z],[a.x,b.y,a.z],
                                     [a.x,a.y,b.z],[b.x,a.y,b.z],[b.x,b.y,b.z],[a.x,b.y,b.z]]
        return [[0,1,2,3],[4,7,6,5],[0,4,5,1],[3,2,6,7],[0,3,7,4],[1,5,6,2]].map { Face(points: $0.map { points[$0] }) }
    }
    private static func hash(_ value: Float) -> Float {
        let n=sin(value*127.1+311.7)*43758.5453
        return n-floor(n)
    }
}

struct HorizonGuideClock {
    private var started = Date()
    private var accumulated: TimeInterval = 0
    private var running = false
    mutating func setRunning(_ next: Bool, now: Date = Date()) {
        guard next != running else { return }
        accumulated = elapsed(at: now)
        started = now
        running = next
    }
    func elapsed(at date: Date) -> TimeInterval {
        accumulated + (running ? max(0, date.timeIntervalSince(started)) : 0)
    }
}

/// Shared only by the guide and its drawing surface; no per-frame view notifications.
final class HorizonGuidePlayback {
    let clock = HorizonSceneClock()
    private var transitionClock = HorizonGuideClock()
    private var transition: HorizonGuideTransition?
    private var lastPresented: HorizonGuidePresentation?
    private var forceEndpoint = false
    private var pullMotion = HorizonGuidePullMotion()
    func setRunning(_ running: Bool) {
        clock.setRunning(running)
        transitionClock.setRunning(running && transition != nil)
    }
    func elapsed(at date: Date = Date()) -> Float { Float(clock.elapsed(at:date)) }
    var rotation: Double { -0.4+Double(elapsed())*0.055 }
    func presented(_ frame: HorizonGuidePresentation) { lastPresented = frame }
    func beginTransition(to destination: CGRect) -> Bool {
        guard let source = lastPresented, !destination.isEmpty else { return false }
        transition = HorizonGuideTransition(source:source,destination:destination)
        transitionClock.setRunning(true)
        return true
    }
    func transitionFrame(at date: Date) -> HorizonGuidePresentation? {
        guard var frame = transition?.sample(elapsed:forceEndpoint ? HorizonGuideTransition.duration : transitionClock.elapsed(at:date)) else { return nil }
        frame.time = Float(clock.elapsed(at:date))
        return frame
    }
    var presentedProgress: Double { lastPresented?.progress ?? 0 }
    var interactiveRestingAtStart: Bool { pullMotion.atStart }
    func beginInteractiveTransition(to destination: CGRect) -> Bool {
        guard beginTransition(to:destination) else { return false }
        pullMotion = HorizonGuidePullMotion()
        _ = pullMotion.sample(at:clock.elapsed())
        return true
    }
    func targetInteractiveProgress(_ value: Double) { pullMotion.setTarget(value) }
    func interactiveFrame(at date: Date) -> HorizonGuidePresentation? {
        let progress = pullMotion.sample(at:clock.elapsed(at:date))
        guard var frame = transition?.sample(progress:progress) else { return nil }
        frame.time = Float(clock.elapsed(at:date))
        return frame
    }
    func cancelTransition() {
        transition = nil
        transitionClock = HorizonGuideClock()
        forceEndpoint = false
        pullMotion = HorizonGuidePullMotion()
    }
    func resizeTransition(source: CGRect, destination: CGRect) {
        guard transition != nil, !source.isEmpty, !destination.isEmpty else { return }
        transition?.source.viewport = source
        transition?.destination = destination
    }
    func finishImmediately() { forceEndpoint = true }
}
