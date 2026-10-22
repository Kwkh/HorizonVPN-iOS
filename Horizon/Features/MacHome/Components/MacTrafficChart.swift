#if os(macOS)
import SwiftUI

/// The native surface owns the display clock; SwiftUI only delivers new samples.
struct MacTrafficChart: View {
    let telemetry: MacTelemetryStore
    let active: Bool
    var compact = false
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 18) {
            if compact {
                Text(settings.text("实时流量", "Live traffic")).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top) {
                    Text(settings.text("实时流量", "Live traffic")).font(.headline)
                    Spacer(minLength: 16)
                    readout.frame(width: 196, alignment: .trailing)
                }
            }
            MacScrollingTrafficPlot(points: telemetry.window.points, running: active,
                reduceMotion: reduceMotion, ceiling: settings.trafficScale.rawValue,
                logarithmic: settings.trafficMapping == .logarithmic)
                .transaction { $0.animation = nil }
                .frame(height: compact ? 64 : 110).clipped().accessibilityHidden(true)
            if compact {
                readout
            }
        }
    }
    private var readout: some View {
        VStack(spacing: compact ? 9 : 8) {
            rate("arrow.up", telemetry.window.current?.upload).foregroundStyle(.secondary)
            rate("arrow.down", telemetry.window.current?.download)
        }
        .font(.system(size: compact ? 12 : 14))
    }
    private func rate(_ symbol: String, _ bytes: Double?) -> some View {
        let value = MacTrafficRateText(bytes: bytes)
        return HStack(spacing: 0) {
            Image(systemName: symbol)
                .frame(width: compact ? 16 : 18)
                .accessibilityLabel(symbol == "arrow.up" ? settings.text("上传", "Upload") : settings.text("下载", "Download"))
            Spacer(minLength: 12)
            Text(value.number)
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8).contentTransition(.numericText())
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: value.number)
                .frame(width: compact ? 76 : 96, alignment: .trailing)
                .padding(.trailing, compact ? 14 : 18)
            Text(value.unit)
                .lineLimit(1).contentTransition(.opacity)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: value.unit)
                .frame(width: compact ? 34 : 42, alignment: .trailing)
        }
        .frame(height: compact ? 16 : 20)
        .accessibilityElement(children: .combine)
    }
}

private struct MacTrafficRateText {
    let number: String
    let unit: String

    init(bytes: Double?) {
        guard let bytes, bytes.isFinite, bytes >= 0 else {
            number = "—"; unit = "KB/s"; return
        }
        if bytes >= 1_000_000_000 {
            number = String(format: "%.2f", bytes / 1_000_000_000); unit = "GB/s"
        } else if bytes >= 1_000_000 {
            number = String(format: "%.2f", bytes / 1_000_000); unit = "MB/s"
        } else {
            number = String(format: "%.1f", bytes / 1_000); unit = "KB/s"
        }
    }
}
#endif
