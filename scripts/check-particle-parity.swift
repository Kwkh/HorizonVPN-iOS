// Compare production GPU particle output, without running an app or network operation.
import Foundation
import MetalKit
import simd

@main struct ParticleParity {
    static func main() throws {
        let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let out = root.appendingPathComponent(".build/particle-parity")
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let bundleURL = out.appendingPathComponent("Test.bundle")
        try FileManager.default.createDirectory(at:bundleURL,withIntermediateDirectories:true)
        let data = try Data(contentsOf:root.appendingPathComponent("Horizon/Features/Horizon/Resources/earth-land.bin"))
        try data.write(to:bundleURL.appendingPathComponent("earth-land.bin"))
        let points = HorizonParticlePass.loadPoints(bundle:Bundle(url:bundleURL)!)
        precondition(points.count == data.count/16+2400, "full land data plus shared ocean/atmosphere")
        precondition(points.filter { $0.w < 0 }.count == 1200)
        precondition(MemoryLayout<HorizonRenderFrame>.stride == 176, "Metal uniform layout")
        let source = try String(contentsOf:root.appendingPathComponent("Horizon/Features/Horizon/Rendering/HorizonShaders.metal"),encoding:.utf8)
        // Pin the actual pre-introduction snapshot; do not reconstruct a baseline
        // from today's shader, which could hide a shared appearance regression.
        func baseline(_ path: String) throws -> Data {
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(fileURLWithPath:"/usr/bin/git")
            process.arguments = ["show","ce20c95:"+path]
            process.standardOutput = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            precondition(process.terminationStatus == 0,"pre-introduction snapshot must be available")
            return data
        }
        let oldLand = try baseline("Clash/Features/Horizon/Resources/earth-land.bin")
        precondition(data == oldLand,
                     "land density must match pre-introduction data")
        let oldSource = String(data:try baseline("Clash/Features/Horizon/Rendering/HorizonShaders.metal"),encoding:.utf8)!
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { fatalError("Metal unavailable") }
        let library = try device.makeLibrary(source:source,options:nil)
        let oldLibrary = try device.makeLibrary(source:oldSource,options:nil)
        let renderer = HorizonParticlePass(device:device,library:library,format:.bgra8Unorm,samples:4,points:points)!
        let oldRenderer = HorizonParticlePass(device:device,library:oldLibrary,format:.bgra8Unorm,samples:4,points:points)!
        let width=390, height=640
        func texture(_ format: MTLPixelFormat, samples: Int, shared: Bool = false) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:format,width:width,height:height,mipmapped:false)
            d.textureType = samples > 1 ? .type2DMultisample : .type2D
            d.sampleCount = samples; d.storageMode = shared ? .shared : .private; d.usage = [.renderTarget]
            return device.makeTexture(descriptor:d)!
        }
        let color=texture(.bgra8Unorm,samples:4), depth=texture(.depth32Float,samples:4)
        let resolved=texture(.bgra8Unorm,samples:1,shared:true)
        func render(_ frame: HorizonRenderFrame, using renderer: HorizonParticlePass, transparent: Bool = false, stride: Int) -> [UInt8] {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture=color; pass.colorAttachments[0].resolveTexture=resolved
            pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .multisampleResolve
            pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,transparent ? 0 : 1)
            pass.depthAttachment.texture=depth; pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.storeAction = .dontCare; pass.depthAttachment.clearDepth=1
            let command=queue.makeCommandBuffer()!, encoder=command.makeRenderCommandEncoder(descriptor:pass)!
            renderer.encode(encoder,frame:frame,stride:stride)
            encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
            precondition(command.status == .completed)
            var bytes=[UInt8](repeating:0,count:width*height*4)
            resolved.getBytes(&bytes,bytesPerRow:width*4,from:MTLRegionMake2D(0,0,width,height),mipmapLevel:0)
            return bytes
        }
        func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
            zip(a,b).enumerated().reduce(0.0) { sum,pair in
                sum+(pair.offset % 4 == 3 ? 0 : abs(Double(pair.element.0)-Double(pair.element.1)))
            }/Double(width*height*3)
        }
        func save(_ bytes: [UInt8], name: String) throws {
            var ppm=Data("P6\n\(width) \(height)\n255\n".utf8)
            for i in stride(from:0,to:bytes.count,by:4) { ppm.append(contentsOf:[bytes[i+2],bytes[i+1],bytes[i]]) }
            try ppm.write(to:out.appendingPathComponent(name+".ppm"))
        }
        let aspect=Float(width)/Float(height)
        let smallPose = HorizonGuideGeometry.bridge(focus:2,entry:1,tilt:.zero,progress:0,aspect:aspect)
        let small = HorizonRenderFrame.guide(eye:smallPose.eye,target:smallPose.target,globe:smallPose.globe,
            aspect:aspect,pixelScale:3,time:13,visibility:1)
        let globePoints = points.filter { $0.w >= 0 }
        let guideGlobe = HorizonParticlePass(device:device,library:library,format:.bgra8Unorm,samples:4,points:globePoints)!
        let oldGlobe = HorizonParticlePass(device:device,library:oldLibrary,format:.bgra8Unorm,samples:4,points:globePoints)!
        let ambient = HorizonParticlePass(device:device,library:library,format:.bgra8Unorm,samples:4,
                                         points:points.filter { $0.w < 0 })!
        func energy(_ pixels: [UInt8]) -> Double {
            pixels.enumerated().reduce(0) { $0+($1.offset % 4 == 0 ? Double($1.element) : 0) }
        }
        var fullBrightness = small
        fullBrightness.viewport.z = 0
        for stride in [1,2] {
            let dimmed = render(small,using:guideGlobe,transparent:true,stride:stride)
            let original = render(small,using:oldGlobe,transparent:true,stride:stride)
            precondition(energy(dimmed)<energy(original) && energy(dimmed)>energy(original)*0.75,
                         "intro globe only dims modestly without reducing point size")
            precondition(difference(render(small,using:ambient,stride:stride),
                                    render(fullBrightness,using:ambient,stride:stride)) == 0,
                         "guide brightness does not affect floating particles")
            if stride==1 { try save(dimmed,name:"guide-dimmed"); try save(original,name:"guide-bright") }
        }
        var previous: Float = 0.8
        for index in 0...1000 {
            let frame = HorizonRenderFrame.guide(eye:smallPose.eye,target:smallPose.target,globe:smallPose.globe,
                aspect:aspect,pixelScale:3,time:13,visibility:1,handoffProgress:Double(index)/1000)
            precondition(frame.viewport.z>=previous && frame.viewport.z-previous<0.001)
            if index==1000 { precondition(frame.viewport.z==1 && frame.viewport.z-previous<0.000001) }
            previous = frame.viewport.z
        }
        for stride in [1,2] {
            for time: Float in [0,13,50] {
                let pose = HorizonGuideGeometry.bridge(focus:2,entry:1,tilt:[0.6,-0.3],progress:1,aspect:aspect)
                let guide = HorizonRenderFrame.guide(eye:pose.eye,target:pose.target,globe:pose.globe,
                    aspect:aspect,pixelScale:3,time:time,visibility:1,handoffProgress:1)
                let camera = HorizonGeometry.camera(journey:1)
                var home = HorizonRenderFrame(vp:HorizonGeometry.perspective(aspect:aspect)*HorizonGeometry.view(eye:camera.eye,target:camera.target),
                    eye:SIMD4(camera.eye,1),motion:[time,1,1,-0.4+time*0.055],viewport:[3,1,0,0],interaction:[0,0,0,1],
                    globe:HorizonGeometry.introductionGlobe(aspect:aspect),introduction:[0,1,1,aspect])
                let actual=render(guide,using:renderer,transparent:true,stride:stride)
                let expected=render(home,using:renderer,stride:stride)
                let error=difference(actual,expected)
                precondition(expected.contains { $0 > 0 && $0 < 255 }, "nonempty particle image")
                precondition(error < 0.01, "guide/home image mismatch: \(error)")
                for formation: Float in [0,0.5,1] {
                    home.motion.z=formation
                    precondition(difference(render(home,using:renderer,stride:stride),render(home,using:oldRenderer,stride:stride)) < 0.001,
                                 "home shader appearance must not change")
                }
                for scale: Float in [1,2] {
                    home.globe = HorizonGeometry.globe(scale:scale,aspect:aspect)
                    for formation: Float in [0,0.5,1] {
                        home.motion.z = formation
                        precondition(difference(render(home,using:renderer,stride:stride),
                                                render(home,using:oldRenderer,stride:stride)) < 0.001,
                                     "regular home globe must match pre-introduction shader")
                    }
                }
                print("PASS: stride=\(stride), time=\(time), guide/home mean RGB error=\(error)")
                if stride == 1 && time == 13 {
                    try save(actual,name:"guide-handoff"); try save(expected,name:"home-introduction")
                }
            }
        }
        print("PASS: complete point set, shared blending, transparent composition, full/reduced detail, guide-only dimming with continuous handoff, unchanged home appearance")
    }
}
