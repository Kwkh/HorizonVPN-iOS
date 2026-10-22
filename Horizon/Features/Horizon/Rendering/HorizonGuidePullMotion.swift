import Foundation

/// A single physical follower owns position/velocity across dragging, release
/// and re-grab. SwiftUI animation retargeting cannot enforce acceleration limits.
struct HorizonGuidePullMotion {
    static let maximumAcceleration = 1.8 // normalized scene progress / second²
    static let maximumSpeed = 0.65
    // Finish the imperceptible exponential tail, then present the exact endpoint.
    // The guide projection regression keeps this correction below half a point.
    static let settlingDistance = 0.0002
    static let settlingSpeed = 0.001
    private(set) var position = 0.0
    private(set) var velocity = 0.0
    private(set) var target = 0.0
    private var lastTime: Double?

    var atStart: Bool { target == 0 && position == 0 && velocity == 0 }
    mutating func setTarget(_ value: Double) { target = min(1,max(0,value)) }

    mutating func sample(at time: Double) -> Double {
        defer { lastTime = time }
        guard let lastTime else { return position }
        // A stalled frame or background resume must not fast-forward the camera.
        var remaining = min(1.0/20,max(0,time-lastTime))
        while remaining > 0 {
            let dt = min(1.0/240,remaining)
            let error = target-position
            // Return promptly without relaxing speed/acceleration limits or the
            // exact rendered-endpoint requirement for revealing UI.
            let response = target == 0 ? 12.0 : 4.0
            // Leave braking distance before the endpoint at the quicker return
            // response, rather than correcting an overshoot after it happens.
            let brakingSpeed = sqrt(2*Self.maximumAcceleration*abs(error))*(target == 0 ? 0.75 : 1)
            let desiredSpeed = min(Self.maximumSpeed,min(abs(error)*response,brakingSpeed))
            let desiredVelocity = error < 0 ? -desiredSpeed : desiredSpeed
            let acceleration = min(Self.maximumAcceleration,max(-Self.maximumAcceleration,(desiredVelocity-velocity)/dt))
            let nextVelocity = velocity+acceleration*dt
            position += (velocity+nextVelocity)*0.5*dt
            velocity = nextVelocity
            // Only settle at subpixel distance and near-zero speed. A reversal
            // retains inertia instead of snapping to the new target on release.
            if abs(target-position) < Self.settlingDistance && abs(velocity) < Self.settlingSpeed {
                position = target
                velocity = 0
            }
            remaining -= dt
        }
        return min(1,max(0,position))
    }
}
