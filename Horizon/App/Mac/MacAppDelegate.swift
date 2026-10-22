#if os(macOS)
import AppKit

final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Closing the window leaves the menu bar controls available. Explicit
        // Quit retains the existing app termination / system VPN behavior.
        false
    }
}
#endif
