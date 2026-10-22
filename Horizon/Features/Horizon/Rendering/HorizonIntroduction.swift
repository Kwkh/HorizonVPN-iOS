import Foundation

/// A presentation-only timeline. Never changes or infers VPN state.
struct HorizonIntroduction {
    struct Pose: Equatable {
        var journey: Double = 1
        var formation: Double = 1
        var wall: Double = 0
        var globeBlend: Double = 0
        var particles: Double = 0
    }
    private(set) var elapsed: Double = 0
    private(set) var pose = Pose()
    private(set) var finished = false
    private var tailStart: Pose?
    private var tailElapsed: Double = 0
    private var tailDuration: Double = 2.4
    private var destination: HorizonMotion.Phase
    private var reduced: Bool
    private let continuesGlobe: Bool

    init(destination: HorizonMotion.Phase, reduced: Bool, continuesGlobe: Bool = false) {
        self.destination = destination
        self.reduced = reduced
        self.continuesGlobe = continuesGlobe
        if continuesGlobe { pose.particles = 1 }
        if reduced {
            pose = Self.endpoint(destination)
            pose.particles = 0
            tailStart = pose
            tailDuration = 0.4
        }
    }

    mutating func advance(_ seconds: Double, destination: HorizonMotion.Phase, reduced: Bool, skip: Bool) {
        guard !finished else { return }
        let dt = min(0.1, max(0, seconds))
        elapsed += dt
        if reduced && !self.reduced {
            // Accessibility changes must not leave a spatial animation running.
            self.reduced = true
            pose = Self.endpoint(destination)
            pose.particles = 0
            beginTail(destination: destination, duration: 0.4)
        } else if tailStart != nil && self.destination != destination {
            // Rebase from the displayed pose if the real tunnel changes during the outro.
            beginTail(destination: destination, duration: 0.8)
        } else if skip && tailDuration > 0.45 {
            beginTail(destination: destination, duration: 0.45)
        }
        if let start = tailStart {
            tailElapsed += dt
            let t = Self.ease(tailElapsed / tailDuration)
            let end = Self.endpoint(destination)
            pose = Self.interpolate(start, end, t)
            if tailElapsed >= tailDuration { pose = end; finished = true }
        } else {
            pose.particles = continuesGlobe ? 1 : Self.ease(elapsed / 0.55)
            // A continued globe is already visible: don't replay its fade-in
            // waiting period. The initial matched frame still has no wall.
            let wallDelay = continuesGlobe ? 0.0 : 0.6
            // Each brick eases locally; a linear clock preserves the stagger spacing.
            pose.wall = min(1, max(0, (elapsed - wallDelay) / 2))
            if elapsed >= wallDelay + 2 { beginTail(destination: destination, duration: 2.4) }
        }
    }

    private mutating func beginTail(destination: HorizonMotion.Phase, duration: Double) {
        tailStart = pose
        tailElapsed = 0
        tailDuration = duration
        self.destination = destination
    }
    private static func endpoint(_ phase: HorizonMotion.Phase) -> Pose {
        let outside = phase != .idle && phase != .disconnecting
        return Pose(journey: outside ? 1 : 0, formation: phase == .connected ? 1 : 0,
                    wall: 1, globeBlend: 1, particles: outside ? 1 : 0)
    }
    private static func interpolate(_ a: Pose, _ b: Pose, _ t: Double) -> Pose {
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        // Dissolve before the camera finishes returning, using the same continuous tail.
        let dissolve = min(1, t * 1.8)
        return Pose(journey: mix(a.journey, b.journey),
                    formation: a.formation + (b.formation - a.formation) * dissolve,
                    wall: mix(a.wall, b.wall), globeBlend: mix(a.globeBlend, b.globeBlend),
                    particles: a.particles + (b.particles - a.particles) * dissolve)
    }
    private static func ease(_ raw: Double) -> Double {
        let t = min(1, max(0, raw))
        return t*t*t*(t*(t*6-15)+10)
    }
}
