import AppKit
import SwiftUI

@MainActor private final class Fixture {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                          styleMask: [.titled], backing: .buffered, defer: false)
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 640))
    let scroll = NSScrollView(frame: NSRect(x: 220, y: 0, width: 680, height: 580))
    let document = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 580))
    let surface = MacConfigurationSelectionSurface.Surface(frame: NSRect(x: 0, y: 0, width: 680, height: 580))
    let card = UUID()
    var active = true
    var clicks = 0
    var drags = 0
    var cancellations = 0
    var selections = 0
    init() {
        window.isReleasedWhenClosed = false
        window.contentView = root; root.addSubview(scroll); scroll.documentView = document
        document.addSubview(surface)
        surface.configuration = MacConfigurationSelectionSurface(
            frames: [card: CGRect(x: 20, y: 20, width: 280, height: 120)], enabled: true,
            isCurrentPage: { [weak self] in self?.active == true },
            click: { [weak self] _, _ in self?.clicks += 1 },
            drag: { [weak self] event in
                switch event { case .began: self?.drags += 1; case .cancelled: self?.cancellations += 1; default: break }
            }, selectAll: { [weak self] in self?.selections += 1 }, clear: {}, delete: {})
        surface.synchronizeLifecycle()
        root.layoutSubtreeIfNeeded()
    }
    func event(_ type: NSEvent.EventType, _ point: CGPoint, flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: surface.convert(point, to: nil), modifierFlags: flags, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    }
    func hit(_ point: CGPoint, type: NSEvent.EventType = .leftMouseDown, flags: NSEvent.ModifierFlags = []) -> NSView? {
        surface.selectionHitTest(surface.convert(point, to: surface.superview), event: event(type, point, flags: flags))
    }
    func stop() { surface.stop(); window.close() }
}

@MainActor private final class HostingState {
    var current = true
    var surface: MacConfigurationSelectionSurface.Surface?
}
private struct HostedSurface: NSViewRepresentable {
    let state: HostingState
    func makeNSView(context: Context) -> MacConfigurationSelectionSurface.Surface {
        let view = MacConfigurationSelectionSurface.Surface(); state.surface = view; return view
    }
    func updateNSView(_ view: MacConfigurationSelectionSurface.Surface, context: Context) {
        view.configuration = MacConfigurationSelectionSurface(frames: [:], enabled: true,
            isCurrentPage: { state.current }, click: { _, _ in }, drag: { _ in }, selectAll: {}, clear: {}, delete: {})
        view.synchronizeLifecycle()
    }
    static func dismantleNSView(_ view: MacConfigurationSelectionSurface.Surface, coordinator: ()) { view.stop() }
}

@main enum SelectionEventCheck {
    @MainActor static func main() {
        _ = NSApplication.shared
        var passed = 0
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            guard condition() else { fatalError("FAIL: \(name)") }
            passed += 1; print("PASS: \(name)")
        }
        let f = Fixture(); defer { f.stop() }
        check("card participates in native hit testing", f.hit(CGPoint(x: 60, y: 60)) === f.surface)
        f.surface.mouseDown(with: f.event(.leftMouseDown, CGPoint(x: 60, y: 60)))
        f.surface.mouseUp(with: f.event(.leftMouseUp, CGPoint(x: 60, y: 60)))
        check("native mouse-up completes one click", f.clicks == 1)
        check("sidebar is outside surface", f.hit(CGPoint(x: -100, y: 300)) == nil)
        check("toolbar is outside surface", f.hit(CGPoint(x: 100, y: -40)) == nil)
        check("refresh target remains native", f.hit(CGPoint(x: 275, y: 45)) == nil)
        check("right-click uses native context menu", f.hit(CGPoint(x: 60, y: 60), type: .rightMouseDown) == nil)
        check("control-click uses native context menu", f.hit(CGPoint(x: 60, y: 60), flags: .control) == nil)
        let scrollEvent = NSEvent(cgEvent: CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 10, wheel2: 0, wheel3: 0)!)!
        check("scroll events pass through", f.surface.selectionHitTest(CGPoint(x: 60, y: 60), event: scrollEvent) == nil)
        f.surface.mouseDown(with: f.event(.leftMouseDown, CGPoint(x: 60, y: 60)))
        f.surface.mouseDragged(with: f.event(.leftMouseDragged, CGPoint(x: 120, y: 180)))
        check("native drag starts marquee", f.drags == 1)
        f.surface.mouseUp(with: f.event(.leftMouseUp, CGPoint(x: -100, y: 300)))
        check("drag can finish outside without activation", f.clicks == 1)
        check("next sidebar click still outside hit target", f.hit(CGPoint(x: -100, y: 300)) == nil)
        f.surface.mouseDown(with: f.event(.leftMouseDown, CGPoint(x: 60, y: 60)))
        f.surface.mouseDragged(with: f.event(.leftMouseDragged, CGPoint(x: 120, y: 180)))
        f.active = false
        check("retained outgoing surface never hit", f.hit(CGPoint(x: 60, y: 60)) == nil)
        f.surface.mouseUp(with: f.event(.leftMouseUp, CGPoint(x: 60, y: 60)))
        check("outgoing gesture cancelled and focus released", f.cancellations == 1 && f.window.firstResponder !== f.surface && f.clicks == 1)
        f.active = true
        f.surface.configuration?.enabled = false
        check("busy surface passes through", f.hit(CGPoint(x: 60, y: 60)) == nil)
        f.surface.configuration?.enabled = true
        f.surface.isHidden = true
        check("hidden surface passes through", f.hit(CGPoint(x: 60, y: 60)) == nil)
        f.surface.isHidden = false
        f.window.makeFirstResponder(f.surface)
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: f.window.windowNumber, context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
        check("current-page select-all uses responder chain", f.surface.performKeyEquivalent(with: key) && f.selections == 1)
        f.active = false
        check("outgoing page relinquishes keyboard", f.surface.handleSelectionEvent(key) != nil && f.selections == 1)

        // Real SwiftUI hosting/scroll ancestry, including an attached outgoing view.
        let state = HostingState()
        let host = NSHostingView(rootView: HStack(spacing: 0) {
            VStack { Button("Home") {}; Button("Configurations") {}; Spacer() }.frame(width: 220)
            ScrollView { Color.black.frame(height: 1000).overlay { HostedSurface(state: state) } }
        })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1)); host.layoutSubtreeIfNeeded()
        guard let surface = state.surface, surface.superview != nil else { fatalError("SwiftUI surface not mounted") }
        check("SwiftUI overlay has actual scroll viewport", surface.enclosingScrollView != nil)
        func hostedHit(_ location: CGPoint) -> NSView? {
            let event = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            return surface.selectionHitTest(surface.superview!.convert(location, from: nil), event: event)
        }
        check("hosted content receives selection", hostedHit(CGPoint(x: 450, y: 300)) === surface)
        check("hosted sidebar not claimed", hostedHit(CGPoint(x: 100, y: 300)) == nil)
        check("hosted toolbar not claimed", hostedHit(CGPoint(x: 500, y: 670)) == nil)
        for _ in 0..<100 {
            state.current = false
            check("retained hosted outgoing view passes through", hostedHit(CGPoint(x: 450, y: 300)) == nil)
            state.current = true
            precondition(hostedHit(CGPoint(x: 100, y: 300)) == nil)
        }
        surface.stop(); window.close()
        print("\(passed) selection checks passed; no desktop events posted, no VPN or network used.")
    }
}
