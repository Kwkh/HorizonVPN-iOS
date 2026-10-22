import MetalKit

/// Wall holds and assembled-globe drags share this surface. Ordinary drags
/// still belong to the ancestor ScrollView.
final class HorizonMetalView: MTKView {
    weak var interactionRenderer: HorizonRenderer?
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        interactionRenderer?.containsGlobe(point, in: self) == true
            || interactionRenderer?.containsWall(point, in:self) == true
    }
}
