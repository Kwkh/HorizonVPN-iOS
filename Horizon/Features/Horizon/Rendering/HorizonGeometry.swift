import Foundation
import simd

/// Right-handed scene: wall at z=0, world beyond it at negative z.
enum HorizonGeometry {
    static let wallHalfDepth: Float = 0.25
    static let introductionGlobeScale: Float = 1.3
    /// A full, centered globe for the introduction, irrespective of the user's zoom.
    static func introductionGlobe(aspect: Float) -> SIMD4<Float> {
        let camera = camera(journey: 1)
        let z: Float = -7.1
        let y = camera.eye.y + (z-camera.eye.z) * (camera.target.y-camera.eye.y) / (camera.target.z-camera.eye.z)
        let center = SIMD3<Float>(0, y, z)
        let depth = simd_length(center-camera.eye)
        let projection = perspective(aspect: aspect)
        let horizontal = 0.96 * depth / sqrt(projection.columns.0.x * projection.columns.0.x + 0.96 * 0.96)
        let vertical = 0.88 * depth / sqrt(projection.columns.1.y * projection.columns.1.y + 0.88 * 0.88)
        return SIMD4(center, min(2.32 * introductionGlobeScale, min(horizontal, vertical)))
    }
    /// xyz is the shared world-space center; w is the sphere radius.
    static func globe(scale: Float, aspect: Float = 0.58) -> SIMD4<Float> {
        let scale = min(2, max(1, scale))
        let radius: Float = 2.32*scale
        var center = SIMD3<Float>(0, 5.15-(scale-1)*0.9, -7.1)
        let camera = camera(journey: 1)
        let forward = simd_normalize(camera.target-camera.eye)
        let depth = simd_dot(center-camera.eye,forward)
        let focalX = perspective(aspect: aspect).columns.0.x
        // Keep the camera fixed. Once the projected sphere exceeds the viewport,
        // sink it progressively behind the foreground wall instead of fitting it on screen.
        let projectedHalfWidth = radius*focalX/sqrt(max(0.01,depth*depth-radius*radius))
        let overflow = max(0,projectedHalfWidth-1)
        center.y -= min(1.5,2.8*overflow*overflow/(overflow+0.2))
        // The final half of the size range settles toward a hemisphere framing.
        // With the fixed camera, y=1.2 aligns the 2x sphere's projected silhouette
        // midpoint with the wall crest (including perspective, not only its world center).
        let t = min(1,max(0,(scale-1.5)/0.5))
        let settle = t*t*(3-2*t)
        center.y += (1.2-center.y)*settle
        return SIMD4(center,radius)
    }
    /// Perspective silhouette used to keep the title above the visible globe.
    static func globeProjection(scale: Float, aspect: Float) -> (halfWidth: Float, top: Float) {
        let sphere = globe(scale: scale, aspect: aspect)
        let camera = camera(journey: 1)
        let position = view(eye: camera.eye, target: camera.target) * SIMD4<Float>(sphere.x,sphere.y,sphere.z,1)
        let depth = -position.z
        let denominator = max(0.01,depth*depth-sphere.w*sphere.w)
        let projection = perspective(aspect: aspect)
        let halfWidth = sphere.w*projection.columns.0.x/sqrt(denominator)
        let topSlope = (position.y*depth+sphere.w*sqrt(max(0,denominator+position.y*position.y)))/denominator
        return (halfWidth,topSlope*projection.columns.1.y)
    }
    static func hitsGlobe(ndc: SIMD2<Float>, aspect: Float, journey: Float, scale: Float) -> Bool {
        let camera = camera(journey: journey)
        let inverse = simd_inverse(perspective(aspect: aspect) * view(eye: camera.eye, target: camera.target))
        let far = inverse * SIMD4<Float>(ndc.x, ndc.y, 1, 1)
        let direction = simd_normalize(SIMD3<Float>(far.x,far.y,far.z)/far.w-camera.eye)
        let sphere = globe(scale: scale, aspect: aspect)
        let center = SIMD3<Float>(sphere.x,sphere.y,sphere.z)
        let offset = camera.eye-center
        let b = simd_dot(offset,direction)
        let discriminant = b*b - simd_dot(offset,offset) + sphere.w*sphere.w
        guard discriminant >= 0 else { return false }
        let distance = -b-sqrt(discriminant)
        guard distance > 0 else { return false }
        // The larger sphere can sink behind the wall; its hidden part must remain scrollable.
        let a = (SIMD3<Float>(-12,0,-wallHalfDepth)-camera.eye)/direction
        let z = (SIMD3<Float>(12,3.06,wallHalfDepth)-camera.eye)/direction
        let near = simd_min(a,z), farWall = simd_max(a,z)
        let entry = max(near.x,max(near.y,near.z)), exit = min(farWall.x,min(farWall.y,farWall.z))
        let wallOccludes = max(entry,0) <= exit && entry < distance
        return !wallOccludes
    }
    struct Wall { var faces: [SIMD4<Float>] = []; var edges: [SIMD4<Float>] = [] }
    static func wall(scale: Float = 1) -> Wall {
        var result = Wall()
        // Scale only the brick grid; keep the silhouette, depth and camera fixed.
        let scale = min(3, max(1, scale))
        let pitch: Float = (1.22 / 3)*scale
        let rowHeight: Float = 0.17*scale
        let columns = Int((28/scale).rounded())
        // Solid mortar behind the brick joints also occludes the submerged globe.
        let left = -(Float(columns)+0.5)*pitch, right = (Float(columns)+1)*pitch
        let backing: [SIMD3<Float>] = [[left,0,0],[right,0,0],[right,3.06,0],[left,3.06,0]]
        for i in [0,1,2,0,2,3] { result.faces.append(SIMD4(backing[i],0.008)) }
        for row in 0..<Int(ceil(18/scale)) {
            for column in -columns...columns {
                let x = Float(column)*pitch + (row % 2 == 0 ? 0 : pitch/2)
                let y = Float(row)*rowHeight
                let a = SIMD3<Float>(x-0.198*scale, y+0.004*scale, -wallHalfDepth)
                let b = SIMD3<Float>(x+0.198*scale, min(3.06, y+rowHeight)-0.004*scale, wallHalfDepth)
                guard b.y > a.y else { continue }
                let p: [SIMD3<Float>] = [
                    [a.x,a.y,a.z],[b.x,a.y,a.z],[b.x,b.y,a.z],[a.x,b.y,a.z],
                    [a.x,a.y,b.z],[b.x,a.y,b.z],[b.x,b.y,b.z],[a.x,b.y,b.z]]
                for f in [[0,1,2,3],[4,7,6,5],[0,4,5,1],[3,2,6,7],[0,3,7,4],[1,5,6,2]] {
                    for i in [0,1,2,0,2,3] { result.faces.append(SIMD4(p[f[i]], 0.008)) }
                }
                for e in [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]] {
                    result.edges.append(SIMD4(p[e[0]], 0.78)); result.edges.append(SIMD4(p[e[1]], 0.78))
                }
            }
        }
        return result
    }
    static func camera(journey p: Float) -> (eye: SIMD3<Float>, target: SIMD3<Float>) {
        (SIMD3<Float>(0, 1.65+2.8*p, 4.6-0.1*p+1.3*sin(p*Float.pi)),
         SIMD3<Float>(0,1.65+2.45*p,-6.8*p))
    }
    static func view(eye: SIMD3<Float>, target: SIMD3<Float>) -> simd_float4x4 {
        let z = simd_normalize(eye-target), x = simd_normalize(simd_cross(SIMD3<Float>(0,1,0),z))
        let y = simd_cross(z,x)
        return simd_float4x4(columns: (
            [x.x,y.x,z.x,0],[x.y,y.y,z.y,0],[x.z,y.z,z.z,0],
            [-simd_dot(x,eye),-simd_dot(y,eye),-simd_dot(z,eye),1]))
    }
    static func perspective(aspect: Float) -> simd_float4x4 {
        let y: Float = 1 / tan(55 * .pi / 360), z: Float = 100 / (0.1-100)
        return simd_float4x4(columns: ([y/max(0.1,aspect),0,0,0],[0,y,0,0],[0,0,z,-1],[0,0,z*0.1,0]))
    }
}
