import simd

/// CPU layout shared by every Horizon Metal pass; matches Frame in HorizonShaders.metal.
struct HorizonRenderFrame {
    var vp: simd_float4x4
    var eye: SIMD4<Float>
    var motion: SIMD4<Float>
    var viewport: SIMD4<Float>
    var interaction: SIMD4<Float>
    var globe: SIMD4<Float>
    var introduction: SIMD4<Float>
    var scatter: SIMD4<Float> = [0,5.15,-7.1,1]

    static func guide(eye: SIMD3<Float>, target: SIMD3<Float>, globe: SIMD4<Float>,
                      aspect: Float, pixelScale: Float, time: Float, visibility: Float,
                      handoffProgress: Double = 0) -> Self {
        // Translate the guide's third chapter into the home's world coordinates.
        let shift = SIMD3<Float>(14,0,0)
        let cameraEye = eye-shift, cameraTarget = target-shift
        let sphere = globe-SIMD4<Float>(14,0,0,0)
        let intro = HorizonGeometry.introductionGlobe(aspect:aspect)
        let scale = sphere.w/intro.w
        let center = SIMD3(sphere.x,sphere.y,sphere.z)
        let cloudCenter = center + (SIMD3<Float>(0,5.15,-7.1)-SIMD3(intro.x,intro.y,intro.z))*scale
        // Brightness only: retain the original point size/coverage to avoid
        // fine subpixel patterns in the compact globe. Home uses zero (disabled).
        let t = min(1,max(0,handoffProgress))
        let blend = t*t*t*(t*(t*6-15)+10)
        let brightness = Float(0.8+0.2*min(1,max(0,blend)))
        return Self(vp:HorizonGeometry.perspective(aspect:aspect)*HorizonGeometry.view(eye:cameraEye,target:cameraTarget),
                    eye:SIMD4(cameraEye,1),motion:[time,1,1,-0.4+time*0.055],
                    viewport:[pixelScale,1,brightness,0],interaction:[0,0,0,1],globe:sphere,
                    introduction:[0,visibility,1,aspect],scatter:SIMD4(cloudCenter,scale))
    }
}
