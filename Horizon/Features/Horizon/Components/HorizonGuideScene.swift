import SwiftUI
import simd

/// Canvas guide objects around the shared Metal globe. Only this subtree redraws.
struct HorizonGuideScene: View, Animatable {
    var focus: Double
    var entry: Double
    let interactive: Bool
    let bridging: Bool
    let sourceViewport: CGRect
    let bridgePresented: (HorizonGuidePresentation) -> Void
    let playback: HorizonGuidePlayback
    let camera: HorizonIntroCamera
    let destinationHeight: CGFloat
    let active: Bool
    let moving: Bool
    var minimumFrameInterval: Double = 1.0/30
    var fullWidthMask = false
    @Environment(\.displayScale) private var displayScale
    @State private var deviceMotion = GuideDeviceMotion()
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(focus, entry) }
        set { focus = newValue.first; entry = newValue.second }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: bridging ? 1.0/60 : minimumFrameInterval, paused: !active || (!moving && !bridging))) { timeline in
            // Sample directly from this frame's date. A nested GeometryReader can
            // reevaluate its stored layout closure on a gesture observation update.
            let tilt = deviceMotion.offset + camera.offset(at:timeline.date)*0.6
            let source = HorizonGuideGeometry.bridge(focus:focus,entry:entry,tilt:tilt,
                progress:0,aspect:Float(sourceViewport.width/max(1,sourceViewport.height)))
            let normal = HorizonGuidePresentation(eye:source.eye,target:source.target,globe:source.globe,
                viewport:sourceViewport,time:playback.elapsed(at:timeline.date),visibility:Float(min(1,max(0,focus-1))))
            let sample = (interactive ? playback.interactiveFrame(at:timeline.date)
                          : playback.transitionFrame(at:timeline.date)) ?? normal
            let viewport = sample.viewport
            let handoff = sample.progress
            #if os(macOS)
            let tablet = true
            #else
            let tablet = UIDevice.current.userInterfaceIdiom == .pad
            #endif
            let cardsVisibility = HorizonGuideFraming.visibility(chapter: 0, focus: focus, tablet: tablet)
            let nodesVisibility = HorizonGuideFraming.visibility(chapter: 1, focus: focus, tablet: tablet)
            let wallVisibility = HorizonGuideFraming.visibility(chapter: 2, focus: focus, tablet: tablet)
            let chapterVisibility = HorizonGuidePullState.spatialProgress(focus+1)
            let time = sample.time
            let aspect = Float(viewport.width/max(1,viewport.height))
            let view = HorizonGeometry.view(eye:sample.eye,target:sample.target)
            let vp = HorizonGeometry.perspective(aspect:aspect) * view
            let project: (SIMD3<Float>) -> CGPoint? = { point in
                let clip = vp * SIMD4(point,1)
                guard clip.w > 0.15 else { return nil }
                return CGPoint(x:viewport.minX+CGFloat(clip.x/clip.w+1)*viewport.width/2,
                               y:viewport.minY+CGFloat(1-clip.y/clip.w)*viewport.height/2)
            }
            ZStack {
                Canvas { context, _ in
                    // Welcome stays black; reveal the same particle field only
                    // as its continuous camera move enters the first chapter.
                    context.opacity = chapterVisibility
                    for (index, original) in HorizonGuideGeometry.particles.enumerated() {
                        let point = HorizonGuideGeometry.particle(original,index:index,time:time)
                        guard let p = project(point) else { continue }
                        let radius: CGFloat = index % 5 == 0 ? 1 : 0.55
                        context.fill(Path(ellipseIn: CGRect(x:p.x-radius,y:p.y-radius,width:radius*2,height:radius*2)),
                                     with: .color(.white.opacity((index % 5 == 0 ? 0.52 : 0.26)*(1-handoff))))
                    }
                }
                HorizonGuideGlobeView(frame: .guide(eye:sample.eye,target:sample.target,globe:sample.globe,
                    aspect:aspect,pixelScale:Float(displayScale),time:time,visibility:sample.visibility,handoffProgress:sample.progress),
                    presentation:sample, playback:playback, bridgePresented:bridgePresented)
                Canvas { context, _ in
                    context.opacity = (1-handoff)*chapterVisibility
                    func stroke(_ points: [SIMD3<Float>], opacity: Double, width: CGFloat = 1) {
                        let projected = points.compactMap(project)
                        guard projected.count == points.count, let first = projected.first else { return }
                        var path = Path(); path.move(to: first)
                        for point in projected.dropFirst() { path.addLine(to: point) }
                        context.stroke(path, with: .color(.white.opacity(opacity)), lineWidth: width)
                    }
                    // Painter's order is sufficient for the disjoint convex display objects.
                    let faces = HorizonGuideGeometry.faces.sorted {
                        func depth(_ face: HorizonGuideGeometry.Face) -> Float {
                            let center = face.points.reduce(SIMD3<Float>.zero,+)/4
                            return (view * SIMD4(center,1)).z
                        }
                        return depth($0) < depth($1)
                    }
                    for face in faces {
                        let points = face.points.compactMap(project)
                        guard points.count == 4 else { continue }
                        var path = Path(); path.addLines(points); path.closeSubpath()
                        var faceContext = context
                        faceContext.opacity *= face.chapter == 2 ? wallVisibility : cardsVisibility
                        faceContext.fill(path, with: .color(.black))
                        faceContext.stroke(path, with: .color(.white.opacity(0.62)), lineWidth: 0.8)
                    }
                    let symbols = ["doc.text", "link", "qrcode"]
                    for index in 0..<3 {
                        if let point = project(HorizonGuideGeometry.cardPoint(index,local:[0,0,0.06])),
                           let right = project(HorizonGuideGeometry.cardPoint(index,local:[0.52,0,0.06])),
                           let up = project(HorizonGuideGeometry.cardPoint(index,local:[0,0.52,0.06])) {
                            var faceContext = context
                            faceContext.opacity *= cardsVisibility
                            faceContext.concatenate(CGAffineTransform(a:(right.x-point.x)/25,b:(right.y-point.y)/25,
                                c:(point.x-up.x)/25,d:(point.y-up.y)/25,tx:point.x,ty:point.y))
                            faceContext.draw(Text(Image(systemName: symbols[index])).font(.system(size: 25, weight: .ultraLight)).foregroundStyle(.white), at:.zero)
                        }
                    }
                    // Trace from just above the wall to its bottom in the front plane.
                    let cycle = moving ? time.truncatingRemainder(dividingBy: 3.4)/3.4 : 0.45
                    let gesture = min(1,max(0,(cycle-0.1)/0.65))
                    let eased = gesture*gesture*(3-2*gesture)
                    let endpoints = HorizonGuideGeometry.wallSwipeEndpoints
                    let contact = endpoints.top + (endpoints.bottom-endpoints.top)*eased
                    let alpha = moving ? Double(pow(max(0,sin(.pi*cycle)),0.65)) : 0.85
                    let baseOpacity = context.opacity
                    context.opacity *= wallVisibility
                    stroke([endpoints.top,endpoints.bottom], opacity: 0.30, width: 1.2)
                    stroke([endpoints.top,contact], opacity: alpha*0.6, width: 1.6)
                    if let start = project(endpoints.top), let tip = project(endpoints.bottom) {
                        // Use the same projected endpoint as the line, without symbol padding.
                        let length = hypot(tip.x-start.x, tip.y-start.y)
                        if length > 0.001 {
                            let dx = (tip.x-start.x)/length, dy = (tip.y-start.y)/length
                            let base = CGPoint(x:tip.x-dx*8, y:tip.y-dy*8)
                            var arrow = Path()
                            arrow.move(to:CGPoint(x:base.x-dy*7, y:base.y+dx*7))
                            arrow.addLine(to:tip)
                            arrow.addLine(to:CGPoint(x:base.x+dy*7, y:base.y-dx*7))
                            context.stroke(arrow, with:.color(.white.opacity(0.8)),
                                           style:StrokeStyle(lineWidth:1.5,lineCap:.round,lineJoin:.round))
                        }
                    }
                    if let finger = project(contact) {
                        context.draw(Text(Image(systemName:"hand.point.up.left")).font(.system(size:33,weight:.light)).foregroundStyle(.white.opacity(alpha)), at: finger)
                    }
                    context.opacity = baseOpacity * nodesVisibility
                    HorizonGuideNodeTree.draw(context: &context, project: project,
                                              eye: sample.eye,
                                              cameraRight: simd_normalize(simd_cross(sample.target-sample.eye,SIMD3<Float>(0,1,0))),
                                              time: time, moving: moving)

                }
                HorizonGuideTrafficReadout(project:project,time:time)
                    .opacity((1-handoff)*chapterVisibility*nodesVisibility)
            }
            .mask {
                LinearGradient(stops:[.init(color:.clear,location:0),
                    .init(color:.black,location:0.12*(1-handoff)),
                    .init(color:.black,location:0.86+0.14*handoff),.init(color:.clear,location:1)],
                    startPoint:.top,endPoint:.bottom)
                    // Desktop renders into the full window. Retain the narrow
                    // camera framing without a hard rectangular side crop.
                    .frame(width:fullWidthMask ? nil : viewport.width,height:viewport.height)
                    .position(x:viewport.midX,y:viewport.midY)
            }
            // Spatial interpolation already happened above; UIKit must see exact sizes.
            .transaction { $0.animation = nil }
        }
        .clipped()
        .task(id: active && moving && !bridging) { await deviceMotion.run(enabled:active && moving && !bridging) }
        .onAppear { playback.setRunning(active && (moving || bridging)) }
        .onChange(of: active && (moving || bridging)) { _, running in playback.setRunning(running) }
        .onChange(of: moving) { _, moving in if !moving && bridging && !interactive { playback.finishImmediately() } }
    }
}
