import SwiftUI

/// The introduction exposes only an exit; connection controls retain their real meaning.
struct HorizonIntroductionControls: View {
    let skip: () -> Void
    let visible: Bool
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    var body: some View {
        Button(action: skip) {
            Text(settings.text("跳过", "Skip"))
                .font(.callout.weight(.medium))
                .padding(.horizontal, 20).frame(minHeight: 44)
        }
        .buttonStyle(.glass).buttonBorderShape(.capsule)
        .accessibilityIdentifier("home.skipIntroduction")
        .padding(.trailing, 26).padding(.top, 8)
        .opacity(appeared ? 1 : 0)
        .allowsHitTesting(visible && appeared)
        .accessibilityHidden(!visible)
        .task(id:visible) {
            // The matched-frame swap disables animations in its transaction.
            // Start this independent UI fade on the following view update.
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration:reduceMotion ? 0.2 : 0.45)) { appeared = visible }
        }
    }
}
