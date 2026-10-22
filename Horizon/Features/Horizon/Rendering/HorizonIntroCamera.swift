import Foundation
import Observation
import simd

/// Bounded presentation-only drag. Rendering samples the return curve directly,
/// without publishing per-frame changes to the entire home page.
@Observable final class HorizonIntroCamera {
    private var drag = SIMD2<Float>.zero
    private var start = SIMD2<Float>.zero
    private var dragging = false
    private var released: Date?
    static let returnDuration = 0.75

    func offset(at date: Date = Date()) -> SIMD2<Float> {
        guard let released else { return drag }
        let t = min(1,max(0,date.timeIntervalSince(released)/Self.returnDuration))
        let eased = t*t*t*(t*(t*6-15)+10)
        return drag * Float(1-eased)
    }
    func update(translation: SIMD2<Float>, viewport: SIMD2<Float>, now: Date = Date()) {
        guard translation.x.isFinite, translation.y.isFinite else { return }
        if !dragging { start = offset(at:now); dragging = true; released = nil }
        var next = start + SIMD2(translation.x/max(120,viewport.x*0.42),
                                 -translation.y/max(120,viewport.y*0.42))
        let length = simd_length(next)
        if length > 1 { next /= length }
        drag = next
    }
    func end(animated: Bool, now: Date = Date()) {
        guard dragging else { return }
        dragging = false
        if animated { released = now } else { reset() }
    }
    func reset() { drag = .zero; start = .zero; dragging = false; released = nil }
}
