import ActivityKit
import SwiftUI
import WidgetKit

struct VPNActivityCard: View {
    let context: ActivityViewContext<VPNActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Label("HORIZON", systemImage: "globe.europe.africa")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(context.state.status(chinese: context.attributes.chinese, stale: context.isStale))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                Text(context.state.nodeLabel ?? (context.attributes.chinese ? "打开 App 更新" : "Open app to update"))
                    .font(.headline).lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.opacity)
                VPNActivityPingButton(sessionID: context.attributes.sessionID,
                    chinese: context.attributes.chinese, state: context.state,
                    stale: context.isStale,
                    enabled: pingEnabled)
            }
        }
        .foregroundStyle(.white)
        .lineLimit(1).minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity)
    }

    private var pingEnabled: Bool {
        #if DEBUG && targetEnvironment(simulator)
        if context.attributes.isDemo { return true }
        #endif
        return !context.attributes.isDemo && context.state.phase == .connected
    }
}
