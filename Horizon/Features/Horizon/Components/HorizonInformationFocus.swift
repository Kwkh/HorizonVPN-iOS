import SwiftUI

/// The information below the iPhone scene comes into focus as it enters view.
struct HorizonInformationFocus: ViewModifier {
    let enabled: Bool
    let scrollOffset: CGFloat
    let heroHeight: CGFloat
    let viewportHeight: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var reveal: CGFloat {
        let height = max(1, viewportHeight)
        let informationTop = heroHeight - max(0, scrollOffset)
        // Stay clear until the information's top reaches 80% of the viewport;
        // only the final approach to 94% blends it back into the scene.
        let progress = min(1, max(0, (height * 0.94 - informationTop) / (height * 0.14)))
        return progress * progress * (3 - 2 * progress)
    }

    func body(content: Content) -> some View {
        if enabled && !reduceTransparency {
            let focus = reveal
            content
                // The scroll position supplies the entire transition; no second
                // animation clock, layout change, or offscreen drawing group.
                .blur(radius: reduceMotion ? 0 : 8 * (1 - focus))
                .opacity(0.12 + 0.88 * focus)
                .overlay(alignment: .top) {
                    // Blend the information's leading edge into the black scene
                    // without masking the full, potentially long lazy node list.
                    LinearGradient(colors: [.black.opacity(1 - focus), .clear],
                        startPoint: .top, endPoint: .bottom)
                        .frame(height: 28)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        } else {
            content
        }
    }
}
