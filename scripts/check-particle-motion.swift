import Foundation

@main struct CheckParticleMotion {
    static func main() {
        let connectedOnLaunch = ParticleMotion(connected: true)
        precondition(connectedOnLaunch.frame(at: 0).connection == 1,
                     "cold launch must render the connected tint on the first frame")
        var motion = ParticleMotion()
        motion.update(connected: false, running: true, at: 0)
        // Long uptimes exposed the former timestamp * changed-speed discontinuity.
        let transitionTime = 1_000_000.0
        let before = motion.frame(at: transitionTime)
        motion.update(connected: true, running: true, at: transitionTime)
        let after = motion.frame(at: transitionTime)
        precondition(before.phase == after.phase && before.time == after.time && before.connection == after.connection)
        let shortlyAfter = motion.frame(at: transitionTime + 0.001)
        precondition(shortlyAfter.phase > after.phase && shortlyAfter.phase - after.phase < 0.000121)
        precondition(shortlyAfter.connection > 0 && shortlyAfter.connection < 0.01)
        // Mid-transition reversals retain both position and current tint.
        let middle = motion.frame(at: transitionTime + 0.2)
        motion.update(connected: false, running: true, at: transitionTime + 0.2)
        precondition(motion.frame(at: transitionTime + 0.2).phase == middle.phase)
        precondition(motion.frame(at: transitionTime + 0.2).connection == middle.connection)
        // A hidden tab or background freezes phase, and resume doesn't reset it.
        motion.update(connected: false, running: false, at: transitionTime + 1)
        let frozen = motion.frame(at: transitionTime + 1)
        precondition(motion.frame(at: transitionTime + 100).phase == frozen.phase)
        motion.update(connected: true, running: true, at: transitionTime + 100)
        precondition(motion.frame(at: transitionTime + 100).phase == frozen.phase)
        // Reduced motion settles tint immediately without moving any particles.
        motion.update(connected: true, running: false, at: transitionTime + 100, settle: true)
        precondition(motion.frame(at: transitionTime + 101).connection == 1)
        precondition(motion.frame(at: transitionTime + 101).phase == frozen.phase)
        print("PASS: long-uptime connection continuity, smooth reversal, pause/resume and reduced motion")
    }
}
