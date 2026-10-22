import ActivityKit
import SwiftUI
import WidgetKit

struct HorizonLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VPNActivityAttributes.self) { context in
            VPNActivityCard(context: context)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // One bottom-region layout keeps all text below the camera and within
                // the same safe bounds, rather than squeezing a title beside the cutout.
                DynamicIslandExpandedRegion(.bottom) {
                    VPNActivityCard(context: context)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                }
            } compactLeading: {
                globeIcon
                    .padding(.leading, 3)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                globeIcon
            }
            .contentMargins(.all, 12, for: .expanded)
            .keylineTint(.white)
        }
    }

    private var globeIcon: some View {
        Image(systemName: "globe.europe.africa")
            .font(.system(size: 20, weight: .regular))
            .frame(width: 24, height: 24)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.white)
            .accessibilityLabel("HORIZON")
    }
}
