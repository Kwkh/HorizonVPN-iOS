import Foundation
import simd

/// Critically damped attraction follows the contact point. Retargeting preserves
/// position and velocity; movement events never accumulate extra force.
struct HorizonWallTouch {
    private struct Brick {
        let center: SIMD2<Float>
        var height: Float = 0
        var velocity: Float = 0
    }
    private var bricks: [Brick]
    private var radius: SIMD2<Float>
    private var returning = false
    private var contact: SIMD2<Float>?
    private(set) var isActive = false
    static let maximumLift: Float = 0.8

    init(faces: [SIMD4<Float>], scale: Float) {
        bricks = stride(from:6,to:faces.count,by:36).map { base in
            let middle = (faces[base]+faces[base+2])*0.5
            return Brick(center:SIMD2(middle.x,middle.y))
        }
        radius = [(1.22/3)*scale*1.8,0.17*scale*2.6]
    }
    var count: Int { bricks.count }
    /// Preserve a visible response for taps released before the feedback timer.
    mutating func pulse(at point: SIMD2<Float>) {
        contact = nil; returning = false; isActive = true
        for i in bricks.indices {
            let weight = max(0, 1-simd_length_squared((bricks[i].center-point)/radius))
            bricks[i].velocity = min(12, bricks[i].velocity + 8*weight*weight)
        }
    }
    mutating func move(to point: SIMD2<Float>) {
        contact = point
        returning = false
        isActive = true
    }
    mutating func release() { contact = nil }
    mutating func settle() { contact = nil; returning = true }
    mutating func reset() {
        for i in bricks.indices { bricks[i].height = 0; bricks[i].velocity = 0 }
        isActive = false; returning = false; contact = nil
    }
    mutating func advance(_ seconds: Double) {
        guard isActive else { return }
        let dt = Float(min(0.1,max(0,seconds)))
        let frequency: Float = returning ? 12 : (contact == nil ? 4.2 : 16)
        let decay = exp(-frequency*dt)
        isActive = contact != nil
        for i in bricks.indices {
            let weight: Float = contact.map { point in
                max(0,1-simd_length_squared((bricks[i].center-point)/radius))
            } ?? 0
            let target: Float = 0.95*weight*weight
            let offset = bricks[i].height-target
            let impulse = bricks[i].velocity + frequency*offset
            bricks[i].height = max(0,target+(offset+impulse*dt)*decay)
            bricks[i].velocity = (bricks[i].velocity-frequency*impulse*dt)*decay
            if bricks[i].height < 0.00002 && abs(bricks[i].velocity) < 0.0002 {
                bricks[i].height = 0; bricks[i].velocity = 0
            } else { isActive = true }
        }
    }
    func presentation(at index: Int, reduced: Bool) -> SIMD4<Float> {
        let lift = Self.maximumLift*tanh(bricks[index].height/Self.maximumLift)
        return [reduced ? 0 : lift, reduced ? lift/Self.maximumLift : 0,0,0]
    }
    func write(to values: UnsafeMutablePointer<SIMD4<Float>>, reduced: Bool) {
        for i in bricks.indices { values[i] = presentation(at:i,reduced:reduced) }
    }

    /// Ray/solid-wall intersection includes the crest, rejects sky and floor.
    static func hit(ndc: SIMD2<Float>, aspect: Float, journey: Float) -> SIMD2<Float>? {
        let camera = HorizonGeometry.camera(journey:journey)
        let inverse = simd_inverse(HorizonGeometry.perspective(aspect:aspect)*HorizonGeometry.view(eye:camera.eye,target:camera.target))
        let far = inverse*SIMD4<Float>(ndc.x,ndc.y,1,1)
        let direction = simd_normalize(SIMD3(far.x,far.y,far.z)/far.w-camera.eye)
        let low = SIMD3<Float>(-11,0,-HorizonGeometry.wallHalfDepth)
        let high = SIMD3<Float>(11,3.06,HorizonGeometry.wallHalfDepth)
        var near: Float = 0, distant = Float.infinity
        for axis in 0..<3 {
            if abs(direction[axis]) < 0.000001 {
                guard camera.eye[axis] >= low[axis], camera.eye[axis] <= high[axis] else { return nil }
            } else {
                let a = (low[axis]-camera.eye[axis])/direction[axis]
                let b = (high[axis]-camera.eye[axis])/direction[axis]
                near = max(near,min(a,b)); distant = min(distant,max(a,b))
            }
        }
        guard near <= distant, distant >= 0 else { return nil }
        let point = camera.eye+direction*near
        return SIMD2(point.x,point.y)
    }
}
