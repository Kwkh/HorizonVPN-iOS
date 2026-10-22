import SwiftUI
import simd

/// The original fine-line node diagram, projected into the guide's shared world.
enum HorizonGuideNodeTree {
    static func draw(context: inout GraphicsContext,
                     project: (SIMD3<Float>) -> CGPoint?, eye: SIMD3<Float>,
                     cameraRight: SIMD3<Float>, time: Float, moving: Bool) {
        func line(_ points: [SIMD3<Float>], alpha: Double, width: CGFloat = 1) {
            let projected = points.compactMap(project)
            guard projected.count == points.count, let first = projected.first else { return }
            var path = Path(); path.move(to:first)
            for point in projected.dropFirst() { path.addLine(to:point) }
            context.stroke(path,with:.color(.white.opacity(alpha)),lineWidth:width)
        }
        let selectionInterval: Float = 6.5 * 2 / 3
        let selectionTime = moving ? time/selectionInterval : 1.3
        let selected = Int(selectionTime)%3
        let rawFade = min(1,(selectionTime-floor(selectionTime))*selectionInterval/1.2)
        let fade = rawFade*rawFade*(3-2*rawFade)
        func emphasis(_ index: Int) -> Double {
            Double(index == selected ? fade : index == (selected+2)%3 ? 1-fade : 0)
        }
        let nodes = HorizonGuideGeometry.nodes
        // Draw all spokes behind the opaque circular labels. Paint far labels
        // first so a camera drag never draws a rear label over a nearer one.
        for (index,node) in nodes.enumerated() {
            line([node,HorizonGuideGeometry.hub],alpha:0.24+0.66*emphasis(index))
        }
        let order = nodes.indices.sorted { simd_distance_squared(nodes[$0],eye) > simd_distance_squared(nodes[$1],eye) }
        for index in order {
            let node = nodes[index]
            if let point = project(node), let edge = project(node+cameraRight*0.24) {
                // Camera-facing circles retain readable numbers while their
                // projected size supplies the same perspective as the branches.
                let radius = min(18,max(11,hypot(edge.x-point.x,edge.y-point.y)))
                let rect = CGRect(x:point.x-radius,y:point.y-radius,width:radius*2,height:radius*2)
                context.fill(Path(ellipseIn:rect),with:.color(.black))
                context.stroke(Path(ellipseIn:rect),with:.color(.white.opacity(0.4+0.6*emphasis(index))),lineWidth:1)
                context.draw(Text(String(format:"%02d",index+1)).font(.system(size:max(9,radius*10/14),weight:.medium,design:.monospaced)).foregroundStyle(.white),at:point)
            }
        }
        HorizonGuideTrafficDisplay.draw(context:&context,project:project,time:time)
    }
}
