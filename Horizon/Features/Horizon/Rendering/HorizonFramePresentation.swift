import MetalKit

/// Device handoffs wait for display presentation, not a guessed animation delay.
enum HorizonFramePresentation {
    static func observe(_ drawable: CAMetalDrawable, command: MTLCommandBuffer,
                        completion: @escaping () -> Void) {
#if targetEnvironment(simulator)
        // Simulator SDK omits MTLDrawable's presentation callback. GPU completion
        // is the closest available signal; recorded simulator playback is checked separately.
        command.addCompletedHandler { buffer in
            guard buffer.status == .completed else { return }
            completion()
        }
#else
        drawable.addPresentedHandler { _ in completion() }
#endif
    }
}
