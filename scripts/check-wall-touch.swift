import Foundation
import simd

@main struct CheckWallTouch {
    static func main() {
        for scale: Float in [1,1.5,3] {
            let wall = HorizonGeometry.wall(scale:scale)
            var motion = HorizonWallTouch(faces:wall.faces,scale:scale)
            motion.move(to:[0,1.65])
            precondition(motion.isActive)
            for i in 0..<motion.count { precondition(motion.presentation(at:i,reduced:false).x == 0) }
            for _ in 0..<12 { motion.advance(1.0/60) }
            let before = (0..<motion.count).map { motion.presentation(at:$0,reduced:false).x }
            precondition(before.max()! > 0.3, "touch-down must produce a clearly raised surface")
            precondition(before.filter { $0 > 0 }.count < 32, "effect must remain local")
            motion.move(to:[0.1,1.6])
            precondition(before == (0..<motion.count).map { motion.presentation(at:$0,reduced:false).x }, "retargeting must not teleport bricks")
            for frame in 0..<120 {
                if frame < 50 { motion.move(to:[0,1.65]) }
                motion.advance(1.0/60)
                for i in 0..<motion.count {
                    let normal = motion.presentation(at:i,reduced:false)
                    let reduced = motion.presentation(at:i,reduced:true)
                    precondition(normal.x >= 0 && normal.x <= HorizonWallTouch.maximumLift)
                    precondition(reduced.x == 0 && reduced.y >= 0 && reduced.y <= 1)
                }
            }
            motion.settle()
            for _ in 0..<180 { motion.advance(1.0/60) }
            precondition(!motion.isActive)
            for i in 0..<motion.count { precondition(motion.presentation(at:i,reduced:false) == .zero) }
        }
        let wall = HorizonGeometry.wall(scale:1.5)
        var held = HorizonWallTouch(faces:wall.faces,scale:1.5)
        var frequent = held
        held.move(to:[0,1.65])
        for _ in 0..<240 {
            // Event frequency cannot pump up the effect.
            for _ in 0..<20 { frequent.move(to:[0,1.65]) }
            held.advance(1.0/60); frequent.advance(1.0/60)
        }
        let stable = (0..<held.count).map { held.presentation(at:$0,reduced:false) }
        precondition(stable == (0..<frequent.count).map { frequent.presentation(at:$0,reduced:false) })
        precondition(stable.map(\.x).max()! > 0.4 && held.isActive, "hold must retain elevation")
        held.release()
        precondition(stable == (0..<held.count).map { held.presentation(at:$0,reduced:false) }, "release must preserve position")
        for _ in 0..<300 { held.advance(1.0/60) }
        precondition(!held.isActive)
        held.move(to:[0,1.65])
        for _ in 0..<30 { held.advance(1.0/60) }
        let origin = (0..<held.count).map { held.presentation(at:$0,reduced:false).x }
        held.move(to:[2,1.65])
        precondition(origin == (0..<held.count).map { held.presentation(at:$0,reduced:false).x })
        for _ in 0..<120 { held.advance(1.0/60) }
        for i in 0..<held.count where origin[i] > 0.05 {
            precondition(held.presentation(at:i,reduced:false).x < 0.001, "old contact must settle as new region rises")
        }
        // Project actual world positions and raycast back to the wall.
        for journey: Float in [0,1] {
            let aspect: Float = 0.58
            let camera = HorizonGeometry.camera(journey:journey)
            let vp = HorizonGeometry.perspective(aspect:aspect)*HorizonGeometry.view(eye:camera.eye,target:camera.target)
            let world = SIMD4<Float>(0.3,2.4,HorizonGeometry.wallHalfDepth,1)
            let clip = vp*world
            let hit = HorizonWallTouch.hit(ndc:[clip.x/clip.w,clip.y/clip.w],aspect:aspect,journey:journey)!
            precondition(simd_distance(hit,[world.x,world.y])<0.0001)
            precondition(HorizonWallTouch.hit(ndc:[0,0.95],aspect:aspect,journey:journey)==nil, "sky must not be tappable")
        }
        print("PASS: touch-down, sustained hold, drag retargeting, event-rate independence, release/cancel continuity, bounded elevation, reduced motion and ray hits.")
    }
}
