import Foundation
import simd

/// Temporary user rotation layered over the uninterrupted automatic rotation.
struct HorizonGlobeInteraction {
    private(set) var orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
    private(set) var isDragging = false
    private var origin = simd_quatf(angle: 0, axis: [0, 1, 0])
    private var returnElapsed: Double = 1
    var isReturning: Bool { !isDragging && returnElapsed < 1 }

    mutating func begin() {
        origin = orientation
        isDragging = true
        returnElapsed = 1
    }
    mutating func drag(translation: SIMD2<Float>, diameter: Float) {
        guard isDragging else { return }
        let angles = translation / max(80, diameter) * .pi
        let yaw = simd_quatf(angle: angles.x, axis: [0, 1, 0])
        let pitch = simd_quatf(angle: angles.y, axis: [1, 0, 0])
        orientation = simd_normalize(yaw * pitch * origin)
    }
    mutating func end(animated: Bool) {
        guard isDragging else { return }
        isDragging = false
        origin = orientation
        returnElapsed = 0
        if !animated { reset() }
    }
    mutating func advance(_ seconds: Double) {
        guard isReturning else { return }
        returnElapsed = min(1, returnElapsed + max(0, seconds)/0.9)
        let t = Float(returnElapsed)
        let easing = t*t*t*(t*(t*6-15)+10)
        orientation = simd_slerp(origin, simd_quatf(angle: 0, axis: [0, 1, 0]), easing)
    }
    mutating func reset() { self = Self() }
}
