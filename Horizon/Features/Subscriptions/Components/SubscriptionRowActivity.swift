import SwiftUI

/// Keeps a row's trailing accessory stable as selection changes into activity.
struct SubscriptionRowActivity: View {
    let busy: Bool
    var selected = false
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Image(systemName: "checkmark").opacity(selected && !busy ? 1 : 0)
            ProgressView().controlSize(.small).opacity(busy ? 1 : 0)
        }
        .frame(width: 24, height: 24)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: busy)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: selected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(busy ? settings.text("正在处理", "Working") : settings.text("已选择", "Selected"))
        .accessibilityHidden(!busy && !selected)
    }
}
