import Foundation
import simd

/// Sensor-independent, bounded parallax. A long suspension must not produce a leap.
struct GuideTiltFilter {
    private(set) var value = SIMD2<Double>.zero
    mutating func update(angles: SIMD2<Double>, delta: TimeInterval, recentering: Bool = false) -> SIMD2<Double> {
        guard angles.x.isFinite, angles.y.isFinite, delta.isFinite else { return value }
        let limit = 0.30 // About 17 degrees reaches the maximum camera offset.
        var target = angles / limit
        let length = simd_length(target)
        if length > 1 { target /= length }
        let alpha = 1 - exp(-min(1.0 / 15, max(0, delta)) / (recentering ? 0.55 : 0.20))
        value += (target - value) * alpha
        return value
    }
}

/// Rebase only after a sustained still hold. Keep this sensor-independent so
/// gyro noise, slow drift and interruptions can be checked without a phone.
struct GuideTiltNeutral {
    private(set) var attitude = simd_quatd(angle:0,axis:[0,1,0])
    private(set) var isRecentering = false
    private var anchor: simd_quatd?
    private var stableTime = 0.0

    mutating func reset(to sample: simd_quatd) {
        attitude = sample
        anchor = sample
        stableTime = 0
        isRecentering = false
    }
    mutating func update(sample: simd_quatd, angularSpeed: Double, delta: Double) {
        guard sample.vector.x.isFinite, sample.vector.y.isFinite,
              sample.vector.z.isFinite, sample.vector.w.isFinite,
              angularSpeed.isFinite, delta.isFinite else { return }
        guard let anchor else { reset(to:sample); return }
        // q and -q describe the same orientation. Bound accumulated drift too:
        // a slow deliberate tilt must not look like a stationary phone.
        // 0.004 rad keeps the same drift tolerance per second at a 0.4 s dwell.
        let separation = 2*acos(min(1,abs(simd_dot(anchor.vector,sample.vector))))
        guard delta > 0, delta < 0.2, angularSpeed < 0.04, separation < 0.004 else {
            self.anchor = sample
            stableTime = 0
            isRecentering = false
            return
        }
        stableTime += delta
        if stableTime >= 0.4 && !isRecentering {
            attitude = sample
            isRecentering = true
        }
    }
}
