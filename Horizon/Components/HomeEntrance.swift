import SwiftUI

/// Presentation-only cold-launch animation shared by both home styles.
/// The root owns the one-shot flag; this modifier never restarts on appearance.
struct HomeEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let presented: Bool
    var delay: Double = 0
    var rise: CGFloat = 8

    func body(content: Content) -> some View {
        content
            // Limit the transaction to these presentation effects. Live charts,
            // numeric transitions and the Metal camera retain their own timing.
            .animation(reduceMotion ? .easeOut(duration: 0.18) : .easeOut(duration: 0.42).delay(delay)) { view in
                view.opacity(presented ? 1 : 0)
                    .offset(y: presented || reduceMotion ? 0 : rise)
            }
            .allowsHitTesting(presented)
            .accessibilityHidden(!presented)
    }
}
