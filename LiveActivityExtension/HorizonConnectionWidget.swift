import SwiftUI
import WidgetKit

struct HorizonConnectionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ConnectionWidgetState.widgetKind, provider: Provider()) { entry in
            ConnectionWidgetView(state: entry.state)
                .containerBackground(.black, for: .widget)
        }
        .configurationDisplayName("HORIZON VPN")
        .description("Connect or disconnect your current configuration.")
        .supportedFamilies([.systemSmall])
    }
    struct Entry: TimelineEntry { var date: Date; var state: ConnectionWidgetState }
    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry { .init(date: .now, state: .init(phase: .disconnected, subscription: "HORIZON")) }
        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            completion(context.isPreview ? placeholder(in: context) : .init(date: .now, state: .read()))
        }
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            completion(Timeline(entries: [.init(date: .now, state: .read())], policy: .after(.now.addingTimeInterval(900))))
        }
    }
}

private struct ConnectionWidgetView: View {
    let state: ConnectionWidgetState
    private var status: LocalizedStringKey {
        switch state.phase {
        case .unavailable: "Open HORIZON to set up"
        case .disconnected: "Disconnected"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .reconnecting: "Reconnecting"
        case .disconnecting: "Disconnecting"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "globe.europe.africa").font(.title2)
                Spacer()
                Text("HORIZON").font(.caption2).tracking(2)
            }
            Text(status).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
            if !state.subscription.isEmpty {
                Text(state.subscription).font(.caption).foregroundStyle(.secondary).lineLimit(1).privacySensitive()
            }
            Spacer(minLength: 0)
            Button(intent: SetVPNConnectionIntent(value: !state.phase.isOn)) {
                Text(state.phase.isOn ? LocalizedStringKey("Disconnect") : LocalizedStringKey("Connect"))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Capsule())
            }
            .buttonStyle(ConnectionWidgetButtonStyle())
        }
        .foregroundStyle(.white)
    }
}
