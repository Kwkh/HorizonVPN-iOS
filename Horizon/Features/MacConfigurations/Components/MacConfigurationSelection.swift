#if os(macOS)
import Foundation

/// Selection is independent of the active VPN configuration and survives card refreshes.
struct MacConfigurationSelection {
    private(set) var ids: Set<UUID> = []
    private(set) var rectangle: CGRect?
    private var anchor: UUID?
    private var dragBase: Set<UUID> = []
    private var dragFrames: [UUID: CGRect] = [:]
    private var extendsDrag = false

    /// Only an unmodified click activates a configuration.
    mutating func click(_ id: UUID, order: [UUID], toggle: Bool, range: Bool) -> Bool {
        if range, let anchor, let first = order.firstIndex(of: anchor), let last = order.firstIndex(of: id) {
            let interval = Set(order[min(first, last)...max(first, last)])
            ids = toggle ? ids.union(interval) : interval
        } else if toggle {
            if !ids.insert(id).inserted { ids.remove(id) }
            anchor = id
        } else { ids = [id]; anchor = id }
        return !toggle && !range
    }
    mutating func context(_ id: UUID) {
        if !ids.contains(id) { ids = [id]; anchor = id }
    }
    mutating func clear() { ids = []; anchor = nil; rectangle = nil }
    mutating func selectAll(_ order: [UUID]) { ids = Set(order); anchor = order.first }
    mutating func retain(_ visible: Set<UUID>) {
        ids.formIntersection(visible)
        dragBase.formIntersection(visible)
        dragFrames = dragFrames.filter { visible.contains($0.key) }
        if let anchor, !visible.contains(anchor) { self.anchor = nil }
    }
    mutating func beginDrag(extending: Bool) { dragBase = ids; dragFrames = [:]; extendsDrag = extending }
    mutating func updateDrag(_ rectangle: CGRect, frames: [UUID: CGRect]) {
        self.rectangle = rectangle
        // Lazy grids retire offscreen cells during autoscroll. Keep their document
        // coordinates until this drag ends so earlier rows remain in the rectangle.
        dragFrames.merge(frames, uniquingKeysWith: { _, new in new })
        let hits = Set(dragFrames.compactMap { rectangle.intersects($0.value) ? $0.key : nil })
        ids = extendsDrag ? dragBase.union(hits) : hits
    }
    mutating func endDrag(cancelled: Bool = false) {
        if cancelled { ids = dragBase }
        rectangle = nil; dragBase = []; dragFrames = [:]
    }
}
#endif
