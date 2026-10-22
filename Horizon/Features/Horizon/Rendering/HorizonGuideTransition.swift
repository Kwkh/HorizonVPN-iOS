import Foundation
import CoreGraphics
import simd

/// All spatial inputs for one actually presented guide frame.
struct HorizonGuidePresentation {
    var eye: SIMD3<Float>
    var target: SIMD3<Float>
    var globe: SIMD4<Float>
    var viewport: CGRect
    var time: Float
    var visibility: Float
    var progress: Double = 0
    var transitionID: UUID?
}

/// A single clock drives the viewport and scene, never a UIKit view-size animation.
struct HorizonGuideTransition {
    static let duration = 1.6
    let id = UUID()
    var source: HorizonGuidePresentation
    var destination: CGRect

    func sample(elapsed: Double) -> HorizonGuidePresentation {
        let raw = min(1,max(0,elapsed/Self.duration))
        let t = raw*raw*raw*(raw*(raw*6-15)+10)
        var result = sample(progress:t)
        result.time = source.time+Float(max(0,elapsed))
        return result
    }

    /// Finger progress is already spatial progress; do not ease it a second time.
    func sample(progress: Double) -> HorizonGuidePresentation {
        let t = min(1,max(0,progress))
        let viewport = CGRect(x:source.viewport.minX+(destination.minX-source.viewport.minX)*t,
                              y:source.viewport.minY+(destination.minY-source.viewport.minY)*t,
                              width:source.viewport.width+(destination.width-source.viewport.width)*t,
                              height:source.viewport.height+(destination.height-source.viewport.height)*t)
        let aspect = Float(viewport.width/max(1,viewport.height))
        let camera = HorizonGeometry.camera(journey:1)
        let offset = SIMD3<Float>(14,0,0)
        let globe = HorizonGeometry.introductionGlobe(aspect:aspect)+SIMD4<Float>(14,0,0,0)
        return HorizonGuidePresentation(eye:source.eye+(camera.eye+offset-source.eye)*Float(t),
            target:source.target+(camera.target+offset-source.target)*Float(t),
            globe:source.globe+(globe-source.globe)*Float(t), viewport:viewport,time:source.time,
            visibility:source.visibility+(1-source.visibility)*Float(t),progress:t,transitionID:id)
    }

    /// Map a local perspective viewport into a fixed full-page drawable.
    static func embed(_ viewport: CGRect, in canvas: CGSize) -> simd_float4x4 {
        let width = max(1,canvas.width), height = max(1,canvas.height)
        var matrix = matrix_identity_float4x4
        matrix.columns.0.x = Float(viewport.width/width)
        matrix.columns.1.y = Float(viewport.height/height)
        matrix.columns.3.x = Float(2*viewport.midX/width-1)
        matrix.columns.3.y = Float(1-2*viewport.midY/height)
        return matrix
    }
}
