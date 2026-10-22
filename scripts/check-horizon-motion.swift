import Foundation
import simd

@main struct CheckHorizonMotion {
    static func main() {
        var pull = HorizonPullState()
        pull.begin(eligible: false, currentJourney: 0)
        precondition(!pull.update(distance: 200, threshold: 100), "ineligible or inertial scroll must not connect")
        pull.begin(eligible: true, currentJourney: 0)
        precondition(!pull.update(distance: 50, threshold: 100))
        precondition(pull.journey == HorizonPullState.crossing / 2)
        var interactive = HorizonMotion()
        interactive.select(.idle, immediate: false)
        interactive.scrub(to: pull.journey)
        interactive.advance(0.1)
        precondition(interactive.journey == pull.journey && interactive.formation == 0)
        pull.end()
        let released = interactive.journey
        interactive.scrub(to: pull.journey)
        precondition(interactive.journey == released, "early release must begin rollback without a jump")
        for _ in 0..<120 { interactive.advance(1.0/60) }
        precondition(interactive.journey == 0)
        pull.begin(eligible: true, currentJourney: 0)
        precondition(pull.update(distance: 100, threshold: 100), "crossing commits before release")
        precondition(!pull.update(distance: 120, threshold: 100), "a pull connects at most once")
        pull.end()
        interactive.scrub(to: pull.journey)
        for _ in 0..<300 { interactive.advance(1.0/60) }
        precondition(interactive.journey == HorizonPullState.crossing && interactive.formation == 0,
                     "confirmation holds the camera without falsely assembling the globe")
        let crestEye = HorizonGeometry.camera(journey: Float(HorizonPullState.crossing)).eye
        precondition(crestEye.y > 3.06, "commit threshold must clear the wall")
        interactive.select(.connecting, immediate: false)
        pull.reset()
        interactive.scrub(to: pull.journey)
        precondition(interactive.journey == HorizonPullState.crossing, "confirmed connection continues from the held pose")
        for _ in 0..<240 { interactive.advance(1.0/60) }
        precondition(interactive.journey == 1 && interactive.formation == 0)
        interactive.select(.connected, immediate: false)
        interactive.advance(0.1)
        precondition(interactive.formation > 0)
        pull.begin(eligible: true, currentJourney: 0.2)
        _ = pull.update(distance: 0, threshold: 100)
        precondition(pull.journey == 0.2, "regrab preserves the current rollback pose")
        _ = pull.update(distance: 50, threshold: 100)
        _ = pull.update(distance: 10, threshold: 100)
        precondition(pull.journey! < 0.3, "the camera follows a reversing finger before commitment")
        pull.reset()
        interactive.select(.idle, immediate: true)
        interactive.scrub(to: HorizonPullState.crossing)
        interactive.scrub(to: nil)
        precondition(interactive.journey == HorizonPullState.crossing)
        for _ in 0..<240 { interactive.advance(1.0/60) }
        precondition(interactive.journey == 0, "cancelled confirmation returns to the wall")
        var waiting = HorizonMotion()
        waiting.select(.idle, immediate: false)
        waiting.select(.connecting, immediate: false)
        for _ in 0..<900 { waiting.advance(1.0/60) }
        precondition(waiting.journey == 1 && waiting.formation == 0, "slow connection cannot produce a connected globe")
        let previous = waiting.journey
        waiting.select(.idle, immediate: false)
        precondition(waiting.journey == previous, "failure reverses from current camera position")
        var m = HorizonMotion()
        m.select(.idle, immediate: false)
        m.select(.connecting, immediate: false)
        for _ in 0..<90 { m.advance(1.0/60) }
        precondition(m.journey > 0 && m.journey < 1 && m.formation == 0)
        let before = m.journey
        m.select(.connected, immediate: false)
        precondition(m.journey == before && m.formation == 0, "status must not teleport camera or particles")
        m.advance(0.1)
        precondition(m.formation > 0 && m.journey < 0.995, "connected particles must gather during the reveal")
        for _ in 0..<600 { m.advance(1.0/60) }
        precondition(m.journey == 1 && m.formation > 0.99)
        // Isolate recovery from the unchanged regular connection camera path.
        for fps in [30.0, 60.0, 120.0] {
            var recovery = HorizonMotion()
            recovery.select(.connected, immediate: true)
            let rotation = recovery.rotation
            recovery.select(.recovering, immediate: false, resuming: true)
            precondition(recovery.formation == 1 && recovery.journey == 1,
                         "foreground resume must preserve the last connected globe")
            recovery.advance(1/fps)
            precondition(1-recovery.formation < 0.005,
                         "recovery must ease into dispersion, not lose a large particle fraction on frame one")
            for _ in 0..<Int(fps/2) { recovery.advance(1/fps) }
            let interrupted = recovery.formation
            recovery.select(.connected, immediate: false, resuming: true)
            precondition(recovery.formation == interrupted, "quick recovery must not teleport to a complete globe")
            var previous = interrupted
            for frame in 0..<Int(fps*6) {
                if frame == Int(fps/4) { recovery.select(.recovering, immediate: false) }
                if frame == Int(fps/2) { recovery.select(.connected, immediate: false) }
                recovery.advance(1/fps)
                precondition(abs(recovery.formation-previous) < 0.04)
                precondition((0...1).contains(recovery.formation) && recovery.journey == 1)
                previous = recovery.formation
            }
            precondition(recovery.formation == 1 && recovery.rotation > rotation)
            recovery.select(.recovering, immediate: true)
            precondition(recovery.formation == 0 && recovery.journey == 1, "reduced motion still settles immediately")
        }
        var coldRecovery = HorizonMotion()
        coldRecovery.select(.recovering, immediate: false, resuming: true)
        precondition(coldRecovery.formation == 0, "cold start must never invent a previous connected globe")
        coldRecovery.select(.connected, immediate: false, resuming: true)
        precondition(coldRecovery.formation == 0, "resuming after a settled recovery must assemble from the last pose")
        for _ in 0..<360 { coldRecovery.advance(1.0/60) }
        precondition(coldRecovery.formation == 1)
        let p = m.formation
        m.select(.recovering, immediate: false)
        precondition(m.formation == p)
        for _ in 0..<180 { m.advance(1.0/60) }
        precondition(m.journey == 1 && m.formation < 0.01, "recovery must not imply connected globe")
        m.select(.idle, immediate: false)
        for _ in 0..<240 { m.advance(1.0/60) }
        precondition(m.journey == 0 && m.formation < 0.01)
        m.select(.connected, immediate: true)
        precondition(m.journey == 1 && m.formation == 1, "reentry/reduced motion must settle to actual state")
        var globe = HorizonGlobeInteraction()
        let identity = simd_quatf(angle: 0, axis: SIMD3<Float>(0,1,0))
        globe.begin()
        globe.drag(translation: [140,-95], diameter: 300)
        precondition(abs(simd_length(globe.orientation.vector)-1) < 0.0001)
        let dragged = globe.orientation.vector
        globe.end(animated: true)
        precondition(globe.orientation.vector == dragged, "release must not snap orientation")
        globe.advance(0.3)
        let returning = globe.orientation.vector
        globe.begin()
        precondition(globe.orientation.vector == returning, "regrabbing must preserve the current return position")
        globe.drag(translation: .zero, diameter: 300)
        precondition(simd_length(globe.orientation.vector-returning) < 0.0001)
        globe.end(animated: true)
        for _ in 0..<60 { globe.advance(1.0/60) }
        precondition(!globe.isReturning && abs(simd_dot(globe.orientation.vector, identity.vector)) > 0.9999)
        globe.begin(); globe.drag(translation: [100,100], diameter: 300); globe.end(animated: false)
        precondition(abs(simd_dot(globe.orientation.vector, identity.vector)) > 0.9999, "reduced motion returns without animation")
        let wall = HorizonGeometry.wall()
        precondition(wall.faces.count == 18*57*36+6 && wall.edges.count == 18*57*24)
        precondition(wall.faces.allSatisfy { $0.x.isFinite && $0.y >= 0 && abs($0.z) <= HorizonGeometry.wallHalfDepth })
        for scale: Float in [1, 1.1, 1.7, 2.4, 3] {
            let scaled = HorizonGeometry.wall(scale: scale)
            precondition(scaled.faces.allSatisfy { $0.y >= 0 && $0.y <= 3.06 && (abs($0.z) == HorizonGeometry.wallHalfDepth || $0.z == 0) },
                         "brick size must preserve wall height and thickness")
            precondition(scaled.faces.allSatisfy { $0.w == 0.008 }, "keep every brick face black")
        }
        let camera = HorizonGeometry.camera(journey: 1)
        let vp = HorizonGeometry.perspective(aspect: 0.58) * HorizonGeometry.view(eye: camera.eye, target: camera.target)
        func screen(_ point: SIMD3<Float>) -> SIMD2<Float> {
            let p = vp * SIMD4(point,1)
            return [p.x/p.w,p.y/p.w]
        }
        let original = HorizonGeometry.globe(scale: 1)
        let enlarged = HorizonGeometry.globe(scale: 1.5)
        precondition(original == SIMD4<Float>(0,5.15,-7.1,2.32))
        precondition(enlarged.y < original.y && enlarged.w > original.w)
        let expandedEdge = screen([enlarged.w*0.85,enlarged.y,enlarged.z])
        precondition(HorizonGeometry.hitsGlobe(ndc: expandedEdge, aspect: 0.58, journey: 1, scale: 1.5),
                     "enlarged visible globe must accept touches outside the old radius")
        precondition(!HorizonGeometry.hitsGlobe(ndc: expandedEdge, aspect: 0.58, journey: 1, scale: 1))
        precondition(!HorizonGeometry.hitsGlobe(ndc: screen([0,1.5,0.25]), aspect: 0.58, journey: 1, scale: 1.5),
                     "wall remains a scroll surface even below an enlarged globe")
        let maximum = HorizonGeometry.globe(scale: 2)
        precondition(abs(maximum.w-4.64) < 0.0001 && maximum.y < enlarged.y)
        precondition(screen([maximum.w,maximum.y,maximum.z]).x > 1, "large globe stays cropped, camera does not fit it")
        precondition(!HorizonGeometry.hitsGlobe(ndc: screen([0,2.8,0.25]), aspect: 0.58, journey: 1, scale: 2),
                     "submerged globe must not intercept touches on the wall")
        precondition(HorizonGeometry.globe(scale: 1.6, aspect: 0.5).y < HorizonGeometry.globe(scale: 1.6, aspect: 0.75).y,
                     "submergence follows actual viewport overflow")
        let crest = vp * SIMD4<Float>(0,3.06,HorizonGeometry.wallHalfDepth,1)
        let view = HorizonGeometry.view(eye: camera.eye, target: camera.target)
        let sphereInView = view * SIMD4<Float>(maximum.x,maximum.y,maximum.z,1)
        let depth = -sphereInView.z
        let silhouetteMidY = HorizonGeometry.perspective(aspect: 0.58).columns.1.y *
            sphereInView.y*depth/(depth*depth-maximum.w*maximum.w)
        precondition(abs(silhouetteMidY-crest.y/crest.w) < 0.01,
                     "maximum globe must expose roughly its upper half above the wall")
        precondition(crest.y/crest.w > -0.9 && crest.y/crest.w < -0.4, "wall crest must remain in lower foreground")
        print("PASS: interactive pull/hold/cancel/continuation, early connected assembly, interruption/recovery, globe drag/return/regrab, reduced motion and wall geometry")
    }
}
