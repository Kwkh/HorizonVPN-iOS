import Foundation

/// Presentation only. Crossing the threshold arms completion; releasing commits.
/// A reversed, cancelled or interrupted drag never starts the next introduction.
struct HorizonGuidePullState {
    enum Phase { case idle, dragging, returning, committed }
    private(set) var phase = Phase.idle
    private(set) var generation = 0
    private var anchor = 0.0
    var progress = 0.0
    // Keep chrome hidden during a reversal/re-grab until the rendered camera
    // has actually settled. Finger distance alone is not camera position.
    private(set) var textFadeProgress = 0.0
    // Twice the original pull distance, while still disappearing before commit.
    static let textFadeExtent = 0.24
    var textVisibility: Double { 1-Self.spatialProgress(textFadeProgress/Self.textFadeExtent) }
    static let threshold = 0.64

    /// Gentle start/finish in space, in addition to the camera's temporal follow.
    static func spatialProgress(_ raw: Double) -> Double {
        let t = min(1,max(0,raw))
        return t*t*t*(t*(t*6-15)+10)
    }
    static func gestureProgress(forSpatial value: Double) -> Double {
        let target = min(1,max(0,value))
        var low = 0.0, high = 1.0
        for _ in 0..<40 {
            let middle = (low+high)/2
            if spatialProgress(middle) < target { low = middle } else { high = middle }
        }
        return (low+high)/2
    }

    mutating func begin(presentedProgress: Double) {
        guard phase != .committed else { return }
        generation += 1
        anchor = min(0.94,max(0,presentedProgress))
        progress = anchor
        textFadeProgress = max(textFadeProgress,anchor)
        phase = .dragging
    }
    mutating func update(distance: Double, height: Double) {
        guard phase == .dragging, distance.isFinite else { return }
        progress = min(0.94,max(0,anchor+distance/max(150,height*0.60)))
        textFadeProgress = max(textFadeProgress,progress)
    }
    mutating func end(cancelled: Bool) -> Bool {
        guard phase == .dragging else { return false }
        let commit = !cancelled && progress >= Self.threshold
        phase = commit ? .committed : .returning
        textFadeProgress = max(textFadeProgress,Self.textFadeExtent)
        return commit
    }
    mutating func reset() {
        generation += 1
        phase = .idle
        progress = 0
        textFadeProgress = 0
        anchor = 0
    }
}
