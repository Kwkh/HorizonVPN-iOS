import SwiftUI

/// Captures drags only inside the illustrative scene, leaving text scrolling alone.
struct HorizonCameraDragSurface: View {
    let camera: HorizonIntroCamera
    let enabled: Bool
    let animated: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @GestureState private var touching = false

    var body: some View {
        GeometryReader { geometry in
            Color.clear.contentShape(Rectangle())
                .highPriorityGesture(DragGesture(minimumDistance:8)
                    .updating($touching) { _, state, _ in state = true }
                    .onChanged { value in
                        camera.update(translation:[Float(value.translation.width),Float(value.translation.height)],
                            viewport:[Float(geometry.size.width),Float(geometry.size.height)])
                    }
                    .onEnded { _ in camera.end(animated:animated && !reduceMotion) })
        }
        .allowsHitTesting(enabled)
        .accessibilityHidden(true)
        .onChange(of:touching) { _, touching in
            if !touching { camera.end(animated:animated && !reduceMotion) }
        }
        .onChange(of:scenePhase) { _, phase in if phase != .active { camera.reset() } }
    }
}
