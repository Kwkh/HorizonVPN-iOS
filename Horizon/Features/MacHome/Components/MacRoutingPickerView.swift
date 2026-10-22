#if os(macOS)
import SwiftUI

struct MacRoutingPickerView: View {
    let library: MacLibraryStore
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(settings.text("分流方案", "Routing")).font(.caption).foregroundStyle(.secondary)
            Picker(settings.text("分流方案", "Routing"), selection: Binding(
                get: { library.pendingRouting ?? library.routing },
                set: { library.changeRouting($0) }
            )) {
                Text(settings.text("遵循订阅", "Subscription")).tag(ConfigurationRouting.subscription)
                Text(settings.text("智能分流", "Smart routing")).tag(ConfigurationRouting.smart)
            }
            .pickerStyle(.segmented).labelsHidden()
            .disabled(library.prepared == nil)
            .allowsHitTesting(library.canChangeRouting)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: library.pendingRouting ?? library.routing)
        }
    }
}
#endif
