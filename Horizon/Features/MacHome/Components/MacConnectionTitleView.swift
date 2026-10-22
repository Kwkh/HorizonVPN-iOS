#if os(macOS)
import SwiftUI

/// Observe display-frame formation here, without rebuilding the chart or scene.
struct MacConnectionTitleView: View {
    let library: MacLibraryStore
    let progress: HorizonSceneProgress
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var title: String {
        if library.vpn.working { return settings.text("连接中", "Connecting") }
        if library.vpn.status == .connected && progress.formation < 0.98 { return settings.text("连接中", "Connecting") }
        return library.vpn.title
    }
    var body: some View {
        Text(title).font(.system(size: 32, weight: .light)).contentTransition(.numericText())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: title)
    }
}
#endif
