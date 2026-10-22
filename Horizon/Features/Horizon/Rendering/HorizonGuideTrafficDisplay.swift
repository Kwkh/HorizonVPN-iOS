import SwiftUI
import simd

/// A tilted wireframe display. All values are deterministic demo traffic, never
/// tunnel counters; the labels and the rolling curves use the same signal.
enum HorizonGuideTrafficDisplay {
    static let width: CGFloat = 280
    static let height: CGFloat = 88

    static func draw(context: inout GraphicsContext,
                     project: (SIMD3<Float>) -> CGPoint?, time: Float) {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint? { project(worldPoint(x,y)) }
        func stroke(_ points: [CGPoint], opacity: Double, lineWidth: CGFloat = 0.8, closed: Bool = false) {
            guard let first = points.first else { return }
            var path = Path(); path.move(to:first)
            points.dropFirst().forEach { path.addLine(to:$0) }
            if closed { path.closeSubpath() }
            context.stroke(path,with:.color(.white.opacity(opacity)),lineWidth:lineWidth)
        }
        let corners = [(CGFloat(0),CGFloat(0)),(width,0),(width,height),(0,height)].compactMap { point($0.0,$0.1) }
        guard corners.count == 4 else { return }
        var face = Path(); face.addLines(corners); face.closeSubpath()
        context.fill(face,with:.color(.black.opacity(0.88)))
        stroke(corners,opacity:0.5,closed:true)
        stroke([point(196,9),point(196,height-9)].compactMap { $0 },opacity:0.22)
        stroke([point(12,44),point(184,44)].compactMap { $0 },opacity:0.08)
        stroke([point(204,44),point(width-9,44)].compactMap { $0 },opacity:0.14)
        for channel in 0..<2 {
            let alpha = channel == 0 ? 0.55 : 0.95
            let points = (0...100).compactMap { index -> CGPoint? in
                let fraction = Float(index)/100
                let value = rate(at:time-40+fraction*40,channel:channel)/2000
                return point(12+CGFloat(fraction)*172,height-9-CGFloat(value)*62)
            }
            stroke(points,opacity:alpha,lineWidth:channel == 0 ? 1 : 1.3)
        }
    }

    static func worldPoint(_ x: CGFloat, _ y: CGFloat) -> SIMD3<Float> {
        let orientation = simd_quatf(angle:-0.24,axis:[1,0,0])
            * simd_quatf(angle:0.10,axis:[0,1,0])
        return SIMD3<Float>(7,-1.53,0.2)
            + orientation.act([Float(x/width-0.5)*4.35,Float(0.5-y/height)*1.37,0])
    }

    static func rate(at time: Float, channel: Int) -> Float {
        let phase = time/7
        let index = floor(phase)
        let t = phase-index
        let smooth = t*t*t*(t*(t*6-15)+10)
        func value(_ step: Float) -> Float {
            let raw = sin(step*17.17+Float(channel)*43.71+12.3)*43758.5453
            let random = raw-floor(raw)
            return channel == 0 ? 60+random*600 : 320+random*1500
        }
        return value(index)+(value(index+1)-value(index))*smooth
    }
}
