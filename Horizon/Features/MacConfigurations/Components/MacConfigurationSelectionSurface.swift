#if os(macOS)
import SwiftUI
import AppKit

struct MacConfigurationFrames: PreferenceKey {
    static var defaultValue: [UUID: CGRect] { [:] }
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

/// AppKit routes a selection gesture to this content view, never through an
/// application-wide event monitor. Sibling sidebar and toolbar events stay native.
struct MacConfigurationSelectionSurface: NSViewRepresentable {
    enum Drag { case began(extending: Bool), changed(CGRect), ended, cancelled }
    var frames: [UUID: CGRect]
    var enabled: Bool
    var isCurrentPage: () -> Bool = { true }
    var click: (UUID?, NSEvent.ModifierFlags) -> Void
    var drag: (Drag) -> Void
    var selectAll: () -> Void
    var clear: () -> Void
    var delete: () -> Void

    func makeNSView(context: Context) -> Surface { Surface() }
    func updateNSView(_ view: Surface, context: Context) {
        view.configuration = self
        view.synchronizeLifecycle()
    }
    static func dismantleNSView(_ view: Surface, coordinator: ()) { view.stop() }

    final class Surface: NSView {
        var configuration: MacConfigurationSelectionSurface?
        private var focusObserver: NSObjectProtocol?
        private var origin: CGPoint?
        private var flags: NSEvent.ModifierFlags = []
        private var dragging = false
        private var lastDrag: NSEvent?
        private var scrollTimer: Timer?
        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? {
            selectionHitTest(point, event: NSApp.currentEvent)
        }
        // NSView.hitTest receives coordinates in the superview, not this view.
        func selectionHitTest(_ point: NSPoint, event: NSEvent?) -> NSView? {
            guard acceptsSelection, let event, event.window === window,
                  [.leftMouseDown, .leftMouseDragged, .leftMouseUp].contains(event.type),
                  !event.modifierFlags.contains(.control) else { return nil }
            let local = convert(point, from: superview)
            guard containsContent(local) else { return nil }
            // Leave the actual SwiftUI refresh button in the responder chain.
            if configuration?.frames.values.contains(where: {
                CGRect(x: $0.maxX - 44, y: $0.minY + 12, width: 32, height: 32).contains(local)
            }) == true { return nil }
            return self
        }
        private var acceptsSelection: Bool {
            configuration?.enabled == true && configuration?.isCurrentPage() == true &&
                window != nil && window?.attachedSheet == nil && !isHiddenOrHasHiddenAncestor
        }
        private func containsContent(_ point: CGPoint) -> Bool {
            guard bounds.contains(point), visibleRect.contains(point),
                  let viewport = enclosingScrollView?.contentView else { return false }
            return viewport.bounds.contains(viewport.convert(point, from: self))
        }
        override func mouseDown(with event: NSEvent) { _ = handleSelectionEvent(event) }
        override func mouseDragged(with event: NSEvent) { _ = handleSelectionEvent(event) }
        override func mouseUp(with event: NSEvent) { _ = handleSelectionEvent(event) }
        override func keyDown(with event: NSEvent) {
            if handleSelectionEvent(event) != nil { super.keyDown(with: event) }
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            handleSelectionEvent(event) == nil || super.performKeyEquivalent(with: event)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            synchronizeLifecycle()
        }
        func synchronizeLifecycle() {
            guard let window, let configuration, configuration.enabled,
                  configuration.isCurrentPage(), !isHiddenOrHasHiddenAncestor else {
                stop(); return
            }
            guard focusObserver == nil else { return }
            focusObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel() }
            }
        }
        func stop() {
            cancel()
            if window?.firstResponder === self { window?.makeFirstResponder(nil) }
            if let focusObserver { NotificationCenter.default.removeObserver(focusObserver); self.focusObserver = nil }
        }
        override func viewDidHide() { super.viewDidHide(); stop() }
        override func viewDidUnhide() { super.viewDidUnhide(); synchronizeLifecycle() }
        deinit {
            if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
            scrollTimer?.invalidate()
        }
        func cancel() {
            if dragging { configuration?.drag(.cancelled) }
            finish()
        }
        private func finish() {
            origin = nil; dragging = false; lastDrag = nil
            scrollTimer?.invalidate(); scrollTimer = nil
        }
        // Internal so the event-routing regression can exercise the production
        // handler without posting input to the user's desktop.
        func handleSelectionEvent(_ event: NSEvent) -> NSEvent? {
            guard let configuration, event.window === window else { return event }
            guard configuration.enabled, configuration.isCurrentPage(),
                  !isHiddenOrHasHiddenAncestor else { stop(); return event }
            guard window?.attachedSheet == nil else { cancel(); return event }
            if event.type == .keyDown {
                guard window?.firstResponder === self, configuration.enabled else { return event }
                if event.keyCode == 53 { cancel(); configuration.clear(); return nil }
                if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                   event.charactersIgnoringModifiers?.lowercased() == "a" { configuration.selectAll(); return nil }
                if event.keyCode == 51 || event.keyCode == 117 { configuration.delete(); return nil }
                return event
            }
            let point = convert(event.locationInWindow, from: nil)
            let card = configuration.frames.first { $0.value.contains(point) }
            if event.type == .leftMouseDown {
                // A missing mouse-up must not leave the next click captured.
                cancel()
                guard containsContent(point), !event.modifierFlags.contains(.control) else { return event }
                // Same 24pt refresh target + padding as MacConfigurationCard.
                if let frame = card?.value, CGRect(x: frame.maxX - 44, y: frame.minY + 12, width: 32, height: 32).contains(point) { return event }
                window?.makeFirstResponder(self)
                origin = point; flags = event.modifierFlags
                return nil
            }
            guard let origin else { return event }
            if event.type == .leftMouseDragged {
                if !dragging, hypot(point.x - origin.x, point.y - origin.y) >= 5 {
                    dragging = true
                    configuration.drag(.began(extending: !flags.intersection([.command, .shift]).isEmpty))
                    scrollTimer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                        MainActor.assumeIsolated { self?.scrollSelection() }
                    }
                    RunLoop.main.add(scrollTimer!, forMode: .common)
                }
                if dragging { lastDrag = event; updateRectangle(point) }
                return nil
            }
            if event.type == .leftMouseUp {
                if dragging { updateRectangle(point); configuration.drag(.ended) }
                else { configuration.click(card?.key, flags) }
                finish()
                return nil
            }
            return event
        }
        private func updateRectangle(_ point: CGPoint) {
            guard let origin else { return }
            configuration?.drag(.changed(CGRect(x: min(origin.x, point.x), y: min(origin.y, point.y),
                width: abs(origin.x - point.x), height: abs(origin.y - point.y))))
        }
        private func scrollSelection() {
            guard configuration?.isCurrentPage() == true, configuration?.enabled == true,
                  window?.attachedSheet == nil, !isHiddenOrHasHiddenAncestor else { stop(); return }
            guard dragging, let event = lastDrag else { return }
            if autoscroll(with: event) { updateRectangle(convert(event.locationInWindow, from: nil)) }
        }
    }
}
#endif
