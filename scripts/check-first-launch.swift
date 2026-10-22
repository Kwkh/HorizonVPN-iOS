import Foundation
import simd

@main struct FirstLaunchChecks {
    @MainActor static func main() {
        var count = 0
        func check(_ condition: Bool, _ label: String) {
            precondition(condition, label)
            count += 1
        }
        for phase: HorizonMotion.Phase in [.idle, .connected, .connecting, .recovering, .disconnecting] {
            var intro = HorizonIntroduction(destination: phase, reduced: false)
            check(intro.pose.wall == 0 && intro.pose.formation == 1, "full globe before wall")
            var previous = intro.pose
            for _ in 0..<330 {
                intro.advance(1/60, destination: phase, reduced: false, skip: false)
                let current = intro.pose
                check(abs(current.journey-previous.journey) < 0.03, "continuous camera")
                check(abs(current.globeBlend-previous.globeBlend) < 0.03, "continuous globe size")
                check(current.wall >= previous.wall, "wall never unbuilds")
                previous = current
            }
            check(intro.finished, "finishes within 5.5 seconds")
            check(intro.pose.wall == 1 && intro.pose.globeBlend == 1, "normal geometry at handoff")
            check(intro.pose.formation == (phase == .connected ? 1 : 0), "real state at handoff")
            check(intro.pose.journey == (phase == .idle || phase == .disconnecting ? 0 : 1), "real camera destination")
        }
        var bridged = HorizonIntroduction(destination:.idle,reduced:false,continuesGlobe:true)
        check(bridged.pose.particles == 1, "guide globe remains visible at handoff")
        check(bridged.pose.wall == 0, "initial matched frame remains wall-free")
        for fps in [30.0,60,120] {
            var continuation = HorizonIntroduction(destination:.idle,reduced:false,continuesGlobe:true)
            continuation.advance(1/fps,destination:.idle,reduced:false,skip:false)
            check(continuation.pose.wall > 0 && continuation.pose.wall <= 1/60,
                  "continued globe starts staggered wall on first animated frame")
            var standalone = HorizonIntroduction(destination:.idle,reduced:false)
            for _ in 0..<Int(fps*0.5) {
                standalone.advance(1/fps,destination:.idle,reduced:false,skip:false)
                check(standalone.pose.wall == 0,"standalone globe retains its fade-in time")
            }
            for _ in 1..<Int(fps*2)+1 {
                continuation.advance(1/fps,destination:.idle,reduced:false,skip:false)
            }
            check(continuation.pose.wall == 1,"staggered build still takes two seconds")
            for _ in 0..<Int(fps*2.5) {
                continuation.advance(1/fps,destination:.idle,reduced:false,skip:false)
            }
            check(continuation.finished,"continued sequence completes without the redundant delay")
        }
        for _ in 0..<35 {
            bridged.advance(1/60,destination:.idle,reduced:false,skip:false)
            check(bridged.pose.particles == 1, "no second globe fade-in")
        }
        var early = HorizonIntroduction(destination: .idle, reduced: false)
        for _ in 0..<31 { early.advance(1/60, destination: .idle, reduced: false, skip: true) }
        check(early.finished && early.pose.journey == 0, "early skip")
        var reduced = HorizonIntroduction(destination: .connected, reduced: true)
        for _ in 0..<30 {
            reduced.advance(1/60, destination: .connected, reduced: true, skip: false)
            check(reduced.pose.journey == 1 && reduced.pose.globeBlend == 1 && reduced.pose.wall == 1, "reduced motion has no spatial transition")
        }
        check(reduced.finished, "reduced duration")
        var changed = HorizonIntroduction(destination: .connected, reduced: false)
        for _ in 0..<200 { changed.advance(1/60, destination: .connected, reduced: false, skip: false) }
        let before = changed.pose
        changed.advance(1/60, destination: .idle, reduced: false, skip: false)
        check(abs(changed.pose.journey-before.journey) < 0.001, "state change rebases continuously")
        for _ in 0..<65 { changed.advance(1/60, destination: .idle, reduced: false, skip: false) }
        check(changed.finished && changed.pose.journey == 0, "disconnect during intro")
        var motion = HorizonMotion()
        motion.finishIntroduction(phase: .connected, rotation: -0.12, elapsed: 5)
        check(motion.rotation == -0.12 && motion.time == 5 && motion.formation == 1, "preserve renderer clocks at handoff")
        motion.finishIntroduction(phase: .connected, rotation: 0.2, elapsed: 5, startingTime: 13)
        check(motion.time == 18, "continue guide atmosphere clock through both handoffs")
        for aspect: Float in [0.35, 0.46, 0.58, 0.75, 1, 1.8] {
            let globe = HorizonGeometry.introductionGlobe(aspect: aspect)
            let camera = HorizonGeometry.camera(journey: 1)
            let center = SIMD3(globe.x, globe.y, globe.z)
            let depth = simd_length(center-camera.eye)
            let projection = HorizonGeometry.perspective(aspect: aspect)
            let edge = globe.w / sqrt(depth*depth-globe.w*globe.w)
            check(edge * projection.columns.0.x <= 0.961, "horizontal globe fit")
            check(edge * projection.columns.1.y <= 0.881, "vertical globe fit")
        }
        check(abs(HorizonGeometry.introductionGlobe(aspect: 0.58).w - 2.32 * 1.3) < 0.0001, "intro uses 1.3 scale on portrait viewport")
        let name = "Clash.FirstLaunchChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        func clear() { defaults.removePersistentDomain(forName: name) }
        let first = FirstLaunchExperience(defaults: defaults)
        check(first.suppressesTabBar, "unresolved launch cannot flash tab bar")
        check(!first.allowsNetworkMonitoring, "unresolved launch defers network monitoring")
        first.resolve(hasExistingConfiguration: false, horizon: true)
        check(first.suppressesTabBar, "guide hides tab bar")
        check(!first.allowsNetworkMonitoring, "guide defers network monitoring")
        check(first.resolved && first.requestID != nil && first.isShowingGuide, "fresh install starts with guide")
        check(!first.needsVPNSetupOffer, "VPN offer cannot interrupt the guide")
        let firstID = first.requestID!
        first.beginScene(UUID())
        check(first.isShowingGuide, "stale guide callback ignored")
        first.prepareScene(UUID(),rotation:0.8)
        check(!first.isPreparingScene, "stale preparation ignored")
        let clock = HorizonSceneClock()
        first.prepareScene(firstID,rotation:0.8,time:13,clock:clock)
        check(first.guideClock === clock, "both scenes own the same continuous clock")
        check(first.suppressesTabBar, "preparing destination keeps tab bar hidden")
        check(first.isPreparingScene && first.isShowingGuide && first.guideRotation == 0.8 && first.guideTime == 13, "prepare under opaque guide")
        first.beginScene(firstID)
        check(first.isShowingGuide, "cannot release until the real Metal destination has presented")
        first.scenePresented(UUID())
        check(first.preparedSceneID == nil, "stale presented callback ignored")
        first.scenePresented(firstID)
        first.beginScene(firstID)
        check(!first.isPreparingScene && first.guideRotation == 0.8 && first.guideTime == 13, "release renderer with same globe orientation")
        check(first.suppressesTabBar, "cinematic remains fullscreen after guide finishes")
        check(!first.allowsNetworkMonitoring, "cinematic defers network monitoring")
        check(!first.isShowingGuide && first.requestID == firstID, "guide hands off to same intro session")
        let interrupted = FirstLaunchExperience(defaults: defaults)
        interrupted.resolve(hasExistingConfiguration: false, horizon: true)
        check(interrupted.requestID != nil, "unfinished intro can resume next launch")
        first.complete(UUID())
        check(first.suppressesTabBar, "stale completion cannot expose tab bar")
        check(first.requestID != nil, "stale completion ignored")
        check(!first.needsVPNSetupOffer, "stale completion cannot request VPN setup")
        first.complete(first.requestID!)
        check(first.guideClock == nil, "completed session releases shared clock")
        check(!first.suppressesTabBar, "final presented frame releases tab bar")
        check(first.needsVPNSetupOffer, "completed first introduction offers VPN setup")
        check(!first.allowsNetworkMonitoring, "setup offer precedes network monitoring")
        let cold = FirstLaunchExperience(defaults: defaults)
        cold.resolve(hasExistingConfiguration: false, horizon: true)
        check(!cold.suppressesTabBar, "ordinary launch exposes normal tabs")
        check(cold.requestID == nil && !cold.isShowingGuide, "cold launch does not replay either stage")
        check(cold.needsVPNSetupOffer, "unanswered offer survives process termination")
        check(!cold.allowsNetworkMonitoring, "pending setup defers monitoring on next launch")
        cold.dismissVPNSetupOffer()
        check(!cold.needsVPNSetupOffer, "not now or successful setup consumes the offer")
        check(cold.allowsNetworkMonitoring, "answered setup allows ordinary monitoring")
        let afterAnswer = FirstLaunchExperience(defaults: defaults)
        afterAnswer.resolve(hasExistingConfiguration: false, horizon: true)
        check(!afterAnswer.needsVPNSetupOffer, "answered offer is not repeated on cold launch")
        check(afterAnswer.allowsNetworkMonitoring, "ordinary cold launch enables monitoring")
        clear()
        defaults.set(2.0, forKey: "ui.globeScale")
        let migrated = FirstLaunchExperience(defaults: defaults)
        migrated.resolve(hasExistingConfiguration: false, horizon: true)
        check(migrated.requestID == nil, "existing preferences migrate")
        check(!migrated.needsVPNSetupOffer, "upgrading an existing install does not request setup")
        clear()
        let configured = FirstLaunchExperience(defaults: defaults)
        configured.resolve(hasExistingConfiguration: true, horizon: true)
        check(configured.requestID == nil, "existing library migrates")
        check(!configured.needsVPNSetupOffer, "existing configuration does not request setup")
        let preview = FirstLaunchExperience(defaults: defaults, preview: true)
        preview.resolve(hasExistingConfiguration: true, horizon: true)
        check(preview.requestID != nil && preview.isShowingGuide, "explicit debug preview includes guide")
        let previewID = preview.requestID!
        preview.prepareScene(previewID,rotation:nil)
        preview.scenePresented(previewID)
        preview.beginScene(previewID)
        preview.skip()
        check(preview.suppressesTabBar, "skip request still waits for final frame")
        check(preview.skipRequested && !preview.isShowingGuide, "cinematic skip does not restart guide")
        preview.complete(previewID)
        check(!preview.needsVPNSetupOffer, "preview completion never requests system setup")
        check(!preview.suppressesTabBar, "completed skip exposes normal tabs")
        check(preview.requestID == nil && !preview.isShowingGuide && !preview.skipRequested, "completion clears both stages")
        clear()
        let skipped = FirstLaunchExperience(defaults: defaults)
        skipped.resolve(hasExistingConfiguration: false, horizon: true)
        skipped.skip()
        check(!skipped.needsVPNSetupOffer, "skip still waits for the cinematic completion")
        skipped.complete(skipped.requestID!)
        check(skipped.needsVPNSetupOffer, "skipped first introduction also offers setup")
        print("First launch: \(count) checks passed")
    }
}
