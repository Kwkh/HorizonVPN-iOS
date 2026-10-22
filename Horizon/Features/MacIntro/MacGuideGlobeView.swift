#if os(macOS)
import SwiftUI
import MetalKit

/// Transparent Metal globe below the guide's opaque Canvas bricks.
struct HorizonGuideGlobeView: NSViewRepresentable {
    let frame: HorizonRenderFrame
    let presentation: HorizonGuidePresentation
    let playback: HorizonGuidePlayback
    let bridgePresented: (HorizonGuidePresentation) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame:.zero,device:MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.sampleCount = 4
        view.clearColor = MTLClearColorMake(0,0,0,0)
        view.layer?.isOpaque = false
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        if let device = view.device, let library = device.makeDefaultLibrary() {
            context.coordinator.queue = device.makeCommandQueue()
            context.coordinator.particles = HorizonParticlePass(device:device,library:library,
                format:view.colorPixelFormat,samples:view.sampleCount)
        }
        view.delegate = context.coordinator
        return view
    }
    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.frame = frame
        context.coordinator.presentation = presentation
        context.coordinator.playback = playback
        context.coordinator.bridgePresented = bridgePresented
        // Draw this exact TimelineView sample without another deferred AppKit
        // display cycle, keeping the Metal globe beside its Canvas wall in time.
        view.draw()
    }
    static func dismantleNSView(_ view: MTKView, coordinator: Coordinator) {
        view.delegate = nil
        coordinator.particles = nil
        coordinator.queue = nil
    }
    final class Coordinator: NSObject, MTKViewDelegate {
        var particles: HorizonParticlePass?
        var queue: MTLCommandQueue?
        var frame: HorizonRenderFrame?
        var presentation: HorizonGuidePresentation?
        weak var playback: HorizonGuidePlayback?
        var bridgePresented: ((HorizonGuidePresentation) -> Void)?
        private var acknowledgedTransition: UUID?
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { view.setNeedsDisplay() }
        func draw(in view: MTKView) {
            guard let particles, var frame, let presentation, let pass = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable, let command = queue?.makeCommandBuffer(),
                  let encoder = command.makeRenderCommandEncoder(descriptor:pass) else { return }
            frame.viewport.x = Float(view.contentScaleFactor)
            frame.vp = HorizonGuideTransition.embed(presentation.viewport,in:view.bounds.size)*frame.vp
            if frame.introduction.y > 0 {
                particles.encode(encoder,frame:frame,stride:HorizonParticlePass.constrained ? 2 : 1)
            }
            encoder.endEncoding()
            HorizonFramePresentation.observe(drawable,command:command) { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.playback?.presented(presentation)
                    if presentation.transitionID != nil, presentation.progress == 0 {
                        self.bridgePresented?(presentation)
                    }
                    if let id = presentation.transitionID, presentation.progress >= 1,
                       self.acknowledgedTransition != id {
                        self.acknowledgedTransition = id
                        self.bridgePresented?(presentation)
                    }
                }
            }
            command.present(drawable)
            command.commit()
        }
    }
}

#endif
