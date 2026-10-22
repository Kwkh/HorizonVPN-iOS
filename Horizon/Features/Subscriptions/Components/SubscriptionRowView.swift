import SwiftUI

struct SubscriptionRowView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let subscription: SubscriptionSummary
    let isCurrent: Bool
    var isPending = false
    private var emphasis: Bool { isCurrent || isPending }
    private var showsCurrent: Bool { isCurrent && !isPending }
    private var currentLabel: String { settings.text("当前", "Current") }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(subscription.title).font(.headline).lineLimit(2)
                    .foregroundStyle(Color.primary.opacity(emphasis ? 1 : 0.72))
                    .animation(.easeInOut(duration: reduceMotion ? 0.2 : 0.3), value: emphasis)
                Spacer(minLength: 8)
                // Invisible templates keep both symbol and localized text slots
                // stable; the actual status content can transition independently.
                HStack(spacing: 6) {
                    ZStack {
                        Image(systemName: "checkmark.circle.fill")
                            .hidden().accessibilityHidden(true)
                        if showsCurrent {
                            Image(systemName: "checkmark.circle.fill")
                                .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.appear)))
                                .accessibilityHidden(true)
                        }
                    }
                    ZStack(alignment: .trailing) {
                        Text(currentLabel).hidden().accessibilityHidden(true)
                        Text(showsCurrent ? currentLabel : " ")
                            .contentTransition(reduceMotion ? .opacity : .numericText(value: showsCurrent ? 1 : 0))
                    }
                }
                .font(.caption).foregroundStyle(.tint)
                .fixedSize(horizontal: true, vertical: false)
                .overlay(alignment: .trailing) {
                    ProgressView().controlSize(.small)
                        .opacity(isPending ? 1 : 0)
                        .accessibilityHidden(true)
                }
                .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: showsCurrent)
                .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: isPending)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(isPending ? settings.text("正在切换订阅", "Switching subscription") : currentLabel)
                .accessibilityHidden(!showsCurrent && !isPending)
            }
            Text(settings.subscriptionSummary(subscription)).font(.subheadline).foregroundStyle(.secondary)
            if let date = subscription.importedAt {
                Text(date, format: .dateTime.month().day().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(settings.text("旧版迁移 · 可重命名", "Migrated · Rename or reimport to add a filename"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
