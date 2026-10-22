import MetalKit
import simd

/// GPU scene owns only presentation. No sockets, subscriptions or VPN operations.
final class HorizonRenderer: NSObject, MTKViewDelegate {
    private let progress: HorizonSceneProgress
    private let queue: MTLCommandQueue
    private let wallPipeline: MTLRenderPipelineState
    private let wallDepth: MTLDepthStencilState
    private var faces: MTLBuffer
    private let particles: HorizonParticlePass
    private var faceCount: Int
    private weak var wallContact: HorizonWallContactGesture?
    private var wallContactSuppressed = false
    private var wallTouch: HorizonWallTouch
    private var touchBuffers: [MTLBuffer]
    private var touchBufferIndex = 0
    private let framesInFlight = DispatchSemaphore(value:3)
    private var globeScale: Float = 1
    private var brickScale: Float = 1
    private var motion = HorizonMotion()
    private var interaction = HorizonGlobeInteraction()
    private var lastFrame: CFTimeInterval?
    private var active = false
    private var animate = true
    private var phase: HorizonMotion.Phase = .idle
    private var introductionID: UUID?
    private var introduction: HorizonIntroduction?
    private var skipIntroduction = false
    private var introductionRotation: Double = 0
    private var introductionTime: Double = 0
    private var holdIntroduction = false
    private var reportedPreparedID: UUID?
    private var guideClock: HorizonSceneClock?
    private var introCamera: HorizonIntroCamera?

    init?(view: MTKView, progress: HorizonSceneProgress) {
        self.progress = progress
        guard let device = view.device, let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let particles = HorizonParticlePass(device:device,library:library,format:view.colorPixelFormat,samples:view.sampleCount) else { return nil }
        self.queue = queue
        let wall = HorizonGeometry.wall()
        faceCount = wall.faces.count
        wallTouch = HorizonWallTouch(faces:wall.faces,scale:1)
        touchBuffers = (0..<3).compactMap { _ in device.makeBuffer(length:((wall.faces.count-6)/36)*MemoryLayout<SIMD4<Float>>.stride,options:.storageModeShared) }
        guard touchBuffers.count == 3 else { return nil }
        guard let faces = device.makeBuffer(bytes: wall.faces, length: wall.faces.count*16) else { return nil }
        self.faces = faces
        self.particles = particles
        func pipeline(_ vertex: String, _ fragment: String) throws -> MTLRenderPipelineState {
            let p = MTLRenderPipelineDescriptor()
            p.vertexFunction = library.makeFunction(name: vertex); p.fragmentFunction = library.makeFunction(name: fragment)
            p.colorAttachments[0].pixelFormat = view.colorPixelFormat
            p.depthAttachmentPixelFormat = view.depthStencilPixelFormat
            p.rasterSampleCount = view.sampleCount
            return try device.makeRenderPipelineState(descriptor: p)
        }
        do {
            wallPipeline = try pipeline("horizon_wall", "horizon_wall_color")
        } catch { return nil }
        let depth = MTLDepthStencilDescriptor(); depth.depthCompareFunction = .lessEqual; depth.isDepthWriteEnabled = true
        guard let wallDepth = device.makeDepthStencilState(descriptor: depth) else { return nil }
        self.wallDepth = wallDepth
        super.init()
    }
    func configure(view: MTKView, phase: HorizonMotion.Phase, active: Bool, animate: Bool, brickScale: Float, globeScale: Float, interactiveJourney: Double? = nil, introductionID: UUID? = nil, skipIntroduction: Bool = false, holdIntroduction: Bool = false, guideRotation: Double? = nil, guideTime: Double? = nil, guideClock: HorizonSceneClock? = nil, introCamera: HorizonIntroCamera? = nil) {
        if self.introductionID != introductionID {
            reportedPreparedID = nil
            self.introductionID = introductionID
            introduction = introductionID.map { _ in HorizonIntroduction(destination: phase, reduced: !animate, continuesGlobe: guideRotation != nil) }
            introductionRotation = guideRotation ?? motion.rotation
            introductionTime = guideTime ?? motion.time
            lastFrame = nil
        }
        self.guideClock = guideClock
        self.introCamera = introCamera
        guideClock?.setRunning(active && animate)
        self.skipIntroduction = skipIntroduction
        if self.holdIntroduction != holdIntroduction { lastFrame = nil }
        self.holdIntroduction = holdIntroduction
        self.globeScale = min(2, max(1, globeScale))
        if self.brickScale != brickScale, let device = view.device {
            let wall = HorizonGeometry.wall(scale: brickScale)
            let newTouch = HorizonWallTouch(faces:wall.faces,scale:brickScale)
            let newBuffers = (0..<3).compactMap { _ in device.makeBuffer(length:newTouch.count*MemoryLayout<SIMD4<Float>>.stride,options:.storageModeShared) }
            if let newFaces = device.makeBuffer(bytes: wall.faces, length: wall.faces.count*16), newBuffers.count == 3 {
                wallTouch = newTouch
                touchBuffers = newBuffers
                faces = newFaces
                faceCount = wall.faces.count
                self.brickScale = brickScale
            }
        }
        if animate && phase == .recovering {
            // If recovery interrupts a globe drag, keep its orientation and
            // finish the existing gentle return while particles disperse.
            interaction.end(animated: true)
        } else if !active || phase != .connected { interaction.reset() }
        wallContactSuppressed = interactiveJourney != nil || introductionID != nil
        if !active { wallTouch.reset(); wallContact = nil }
        else if phase != self.phase || interactiveJourney != nil || introductionID != nil { wallTouch.settle() }
        let resumed = active && !self.active
        motion.select(phase, immediate: !animate, resuming: resumed)
        motion.scrub(to: animate && active ? interactiveJourney : nil, immediate: !animate || !active)
        self.phase = phase; self.active = active; self.animate = animate
        view.preferredFramesPerSecond = ProcessInfo.processInfo.isLowPowerModeEnabled ? 30 : 60
        view.isPaused = !active || (introduction == nil && (!animate || (phase == .idle && motion.journey == 0 && motion.formation == 0)) && !wallTouch.isActive)
        if view.isPaused || resumed { lastFrame = nil }
        view.enableSetNeedsDisplay = view.isPaused
        if active && view.isPaused { view.setNeedsDisplay() }
    }
    var canRotateGlobe: Bool {
        introduction == nil && active && phase == .connected && motion.journey > 0.995 && motion.formation > 0.98
    }
    private var canTouchWall: Bool {
        active && !wallContactSuppressed && introduction == nil
            && phase == .idle && motion.journey < 0.001
    }
    private func wallPoint(_ point: CGPoint, in view: MTKView) -> SIMD2<Float>? {
        guard canTouchWall, view.bounds.width > 0, view.bounds.height > 0 else { return nil }
        return HorizonWallTouch.hit(ndc:[2*Float(point.x/view.bounds.width)-1,1-2*Float(point.y/view.bounds.height)],
            aspect:Float(view.bounds.width/view.bounds.height),journey:Float(motion.journey))
    }
    func containsWall(_ point: CGPoint, in view: MTKView) -> Bool { wallPoint(point,in:view) != nil }
    func pulseWall(at point: CGPoint, in view: MTKView) {
        guard let hit = wallPoint(point, in: view) else { return }
        wallTouch.pulse(at: hit)
        if view.isPaused { lastFrame = nil }
        view.enableSetNeedsDisplay = false
        view.isPaused = false
    }
    func trackWallContact(_ contact: HorizonWallContactGesture, in view: MTKView) {
        wallContact = contact
        updateWallContact(in:view)
        if wallTouch.isActive {
            if view.isPaused { lastFrame = nil }
            view.enableSetNeedsDisplay = false
            view.isPaused = false
        }
    }
    func endWallContact() { wallContact = nil; wallTouch.release() }
    private func updateWallContact(in view: MTKView) {
        guard let wallContact else { return }
        guard let point = wallContact.point(in:view), let hit = wallPoint(point,in:view) else {
            wallTouch.release()
            return
        }
        wallTouch.move(to:hit)
    }
    private func globeFrame(in view: MTKView) -> CGRect {
        let camera = HorizonGeometry.camera(journey: Float(motion.journey))
        let width = Float(view.bounds.width), height = Float(view.bounds.height)
        guard width > 0, height > 0 else { return .zero }
        let vp = HorizonGeometry.perspective(aspect: width/height) * HorizonGeometry.view(eye: camera.eye, target: camera.target)
        func project(_ point: SIMD3<Float>) -> CGPoint {
            let clip = vp * SIMD4(point, 1)
            return CGPoint(x: CGFloat((clip.x/clip.w+1)*width/2), y: CGFloat((1-clip.y/clip.w)*height/2))
        }
        #if os(macOS)
        let sphere = (view as? MacMetalSurface)?.framedHomeGlobe(scale: globeScale, aspect: width/height)
            ?? HorizonGeometry.globe(scale: globeScale, aspect: width/height)
        #else
        let sphere = HorizonGeometry.globe(scale: globeScale, aspect: width/height)
        #endif
        let center = project([sphere.x,sphere.y,sphere.z])
        let edge = project([sphere.x+sphere.w,sphere.y,sphere.z])
        let radius = abs(edge.x-center.x)
        return CGRect(x: center.x-radius, y: center.y-radius, width: radius*2, height: radius*2)
    }
    func containsGlobe(_ point: CGPoint, in view: MTKView) -> Bool {
        guard canRotateGlobe else { return false }
        let width = Float(view.bounds.width), height = Float(view.bounds.height)
        guard width > 0, height > 0 else { return false }
        let point = SIMD2<Float>(2*Float(point.x)/width-1, 1-2*Float(point.y)/height)
        #if os(macOS)
        if let sphere = (view as? MacMetalSurface)?.framedHomeGlobe(scale: globeScale, aspect: width/height) {
            return MacHomeGlobeFraming.hitsGlobe(ndc: point, aspect: width/height,
                journey: Float(motion.journey), sphere: sphere)
        }
        #endif
        return HorizonGeometry.hitsGlobe(ndc: point, aspect: width/height,
            journey: Float(motion.journey), scale: globeScale)
    }
    func beginGlobeDrag(in view: MTKView) {
        guard canRotateGlobe else { return }
        interaction.begin()
        view.setNeedsDisplay()
    }
    func dragGlobe(_ translation: CGPoint, in view: MTKView) {
        guard canRotateGlobe else { return }
        interaction.drag(translation: [Float(translation.x),Float(translation.y)], diameter: Float(globeFrame(in: view).width))
        if view.isPaused { view.setNeedsDisplay() }
    }
    func endGlobeDrag(in view: MTKView) {
        interaction.end(animated: animate)
        if view.isPaused { view.setNeedsDisplay() }
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { if view.isPaused { view.setNeedsDisplay() } }
    func draw(in view: MTKView) {
        guard active, framesInFlight.wait(timeout:.now()) == .success else { return }
        guard view.drawableSize.width > 0, view.drawableSize.height > 0,
              let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { framesInFlight.signal(); return }
        command.addCompletedHandler { [framesInFlight] _ in framesInFlight.signal() }
        // Resolve through the current view transform each frame, including
        // scrolling beneath a stationary finger. UIKit contact is single-threaded.
        updateWallContact(in:view)
        let now = CACurrentMediaTime()
        if let lastFrame {
            let delta = min(0.1, max(0, now-lastFrame))
            if introduction != nil {
                if !holdIntroduction {
                    introduction?.advance(delta, destination: phase, reduced: !animate, skip: skipIntroduction)
                }
            } else if animate { motion.advance(delta) }
            wallTouch.advance(delta)
            interaction.advance(delta)
        }
        lastFrame = now
        let introPose = introduction?.pose
        let formation = introPose?.formation ?? motion.formation
        let journey = introPose?.journey ?? motion.journey
        let ambientTime = introduction.map { guideClock?.elapsed() ?? (introductionTime+$0.elapsed) } ?? motion.time
        let rotation = introduction.map { intro in
            guideClock != nil ? -0.4+ambientTime*0.055 : introductionRotation+(animate ? intro.elapsed*0.055 : 0)
        } ?? motion.rotation
        // Drawing can be requested during a SwiftUI update. Publish afterwards, on main.
        // Only the title observes this value; it does not rebuild the scene or home page.
        if progress.formation != formation || progress.journey != journey {
            DispatchQueue.main.async { [weak progress] in
                guard let progress else { return }
                progress.formation = formation
                progress.journey = journey
            }
        }
        let p = Float(journey)
        // A continuous rise with a gentle initial pullback; the wall remains foreground.
        var (eye, target) = HorizonGeometry.camera(journey: p)
        if let introPose {
            // Retire manual parallax smoothly before handing back the real home camera.
            let weight = Float(1-introPose.globeBlend)
            eye += HorizonGuideGeometry.parallax(introCamera?.offset() ?? .zero)*0.6*weight
        }
        let constrained = HorizonParticlePass.constrained
        let rate = constrained ? 30 : 60
        if view.preferredFramesPerSecond != rate { view.preferredFramesPerSecond = rate }
        let stride = constrained ? 2 : 1
        let aspect = Float(view.drawableSize.width/view.drawableSize.height)
        #if os(macOS)
        let regularGlobe = (view as? MacMetalSurface)?.framedHomeGlobe(scale: globeScale, aspect: aspect)
            ?? HorizonGeometry.globe(scale: globeScale, aspect: aspect)
        #else
        let regularGlobe = HorizonGeometry.globe(scale: globeScale, aspect: aspect)
        #endif
        let initialGlobe = HorizonGeometry.introductionGlobe(aspect: aspect)
        let blend = Float(introPose?.globeBlend ?? 1)
        var frame = HorizonRenderFrame(vp: HorizonGeometry.perspective(aspect: aspect) * HorizonGeometry.view(eye: eye,target: target),
            eye: SIMD4(eye,1), motion: [Float(ambientTime),p,Float(formation),Float(rotation)],
            viewport: [Float(view.contentScaleFactor),Float(stride),0,0],
            interaction: interaction.orientation.vector,
            globe: initialGlobe + (regularGlobe-initialGlobe)*blend,
            introduction: [Float(introPose?.wall ?? 1), Float(introPose?.particles ?? 1), brickScale, aspect])
        encoder.setVertexBytes(&frame,length: MemoryLayout<HorizonRenderFrame>.stride,index: 1)
        encoder.setCullMode(.none)
        encoder.setRenderPipelineState(wallPipeline); encoder.setDepthStencilState(wallDepth)
        encoder.setVertexBuffer(faces,offset: 0,index: 0)
        let touchBuffer = touchBuffers[touchBufferIndex]
        touchBufferIndex = (touchBufferIndex+1)%touchBuffers.count
        wallTouch.write(to:touchBuffer.contents().bindMemory(to:SIMD4<Float>.self,capacity:wallTouch.count),reduced:!animate)
        encoder.setVertexBuffer(touchBuffer,offset:0,index:2)
        // Face and antialiased outline share one fragment and one true depth.
        // No coplanar line pass or biased wall depth that could leak hidden edges.
        encoder.drawPrimitives(type: .triangle,vertexStart: 0,vertexCount: faceCount)
        if p > 0.005 { particles.encode(encoder,frame:frame,stride:stride) }
        encoder.endEncoding()
        if holdIntroduction, let id = introductionID, reportedPreparedID != id {
            reportedPreparedID = id
            HorizonFramePresentation.observe(drawable,command:command) { [weak progress] in
                DispatchQueue.main.async { progress?.preparedIntroduction = id }
            }
        }
        if introduction?.finished == true {
            if let id = introductionID {
                // UI (including the tab bar) is released only after the final
                // cinematic frame is presented, not while it is still queued.
                HorizonFramePresentation.observe(drawable,command:command) { [weak progress] in
                    DispatchQueue.main.async { progress?.completedIntroduction = id }
                }
            }
        }
        command.present(drawable); command.commit()
        if introduction?.finished == true {
            motion.finishIntroduction(phase: phase, rotation: rotation, elapsed: 0, startingTime: ambientTime)
            introduction = nil
        }
        if introduction == nil && (!animate || (phase == .idle && motion.journey == 0 && motion.formation == 0)) && !wallTouch.isActive {
            view.isPaused = true; view.enableSetNeedsDisplay = true; lastFrame = nil
        }
    }
}
