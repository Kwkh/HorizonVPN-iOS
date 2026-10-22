import SwiftUI

struct HorizonGuideSwipeHint: View {
    @ScaledMetric(relativeTo: .title2) private var fontSize: CGFloat = 26
    let active: Bool
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.animation(minimumInterval:1.0/30,paused:!active || scenePhase != .active || reduceMotion || !settings.particles)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate * .pi / 1.8
            let drift = reduceMotion || !settings.particles ? 0 : (1-cos(phase))*3
            HStack(spacing:12) {
                Image(systemName:"arrow.down")
                    .font(.system(size:28,weight:.light)).offset(y:drift)
                Text(settings.text("下滑以继续", "Swipe to continue"))
                    .font(.system(size:fontSize,weight:.light))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
        }
        .allowsHitTesting(false)
    }
}
