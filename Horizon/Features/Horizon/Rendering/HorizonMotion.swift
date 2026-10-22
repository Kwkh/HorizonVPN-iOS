import Foundation

/// Visual state only. VPN status remains owned by TunnelController.
struct HorizonMotion {
    enum Phase: Equatable { case idle, connecting, connected, recovering, disconnecting }
    private(set) var journey: Double = 0
    private(set) var formation: Double = 0
    private(set) var time: Double = 0
    private(set) var rotation: Double = -0.4
    private var phase: Phase = .idle
    private var initialized = false
    private var startJourney: Double = 0
    private var targetJourney: Double = 0
    private var elapsed: Double = 0
    private var duration: Double = 3.6
    private var scrubbing = false
    private var recoveryTransition = false
    private var formationVelocity: Double = 0

    mutating func finishIntroduction(phase: Phase, rotation: Double, elapsed: Double, startingTime: Double? = nil) {
        select(phase, immediate: true)
        self.rotation = rotation
        time = (startingTime ?? time) + elapsed
    }

    mutating func select(_ next: Phase, immediate: Bool, resuming: Bool = false) {
        // Resume an existing recovery from its last rendered pose. First display
        // and reduced motion still initialize directly to the real VPN state.
        let continuesRecovery = next == .recovering || (phase == .recovering && next == .connected) || recoveryTransition
        if !initialized || immediate || (resuming && !continuesRecovery) {
            journey = next == .idle || next == .disconnecting ? 0 : 1
            formation = next == .connected ? 1 : 0
            startJourney = journey; targetJourney = journey; elapsed = 4; duration = 3.6; scrubbing = false
            initialized = true; phase = next
            recoveryTransition = false; formationVelocity = 0
            return
        }
        guard phase != next else { return }
        if next == .recovering || (phase == .recovering && next == .connected) {
            recoveryTransition = true
        } else if next != .connected {
            recoveryTransition = false
        }
        phase = next
        let target: Double = next == .idle || next == .disconnecting ? 0 : 1
        if target != targetJourney {
            startJourney = journey; targetJourney = target; elapsed = 0; duration = 3.6
        }
    }
    mutating func scrub(to value: Double?, immediate: Bool = false) {
        if let value {
            scrubbing = true
            journey = min(1, max(0, value))
            startJourney = journey
            elapsed = 0
        } else if scrubbing {
            scrubbing = false
            let target: Double = phase == .idle || phase == .disconnecting ? 0 : 1
            startJourney = journey; targetJourney = target; elapsed = 0
            duration = max(0.3, 3.6 * abs(target - journey))
            if immediate { journey = target; startJourney = target; elapsed = duration }
        }
    }
    mutating func advance(_ seconds: Double) {
        let dt = min(0.1, max(0, seconds))
        time += dt; elapsed += dt
        if !scrubbing {
            let t = min(1, elapsed / duration)
            let easing = t*t*t*(t*(t*6-15)+10)
            journey = startJourney + (targetJourney-startJourney)*easing
        }
        // Begin assembling as the view reveals the space beyond the wall.
        let ready = phase == .connected && journey > 0.28
        let target: Double = ready ? 1 : 0
        if recoveryTransition {
            // Critically damped recovery: no initial burst, and a quick network
            // recovery retargets the same position/velocity without restarting.
            let frequency = 2.8
            let offset = formation - target
            let impulse = formationVelocity + frequency * offset
            let decay = exp(-frequency * dt)
            formation = target + (offset + impulse * dt) * decay
            formationVelocity = (formationVelocity - frequency * impulse * dt) * decay
            if formation < 0 || formation > 1 {
                formation = min(1, max(0, formation)); formationVelocity = 0
            }
        } else {
            // Preserve the original connect/disconnect assembly and camera timing.
            let rate = ready ? 1.65 : 2.5
            formation += (target-formation)*(1-exp(-dt*rate))
            formationVelocity = (target-formation)*rate
        }
        if abs(target-formation) < 0.0001 && abs(formationVelocity) < 0.001 {
            formation = target; formationVelocity = 0; recoveryTransition = false
        }
        rotation += dt * 0.055 * formation
    }
}
