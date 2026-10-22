// Offline Mac Metal regression: production wall shader/geometry, synthetic historical line baseline.
// No VPN, device, or credentials. Run from the project root; output is ignored under .build.
import Foundation
import Metal
import simd

struct Frame {
    var vp: simd_float4x4
    var eye: SIMD4<Float>
    var motion: SIMD4<Float> = .zero
    var viewport: SIMD4<Float> = [3,1,0,0]
    var interaction: SIMD4<Float> = [0,0,0,1]
    var globe: SIMD4<Float> = .zero
    var introduction: SIMD4<Float> = [1,1,1,0]
    var scatter: SIMD4<Float> = [0,5.15,-7.1,1]
}
@main struct Compare {
 static func main() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let out = root.appendingPathComponent(".build/research/wall-flicker")
    try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { fatalError("Metal unavailable") }
    let width=600, height=1000
    func texture(_ format: MTLPixelFormat, samples: Int, shared: Bool = false) -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:format,width:width,height:height,mipmapped:false)
        d.textureType = samples > 1 ? .type2DMultisample : .type2D
        d.sampleCount=samples; d.storageMode=shared ? .shared : .private; d.usage=[.renderTarget]
        return device.makeTexture(descriptor:d)!
    }
    let color=texture(.bgra8Unorm,samples:4), depth=texture(.depth32Float,samples:4), resolved=texture(.bgra8Unorm,samples:1,shared:true)
    let ds=MTLDepthStencilDescriptor(); ds.depthCompareFunction = .lessEqual; ds.isDepthWriteEnabled=true
    let writeDepth=device.makeDepthStencilState(descriptor:ds)!
    ds.isDepthWriteEnabled=false; let readDepth=device.makeDepthStencilState(descriptor:ds)!
    func pipeline(_ source: String) throws -> MTLRenderPipelineState {
        let library=try device.makeLibrary(source:source,options:nil)
        let d=MTLRenderPipelineDescriptor(); d.vertexFunction=library.makeFunction(name:"horizon_wall")
        d.fragmentFunction=library.makeFunction(name:"horizon_wall_color"); d.colorAttachments[0].pixelFormat = .bgra8Unorm
        d.depthAttachmentPixelFormat = .depth32Float; d.rasterSampleCount=4
        return try device.makeRenderPipelineState(descriptor:d)
    }
    let old=try pipeline("""
        #include <metal_stdlib>
        using namespace metal;
        struct Frame { float4x4 vp; float4 eye,motion,viewport,interaction,globe; };
        struct WallOut { float4 position [[position]]; float shade; };
        vertex WallOut horizon_wall(uint id [[vertex_id]], const device float4 *v [[buffer(0)]], constant Frame &f [[buffer(1)]]) {
            WallOut o; o.position=f.vp*float4(v[id].xyz,1);
            o.shade=v[id].w*clamp(5.0/length(f.eye.xyz-v[id].xyz),0.16,1.0); return o;
        }
        fragment float4 horizon_wall_color(WallOut v [[stage_in]]) { return float4(float3(v.shade),1); }
        """)
    let new=try pipeline(String(contentsOf:root.appendingPathComponent("Horizon/Features/Horizon/Rendering/HorizonShaders.metal"),encoding:.utf8))
    func render(_ wall: HorizonGeometry.Wall, journey: Float, legacy: Bool, yOffset: Float=0) -> ([UInt8],Frame) {
        let camera=HorizonGeometry.camera(journey:journey)
        var f=Frame(vp:HorizonGeometry.perspective(aspect:Float(width)/Float(height))*HorizonGeometry.view(eye:camera.eye,target:camera.target),eye:SIMD4(camera.eye,1))
        // Controlled subpixel translation of identical geometry, in addition to actual camera sweeps.
        f.vp.columns.0.y += yOffset*f.vp.columns.0.w
        f.vp.columns.1.y += yOffset*f.vp.columns.1.w
        f.vp.columns.2.y += yOffset*f.vp.columns.2.w
        f.vp.columns.3.y += yOffset*f.vp.columns.3.w
        let faces=device.makeBuffer(bytes:wall.faces,length:wall.faces.count*16)!
        let edges=device.makeBuffer(bytes:wall.edges,length:wall.edges.count*16)!
        let pass=MTLRenderPassDescriptor(); pass.colorAttachments[0].texture=color; pass.colorAttachments[0].resolveTexture=resolved
        pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .multisampleResolve
        pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,1)
        pass.depthAttachment.texture=depth; pass.depthAttachment.loadAction = .clear; pass.depthAttachment.storeAction = .dontCare; pass.depthAttachment.clearDepth=1
        let command=queue.makeCommandBuffer()!, encoder=command.makeRenderCommandEncoder(descriptor:pass)!
        encoder.setRenderPipelineState(legacy ? old:new); encoder.setDepthStencilState(writeDepth)
        encoder.setVertexBytes(&f,length:MemoryLayout<Frame>.stride,index:1); encoder.setVertexBuffer(faces,offset:0,index:0)
        if legacy { encoder.setDepthBias(1,slopeScale:1,clamp:0.00001) }
        encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:wall.faces.count)
        if legacy {
            encoder.setDepthBias(0,slopeScale:0,clamp:0); encoder.setDepthStencilState(readDepth)
            encoder.setVertexBuffer(edges,offset:0,index:0); encoder.drawPrimitives(type:.line,vertexStart:0,vertexCount:wall.edges.count)
        }
        encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
        precondition(command.status == .completed,"GPU render failed")
        var bytes=[UInt8](repeating:0,count:width*height*4)
        resolved.getBytes(&bytes,bytesPerRow:width*4,from:MTLRegionMake2D(0,0,width,height),mipmapLevel:0)
        return (bytes,f)
    }
    func ppm(_ bytes:[UInt8],_ name:String) throws {
        var data=Data("P6\n\(width) \(height)\n255\n".utf8)
        for i in stride(from:0,to:bytes.count,by:4) { data.append(contentsOf:[bytes[i+2],bytes[i+1],bytes[i]]) }
        try data.write(to:out.appendingPathComponent(name+".ppm"))
    }
    func energy(_ bytes:[UInt8],frame:Frame,point:SIMD3<Float>, peak:Bool=false) -> Double? {
        let c=frame.vp*SIMD4(point,1)
        let x=Int((c.x/c.w+1)*Float(width)/2), y=Int((1-c.y/c.w)*Float(height)/2)
        guard x>=18,x<width-18,y>=7,y<height-7 else { return nil }
        var sum:Double=0
        // Integrated light across a tracked straight edge (not raw pixel differences from camera motion).
        for xx in (x-16)..<(x+16) {
            let samples=((y-5)...(y+5)).map { max(0,Double(bytes[($0*width+xx)*4])-2)/255 }
            sum += peak ? samples.max()! : samples.reduce(0,+)
        }
        return sum/32
    }
    var rows=["scale,journey,variant,edge_energy"]
    for scale:Float in [1,1.5,3] {
        let wall=HorizonGeometry.wall(scale:scale)
        precondition(wall.faces.count.isMultiple(of:6))
        for i in stride(from:0,to:wall.faces.count,by:6) {
            precondition(wall.faces[i]==wall.faces[i+3] && wall.faces[i+2]==wall.faces[i+4],
                         "wall shader requires quad triangles [0,1,2,0,2,3]")
        }
        let row=Int(ceil(18/scale))-1
        let point=SIMD3<Float>(row%2 == 0 ? 0:(1.22/3)*scale/2, min(3.06,Float(row+1)*0.17*scale)-0.004*scale,0.25)
        for legacy in [true,false] {
            var values:[Double]=[]
            for i in 0...120 {
                let p=Float(i)/120
                let (bytes,frame)=render(wall,journey:p,legacy:legacy)
                if let e=energy(bytes,frame:frame,point:point) { values.append(e); rows.append("\(scale),\(p),\(legacy ? "old":"new"),\(e)") }
                if scale == 1.5 && [0,36,60,84,120].contains(i) { try ppm(bytes,"\(legacy ? "old":"new")-\(i)") }
            }
            let jumps=zip(values,values.dropFirst()).map { abs($0-$1) }
            print("camera scale=\(scale) \(legacy ? "old":"new") samples=\(values.count) mean=\(values.reduce(0,+)/Double(values.count)) maxStep=\(jumps.max() ?? 0)")
        }
        // Constant view, one-pixel translation sampled in 1/32-pixel steps isolates raster phase.
        for legacy in [true,false] {
            var values:[Double]=[], peaks:[Double]=[]
            for i in 0...32 {
                let (bytes,frame)=render(wall,journey:0.6,legacy:legacy,yOffset:Float(i)/32*2/Float(height))
                if let e=energy(bytes,frame:frame,point:point), let peak=energy(bytes,frame:frame,point:point,peak:true) { values.append(e); peaks.append(peak) }
            }
            let peakRange=(peaks.max()!-peaks.min()!)/(peaks.reduce(0,+)/Double(peaks.count))
            print("peak relativeRange=\(peakRange)")
            if !legacy { precondition(peakRange < 0.4, "feathered edge regressed to strong subpixel peak flicker") }
            let avg=values.reduce(0,+)/Double(values.count)
            print("subpixel scale=\(scale) \(legacy ? "old":"new") relativeRange=\(((values.max() ?? 0)-(values.min() ?? 0))/avg)")
        }
    }
    // Inject a test quad entirely behind the central opaque brick surface.
    // It must not affect any color sample; draw it without the wall to verify visibility.
    let base=HorizonGeometry.wall(scale:1.5)
    let hidden:[SIMD4<Float>]=[[-0.2,1.35,-0.1,0.008],[0.2,1.35,-0.1,0.008],[0.2,1.45,-0.1,0.008],[-0.2,1.35,-0.1,0.008],[0.2,1.45,-0.1,0.008],[-0.2,1.45,-0.1,0.008]]
    var withHidden=base; withHidden.faces.append(contentsOf:hidden)
    var isolated=HorizonGeometry.Wall(); isolated.faces=base.faces.prefix(6).map { SIMD4<Float>($0.x+100,$0.y,$0.z,$0.w) }+hidden
    isolated.edges=[.zero,.zero] // legacy buffer is unused by the production pass
    for journey:Float in [0,0.5,1] {
        let a=render(base,journey:journey,legacy:false).0
        let b=render(withHidden,journey:journey,legacy:false).0
        precondition(a==b,"rear geometry leaked through the wall")
    }
    let testAlone=render(isolated,journey:0,legacy:false).0
    precondition(stride(from:0,to:testAlone.count,by:4).contains { testAlone[$0] > 20 },"occlusion probe must be visible without the wall")
    print("PASS: opaque wall hides rear geometry at start/mid/end, and filtered edge peak modulation stays below 40% in the controlled subpixel sweep")
    try rows.joined(separator:"\n").write(to:out.appendingPathComponent("edge-energy.csv"),atomically:true,encoding:.utf8)
 }
}
