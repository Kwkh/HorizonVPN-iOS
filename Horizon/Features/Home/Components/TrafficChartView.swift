import SwiftUI

struct TrafficChartView: View {
    let telemetry: TelemetryStore
    let visible: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var uploadColor: Color { settings.isHorizon ? .white.opacity(0.5) : scheme == .dark ? Color(red: 1, green: 0.24, blue: 0.32) : Color(red: 0.82, green: 0.08, blue: 0.17) }
    private var downloadColor: Color { settings.isHorizon ? .white : ClashStyle.accent(scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Spacer()
                if exceedsScale {
                    Image(systemName: "arrow.up.to.line")
                        .foregroundStyle(uploadColor)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        .accessibilityLabel(settings.text("曲线超出量程，数字仍为真实速率", "Plot exceeds range; numbers show the actual rate"))
                }
                Menu {
                    Button {
                        settings.trafficMapping = .logarithmic
                    } label: {
                        Label(settings.text("细节（固定对数）", "Detail (fixed log)"),
                              systemImage: settings.trafficMapping == .logarithmic ? "checkmark" : "waveform.path")
                    }
                    Section(settings.text("固定线性量程", "Fixed linear range")) {
                        ForEach(AppSettings.TrafficScale.allCases, id: \.self) { scale in
                            Button {
                                settings.trafficScale = scale
                                settings.trafficMapping = .linear
                            } label: {
                                Label(scale.label, systemImage: settings.trafficMapping == .linear && settings.trafficScale == scale ? "checkmark" : "ruler")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(scaleLabel).monospacedDigit().contentTransition(.opacity)
                        Image(systemName: "chevron.up.chevron.down").font(.caption)
                    }.font(.callout).foregroundStyle(.secondary)
                }
                .accessibilityLabel(settings.text("纵轴量程", "Vertical range"))
                .accessibilityValue(scaleLabel)
                .accessibilityIdentifier("traffic.scale")
            }
            .animation(animation, value: exceedsScale)
            .animation(animation, value: settings.trafficScale)
            .animation(animation, value: settings.trafficMapping)
            ScrollingTrafficPlot(points: telemetry.window.points, uploadColor: uploadColor,
                downloadColor: downloadColor, running: visible && scenePhase == .active,
                reduceMotion: reduceMotion, ceiling: settings.trafficScale.rawValue,
                logarithmic: settings.trafficMapping == .logarithmic)
                // The plot owns its display clock. Parent status/Ping animations
                // must not interpolate a second animation into its UIKit updates.
                .transaction { $0.animation = nil }
                .frame(height: 90)
                .accessibilityLabel(settings.text("最近六十秒上传和下载速率", "Upload and download rate over the last 60 seconds"))
                .accessibilityValue(settings.trafficMapping == .logarithmic
                    ? settings.text("固定对数刻度，上限 10 MiB/s，曲线高度不与速率成正比", "Fixed logarithmic scale up to 10 MiB/s; height is not proportional to rate")
                    : scaleLabel)
            VStack(spacing: 16) {
                rate("arrow.up", label: settings.text("上传", "Upload"), value: telemetry.window.current?.upload, color: uploadColor)
                rate("arrow.down", label: settings.text("下载", "Download"), value: telemetry.window.current?.download, color: downloadColor)
            }
            Rectangle().fill(.primary.opacity(0.10)).frame(height: 0.5)
            HStack {
                Text(settings.text("累计", "Total"))
                Spacer()
                total("↓", label: settings.text("累计下载", "Downloaded"), bytes: telemetry.sample?.downloadBytes)
                total("↑", label: settings.text("累计上传", "Uploaded"), bytes: telemetry.sample?.uploadBytes)
            }.font(.callout).foregroundStyle(.secondary)
        }
    }
    private var exceedsScale: Bool {
        telemetry.window.points.contains {
            $0.isMeasured && max($0.upload, $0.download) > (settings.trafficMapping == .logarithmic
                ? TrafficPlotGeometry.logarithmicCeiling : settings.trafficScale.rawValue)
        }
    }
    private var scaleLabel: String {
        settings.trafficMapping == .logarithmic ? settings.text("对数", "Log") : settings.trafficScale.label
    }
    private var animation: Animation? { reduceMotion || !visible ? nil : .easeInOut(duration: 0.28) }
    private func total(_ symbol: String, label: String, bytes: Int64?) -> some View {
        HStack(spacing: 4) {
            Text(symbol)
            Text(bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .decimal) } ?? "—")
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(bytes ?? 0)))
        }
        .animation(animation, value: bytes)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .decimal) } ?? "—")
    }
    private func rate(_ symbol: String, label: String, value: Double?, color: Color) -> some View {
        let formatted = Self.rateText(value ?? 0).split(separator: " ")
        return HStack(alignment: .firstTextBaseline) {
            Image(systemName: symbol).font(.title2.weight(.light)).foregroundStyle(color)
                .accessibilityLabel(label)
            Spacer()
            Text(value == nil ? "—" : String(formatted[0]))
                .font(.system(size: 32, weight: .regular, design: .rounded)).monospacedDigit()
                .foregroundStyle(color).contentTransition(.numericText(value: value ?? 0))
            Text(String(formatted.last ?? "KB/s")).font(.title3).frame(width: 72, alignment: .trailing)
                .contentTransition(.opacity)
        }
        .animation(animation, value: value)
        .accessibilityElement(children: .combine)
    }
    static func rateText(_ value: Double) -> String {
        if value >= 1_000_000 { return String(format: "%.2f MB/s", value / 1_000_000) }
        if value >= 1000 { return String(format: "%.2f KB/s", value / 1000) }
        return String(format: "%.0f B/s", value)
    }
}
