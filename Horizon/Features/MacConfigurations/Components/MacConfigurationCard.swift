#if os(macOS)
import SwiftUI

struct MacConfigurationCard: View {
    let entry: SubscriptionSummary
    let isCurrent: Bool
    let isSelected: Bool
    let canActivate: Bool
    let canRefresh: Bool
    let refreshEnabled: Bool
    let refreshing: Bool
    let usage: SubscriptionDownloader.Usage?
    let activate: () -> Void
    let refresh: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var highlighted: Bool { isCurrent || isSelected }

    var body: some View {
        Button {
            activate()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "square.3.layers.3d").foregroundStyle(.secondary)
                    Text(entry.title).font(.headline).lineLimit(1)
                    Spacer(minLength: 0)
                }.padding(.trailing, 32).frame(height: 24)
                VStack(alignment: .leading, spacing: 10) {
                    if let usage, let summary = usageSummary(usage) {
                        importLabel
                        VStack(alignment: .leading, spacing: 7) {
                            Text(summary)
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                                .contentTransition(.numericText())
                            GeometryReader { geometry in
                                Capsule().fill(.white.opacity(0.12))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(.white.opacity(0.65))
                                            .frame(width: geometry.size.width * (usage.remainingFraction ?? 0))
                                    }
                            }.frame(height: 3).opacity(usage.remainingFraction == nil ? 0 : 1)
                            .accessibilityHidden(usage.remainingFraction == nil)
                            .accessibilityLabel(MacText.value("剩余额度", "Remaining allowance"))
                            .accessibilityValue("\(Int((usage.remainingFraction ?? 0) * 100))%")
                        }
                        .help(MacText.value("服务商更新于：", "Reported by provider: ") + usage.fetchedAt.formatted(date: .abbreviated, time: .shortened))
                    } else {
                        Spacer(minLength: 0)
                        importLabel
                    }
                }.frame(height: 54, alignment: .bottomLeading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .help(canActivate ? MacText.value("单击切换订阅 · ⌘ 点击或拖动框选 · 右键管理", "Click to activate · ⌘-click or drag to select · Right-click to manage") : MacText.value("⌘ 点击或拖动框选 · 右键管理", "⌘-click or drag to select · Right-click to manage"))
        .accessibilityAddTraits(highlighted ? [.isSelected] : [])
        // A sibling button, never nested in the selection button's label.
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                        .opacity(refreshing ? 0 : 1)
                        .overlay { ProgressView().controlSize(.small).opacity(refreshing ? 1 : 0) }
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(!canRefresh)
                .allowsHitTesting(refreshEnabled && !refreshing)
                .opacity(canRefresh || refreshing ? 1 : 0)
                .accessibilityHidden(!canRefresh && !refreshing)
                .help(MacText.value("刷新订阅", "Refresh configuration"))
                .accessibilityLabel(MacText.value("刷新订阅", "Refresh configuration"))
            }.frame(height: 24).padding(16)
        }
        // Single and marquee selection share one appearance. Only decoration
        // animates; the card and its refresh target keep the same geometry.
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(highlighted ? 0.09 : hovered ? 0.065 : 0.035))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: highlighted)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.white.opacity(highlighted ? 0.4 : hovered ? 0.2 : 0.1), lineWidth: 1)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: highlighted)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
        }
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: refreshing)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: usage)
    }

    @ViewBuilder private var importLabel: some View {
        if let importedAt = entry.importedAt {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(importTime(importedAt, now: context.date))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .help(importedAt.formatted(date: .abbreviated, time: .shortened))
        }
    }

    private func bytes(_ value: UInt64) -> String {
        var amount = Double(value)
        let units = ["B", "KB", "MB", "GB", "TB", "PB", "EB"]
        var unit = 0
        while amount >= 1000 && unit < units.count - 1 { amount /= 1000; unit += 1 }
        return amount.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: MacText.isChinese ? "zh_CN" : "en_US"))) + " " + units[unit]
    }
    private func usageSummary(_ usage: SubscriptionDownloader.Usage) -> String? {
        if let remaining = usage.remaining, let total = usage.total {
            return MacText.value("剩余 ", "Remaining ") + bytes(remaining) + " / " + bytes(total)
        }
        if let total = usage.total, total > 0 {
            return MacText.value("额度 ", "Allowance ") + bytes(total) + MacText.value(" · 用量未知", " · Usage unavailable")
        }
        if let used = usage.used { return MacText.value("已用 ", "Used ") + bytes(used) }
        return nil
    }
    private func importTime(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 60 { return MacText.value("刚刚导入", "Imported just now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: MacText.isChinese ? "zh_CN" : "en_US")
        formatter.unitsStyle = .short
        return MacText.value("导入于 ", "Imported ") + formatter.localizedString(for: date, relativeTo: now).replacingOccurrences(of: "min.", with: "min")
    }
}
#endif
