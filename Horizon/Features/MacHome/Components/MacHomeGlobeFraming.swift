#if os(macOS)
import Foundation
import simd

/// Mac Home presentation only; leaves the shared camera, wall and size setting intact.
enum MacHomeGlobeFraming {
    static func globe(scale: Float, aspect: Float, height: Float, buttonTop: Float?) -> SIMD4<Float> {
        let original = HorizonGeometry.globe(scale: scale, aspect: aspect)
        guard height > 0 else { return original }
        let camera = HorizonGeometry.camera(journey: 1)
        let forward = simd_normalize(camera.target - camera.eye)
        let right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
        let up = simd_cross(right, forward)
        let depth = simd_dot(SIMD3(original.x, original.y, original.z) - camera.eye, forward)
        let radius = original.w * 1.22
        // The title ends 18 pt above the surface. The button's real top edge is
        // the lower boundary, with a fallback until its initial layout completes.
        let bottom = min(height, max(0, buttonTop ?? (height - 68)))
        let midpoint = (bottom - 18) * 0.5
        let ndcY = 1 - 2 * midpoint / height
        let focalY = HorizonGeometry.perspective(aspect: aspect).columns.1.y
        // Center the projected silhouette, including perspective enlargement;
        // projecting only the world-space center drifts as the radius increases.
        let cameraY = ndcY * (depth * depth - radius * radius) / (focalY * depth)
        return SIMD4(camera.eye + forward * depth + up * cameraY, radius)
    }

    static func hitsGlobe(ndc: SIMD2<Float>, aspect: Float, journey: Float, sphere: SIMD4<Float>) -> Bool {
        let camera = HorizonGeometry.camera(journey: journey)
        let inverse = simd_inverse(HorizonGeometry.perspective(aspect: aspect) *
            HorizonGeometry.view(eye: camera.eye, target: camera.target))
        let far = inverse * SIMD4<Float>(ndc.x, ndc.y, 1, 1)
        let direction = simd_normalize(SIMD3<Float>(far.x, far.y, far.z) / far.w - camera.eye)
        let offset = camera.eye - SIMD3<Float>(sphere.x, sphere.y, sphere.z)
        let b = simd_dot(offset, direction)
        let discriminant = b * b - simd_dot(offset, offset) + sphere.w * sphere.w
        guard discriminant >= 0 else { return false }
        let distance = -b - sqrt(discriminant)
        guard distance > 0 else { return false }
        let a = (SIMD3<Float>(-12, 0, -HorizonGeometry.wallHalfDepth) - camera.eye) / direction
        let z = (SIMD3<Float>(12, 3.06, HorizonGeometry.wallHalfDepth) - camera.eye) / direction
        let near = simd_min(a, z), farWall = simd_max(a, z)
        let entry = max(near.x, max(near.y, near.z)), exit = min(farWall.x, min(farWall.y, farWall.z))
        return !(max(entry, 0) <= exit && entry < distance)
    }
}
#endif
