import Foundation

/// A single top-edge pull can commit only once. No VPN calls or fake connection status.
struct HorizonPullState {
    // The camera eye clears the 3.06-unit wall at journey ~= 0.504.
    static let crossing = 0.54
    private(set) var journey: Double?
    private(set) var tracking = false
    private(set) var committed = false
    private var origin = 0.0

    mutating func begin(eligible: Bool, currentJourney: Double) {
        guard eligible, !committed else { return }
        tracking = true
        origin = min(Self.crossing, max(0, currentJourney))
        journey = origin
    }
    /// Returns true only on the first threshold crossing, while the finger is still down.
    mutating func update(distance: Double, threshold: Double) -> Bool {
        guard tracking, !committed, threshold > 0 else { return false }
        let fraction = min(1, max(0, distance / threshold))
        journey = origin + (Self.crossing - origin) * fraction
        if fraction >= 1 { committed = true; return true }
        return false
    }
    mutating func end() {
        tracking = false
        if !committed { journey = nil }
    }
    mutating func reset() { self = HorizonPullState() }
}
