import MetalKit
import simd

/// One point set, shader, blending policy and quality policy for guide and home.
final class HorizonParticlePass {
    static let points: [SIMD4<Float>] = loadPoints(bundle:.main)
    static func loadPoints(bundle: Bundle) -> [SIMD4<Float>] {
        guard let url = bundle.url(forResource:"earth-land",withExtension:"bin"),
              let data = try? Data(contentsOf:url), !data.isEmpty, data.count % 16 == 0 else { return [] }
        var dots = data.withUnsafeBytes { bytes in
            stride(from:0,to:bytes.count,by:16).map { bytes.loadUnaligned(fromByteOffset:$0,as:SIMD4<Float>.self) }
        }
        for i in 0..<2400 {
            let y = 1-2*(Float(i)+0.5)/2400
            let angle = Float(i)*2.3999632, r = sqrt(1-y*y)
            dots.append([r*sin(angle),y,r*cos(angle),i % 2 == 0 ? 0.11 : -1])
        }
        return dots
    }
    static var constrained: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled || ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
    }
    private let pipeline: MTLRenderPipelineState
    private let depth: MTLDepthStencilState
    private let buffer: MTLBuffer
    private let count: Int

    init?(device: MTLDevice, library: MTLLibrary, format: MTLPixelFormat, samples: Int,
          points: [SIMD4<Float>] = HorizonParticlePass.points) {
        guard !points.isEmpty, let buffer = device.makeBuffer(bytes:points,length:points.count*16) else { return nil }
        self.buffer = buffer
        count = points.count
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name:"horizon_particle")
        descriptor.fragmentFunction = library.makeFunction(name:"horizon_particle_color")
        descriptor.colorAttachments[0].pixelFormat = format
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.rasterSampleCount = samples
        let color = descriptor.colorAttachments[0]!
        color.isBlendingEnabled = true
        color.sourceRGBBlendFactor = .sourceAlpha
        color.destinationRGBBlendFactor = .one
        color.sourceAlphaBlendFactor = .one
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let pipeline = try? device.makeRenderPipelineState(descriptor:descriptor) else { return nil }
        self.pipeline = pipeline
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .lessEqual
        depthDescriptor.isDepthWriteEnabled = false
        guard let depth = device.makeDepthStencilState(descriptor:depthDescriptor) else { return nil }
        self.depth = depth
    }

    func encode(_ encoder: MTLRenderCommandEncoder, frame: HorizonRenderFrame, stride: Int) {
        var frame = frame
        frame.viewport.y = Float(stride)
        encoder.setVertexBytes(&frame,length:MemoryLayout<HorizonRenderFrame>.stride,index:1)
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depth)
        encoder.setVertexBuffer(buffer,offset:0,index:0)
        encoder.drawPrimitives(type:.point,vertexStart:0,vertexCount:count/stride)
    }
}
