import SwiftUI

/// Cached paths and one Canvas avoid creating one SwiftUI view per QR module.
struct SubscriptionQRCodeArtwork: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress = 0.0
    @State private var visible = false
    private let paths: [Path]
    private let dimension: Int
    private let onShareReveal: () -> Void

    init(pattern: SubscriptionQRPattern, onShareReveal: @escaping () -> Void) {
        paths = pattern.paths().map { Path($0) }
        dimension = pattern.fullDimension
        self.onShareReveal = onShareReveal
    }

    var body: some View {
        SubscriptionQRCodeCanvas(paths: paths, dimension: dimension, progress: progress, reduceMotion: reduceMotion)
            .task {
                visible = true
                // Give the page a brief settling pause before revealing the cached artwork.
                do { try await Task.sleep(for: .milliseconds(reduceMotion ? 30 : 200)) }
                catch { return }
                let duration = reduceMotion ? 0.18 : 1.2
                withAnimation(reduceMotion ? .easeOut(duration: duration) : .linear(duration: duration)) {
                    progress = 1
                }
                // The construction's total progress is linear: half its duration is its midpoint.
                // Keeping this wait in the view task cancels it on dismissal or a new QR generation.
                do { try await Task.sleep(for: .seconds(duration / 2)) }
                catch { return }
                if visible && !Task.isCancelled { onShareReveal() }
            }
            .onDisappear { visible = false }
            .onChange(of: reduceMotion) { _, reduced in
                if reduced {
                    withAnimation(.easeOut(duration: 0.18), completionCriteria: .removed) { progress = 1 } completion: {
                        if visible { onShareReveal() }
                    }
                }
            }
    }
}

struct SubscriptionQRCodeCanvas: View, Animatable {
    @Environment(\.displayScale) private var displayScale
    let paths: [Path]
    let dimension: Int
    var progress: Double
    let reduceMotion: Bool
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let layout = SubscriptionQRPattern.pixelLayout(size: size, dimension: dimension, displayScale: displayScale)
            context.translateBy(x: layout.origin.x, y: layout.origin.y)
            context.scaleBy(x: layout.unit, y: layout.unit)
            // Separate opacity groups must not blend fractional coverage at shared edges.
            let fill = FillStyle(antialiased: false)
            if progress >= 1 {
                // Final artwork uses one fill, matching the exported image at shared edges.
                var path = Path()
                for group in paths { path.addPath(group) }
                context.fill(path, with: .color(.white), style: fill)
            } else {
                for (group, path) in paths.enumerated() {
                    context.opacity = reduceMotion ? progress : SubscriptionQRPattern.opacity(progress: progress, group: group)
                    context.fill(path, with: .color(.white), style: fill)
                }
            }
        }
    }
}
