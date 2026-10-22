import SwiftUI

/// Captures continuation drags across the last chapter without covering its buttons.
struct HorizonGuidePullSurface<Content: View>: View {
    let enabled: Bool
    let referenceHeight: CGFloat
    let changed: (CGFloat, CGFloat) -> Void
    let ended: (Bool) -> Void
    @ViewBuilder var content: () -> Content
    @GestureState private var touching = false
    @State private var tracking = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content()
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance:8)
                .updating($touching) { _, state, _ in state = true }
                .onChanged { value in
                    guard enabled else { return }
                    tracking = true
                    // Keep the original scene-sized travel even though the
                    // gesture can now begin anywhere on the page.
                    changed(value.translation.height,referenceHeight)
                }
                .onEnded { _ in
                    guard tracking else { return }
                    tracking = false
                    ended(false)
                }, including:enabled ? .all : .subviews)
        .onChange(of:touching) { _, active in
            if !active && tracking { tracking = false; ended(true) }
        }
        .onChange(of:enabled) { _, enabled in
            if !enabled && tracking { tracking = false; ended(true) }
        }
        .onChange(of:scenePhase) { _, phase in
            if phase != .active && tracking { tracking = false; ended(true) }
        }
    }
}
