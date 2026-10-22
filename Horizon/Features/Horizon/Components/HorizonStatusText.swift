import SwiftUI

/// Isolate the native content animation from the title's per-frame scene tracking.
struct HorizonStatusText: View {
    let status: String
    let fontSize: CGFloat
    let lineHeight: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedStatus: String
    @State private var transitionIndex: Double = 0

    init(status: String, fontSize: CGFloat, lineHeight: CGFloat) {
        self.status = status
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        _displayedStatus = State(initialValue: status)
    }

    private var animationDuration: Double {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["CLASH_HORIZON_PREVIEW"] == "1", environment["CLASH_HORIZON_SLOW_TEXT"] == "1" {
            return 3.25 // Offline preview only: expose intermediate native transition frames.
        }
        #endif
        return 0.65
    }

    var body: some View {
        Text(displayedStatus)
            .font(.system(size: fontSize, weight: .light))
            .lineLimit(1).minimumScaleFactor(0.75)
            .contentTransition(reduceMotion ? .opacity : .numericText(value: transitionIndex))
            .frame(maxWidth: .infinity)
            .frame(height: lineHeight)
            // The value tells the native transition its direction even for status words.
            .onChange(of: status) { _, next in
                withAnimation(.smooth(duration: reduceMotion ? 0.2 : animationDuration)) {
                    displayedStatus = next
                    transitionIndex += 1
                }
            }
    }
}
