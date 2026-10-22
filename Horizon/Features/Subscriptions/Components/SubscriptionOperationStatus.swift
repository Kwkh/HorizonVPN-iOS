import SwiftUI

/// A stable one-line status slot: activity never inserts/removes list rows.
struct SubscriptionOperationStatus: View {
    let busy: Bool
    let message: String?
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).opacity(busy ? 1 : 0)
                .accessibilityHidden(!busy)
            Text(busy ? settings.text("正在处理…", "Working…") : (message == nil ? " " : settings.text("查看操作结果", "View result")))
                .foregroundStyle(.secondary).contentTransition(.opacity)
            Spacer()
            if let message, !busy {
                InformationButton(title: settings.text("操作结果", "Result"),
                    paragraphs: [settings.text(message, DiagnosticText.importEnglish(message))])
            }
        }
        .frame(minHeight: 44)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: busy)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: message)
        .accessibilityHidden(!busy && message == nil)
    }
}
