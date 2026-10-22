import SwiftUI

/// Reuses the home's history and renderer without starting another sampler.
struct TabletSidebarTrafficView: View {
    let telemetry: TelemetryStore
    let visible: Bool
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var onscreen = false

    private var uploadColor: Color {
        settings.isHorizon ? .primary.opacity(0.5) : Color(red: 0.82, green: 0.08, blue: 0.17)
    }
    private var downloadColor: Color {
        settings.isHorizon ? .primary : ClashStyle.accent(scheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollingTrafficPlot(points: telemetry.window.points,
                uploadColor: uploadColor, downloadColor: downloadColor,
                running: visible && onscreen && scenePhase == .active,
                reduceMotion: reduceMotion, ceiling: settings.trafficScale.rawValue,
                logarithmic: settings.trafficMapping == .logarithmic)
                .transaction { $0.animation = nil }
                .frame(height: 64)
                .accessibilityHidden(true)
            VStack(spacing: 9) {
                rate("arrow.up", label: settings.text("上传", "Upload"),
                    bytes: telemetry.window.current?.upload, color: uploadColor)
                rate("arrow.down", label: settings.text("下载", "Download"),
                    bytes: telemetry.window.current?.download, color: downloadColor)
            }
            .font(.caption)
        }
        // Keep the footer mounted across pages and navigation visibility changes
        // so the native sidebar's viewport and navigation rows stay in place.
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 18)
        .opacity(visible ? 1 : 0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: visible)
        .allowsHitTesting(false)
        .accessibilityHidden(!visible)
        .accessibilityIdentifier("tablet.sidebar.traffic")
        .onAppear { onscreen = true }
        .onDisappear { onscreen = false }
    }

    private func rate(_ symbol: String, label: String, bytes: Double?, color: Color) -> some View {
        let value = bytes.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let parts = TrafficChartView.rateText(value ?? 0).split(separator: " ")
        let number = value == nil ? "—" : String(parts[0])
        let unit = String(parts.last ?? "B/s")
        return HStack(spacing: 0) {
            Image(systemName: symbol).frame(width: 16)
            Spacer(minLength: 8)
            Text(number)
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                .contentTransition(.numericText(value: value ?? 0))
                .animation(reduceMotion || !visible ? nil : .easeInOut(duration: 0.28), value: number)
                .frame(width: 72, alignment: .trailing).padding(.trailing, 10)
            Text(unit)
                .lineLimit(1).minimumScaleFactor(0.75).contentTransition(.opacity)
                .animation(reduceMotion || !visible ? nil : .easeInOut(duration: 0.28), value: unit)
                .frame(width: 44, alignment: .trailing)
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value == nil ? settings.text("暂无数据", "No data") : "\(number) \(unit)")
    }
}
