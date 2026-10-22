import SwiftUI

struct SessionEventsSection: View {
    let events: [TunnelController.Event]

    @Environment(AppSettings.self) private var settings

    var body: some View {
        Section(settings.text("本次会话记录", "Session events")) {
            ForEach(events) { event in
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.date, style: .time).foregroundStyle(.secondary)
                    Text(settings.text(event.message, DiagnosticText.english(event.message)))
                }
                .font(.caption)
            }
        }
    }
}
