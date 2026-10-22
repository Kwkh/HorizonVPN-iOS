import Foundation

/// Integrates angular velocity through connection transitions. Changing the target
/// never re-multiplies an absolute timestamp, so particle positions remain continuous.
struct ParticleMotion {
    struct Frame {
        let time: Double
        let phase: Double
        let connection: Double
    }
    private var anchor: Double = 0
    private var base = Frame(time: 0, phase: 0, connection: 0)
    private var target: Double = 0
    private var running = false
    private let duration = 0.7

    init(connected: Bool = false) {
        target = connected ? 1 : 0
        base = Frame(time: 0, phase: 0, connection: target)
    }

    func frame(at now: Double) -> Frame {
        let dt = running ? max(0, now - anchor) : 0
        let decay = exp(-dt / duration)
        let connection = target + (base.connection - target) * decay
        let integral = target * dt + (base.connection - target) * duration * (1 - decay)
        return Frame(time: base.time + dt,
                     phase: base.phase + 0.045 * dt + 0.075 * integral,
                     connection: connection)
    }

    mutating func update(connected: Bool, running: Bool, at now: Double, settle: Bool = false) {
        let current = frame(at: now)
        target = connected ? 1 : 0
        base = Frame(time: current.time, phase: current.phase,
                     connection: settle ? target : current.connection)
        anchor = now
        self.running = running
    }
}
