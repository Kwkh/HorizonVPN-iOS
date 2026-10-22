import SwiftUI

/// A stable background and hit area: pressing changes brightness, never geometry.
struct ConnectionWidgetButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Capsule()
                    .fill(.white)
                    .opacity(configuration.isPressed ? 0.22 : 0.12)
                    .animation(reduceMotion || luminanceReduced ? nil : .easeInOut(duration: 0.2),
                               value: configuration.isPressed)
            }
    }
}
