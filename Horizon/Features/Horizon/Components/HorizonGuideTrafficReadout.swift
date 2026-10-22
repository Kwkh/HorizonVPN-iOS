import SwiftUI
import simd

/// Real SwiftUI Text keeps numeric glyph identity; Canvas text crossfades cannot.
struct HorizonGuideTrafficReadout: View {
    let project: (SIMD3<Float>) -> CGPoint?
    let time: Float

    var body: some View {
        ZStack(alignment:.topLeading) {
            ForEach(0..<2) { channel in
                let x: CGFloat = 202
                let y: CGFloat = channel == 0 ? 12 : 52
                if let origin = project(HorizonGuideTrafficDisplay.worldPoint(x,y)),
                   let right = project(HorizonGuideTrafficDisplay.worldPoint(x+1,y)),
                   let down = project(HorizonGuideTrafficDisplay.worldPoint(x,y+1)) {
                    let transform = CGAffineTransform(a:right.x-origin.x,b:right.y-origin.y,
                        c:down.x-origin.x,d:down.y-origin.y,tx:origin.x,ty:origin.y)
                    let tick = floor(time/3)*3
                    Rate(channel:channel,value:Int(HorizonGuideTrafficDisplay.rate(at:tick,channel:channel)))
                        .projectionEffect(ProjectionTransform(transform))
                }
            }
        }
        .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        .allowsHitTesting(false).accessibilityHidden(true)
    }

    private struct Rate: View {
        let channel: Int
        let value: Int
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            HStack(spacing:3) {
                Image(systemName:channel == 0 ? "arrow.up" : "arrow.down")
                Text(value,format:.number.grouping(.never))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .opacity : .numericText(value:Double(value)))
                    .frame(width:30,alignment:.trailing)
                    .animation(.easeInOut(duration:reduceMotion ? 0.2 : 1.15),value:value)
                Text("KB/s").font(.system(size:10.5,weight:.medium,design:.monospaced))
            }
            .font(.system(size:12,weight:.medium,design:.monospaced))
            .foregroundStyle(.white.opacity(channel == 0 ? 0.55 : 0.95))
            .frame(width:76,height:24,alignment:.leading)
        }
    }
}
