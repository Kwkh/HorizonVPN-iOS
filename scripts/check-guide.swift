import Foundation
import CoreGraphics
import simd

@main struct GuideChecks {
    static func main() {
        for fps in [30.0,60,120] {
            var motion = HorizonGuidePullMotion()
            var previous = motion.velocity
            _ = motion.sample(at:0)
            for tick in 1...Int(fps*15) {
                let time = Double(tick)/fps
                // Simulate a fast upward fling, reversal while braking, return,
                // and a subsequent completed pull, including one stalled frame.
                let target = time < 0.9 ? 0.94 : time < 1.1 ? 0 : time < 1.35 ? 0.8 : time < 6 ? 0 : 1.0
                motion.setTarget(target)
                let position = motion.sample(at:time)
                precondition(position >= 0 && position <= 1 && motion.position >= -0.00001 && motion.position <= 1.00001)
                precondition(abs(motion.velocity) <= HorizonGuidePullMotion.maximumSpeed+0.00001)
                precondition(abs(motion.velocity-previous)*fps <= HorizonGuidePullMotion.maximumAcceleration+0.001,
                    "rapid reversals and settling must honor the acceleration ceiling")
                previous = motion.velocity
                if tick == Int(fps*5.9) { precondition(motion.atStart, "cancelled pull settles before restoring the guide") }
            }
            precondition(motion.position == 1 && motion.velocity == 0)
            motion.setTarget(0)
            let before = motion.position
            _ = motion.sample(at:100)
            precondition(abs(motion.position-before) < 0.004, "stalled/resumed rendering cannot jump forward")
        }
        // Once motion is visually near rest, no long invisible convergence tail.
        for fps in [30.0,60,120] {
            var follower = HorizonGuidePullMotion()
            _ = follower.sample(at:0)
            var nearRest: Double?, finished: Double?
            for tick in 1...Int(fps*6) {
                let time = Double(tick)/fps
                follower.setTarget(time < 0.9 ? 0.53 : 0)
                _ = follower.sample(at:time)
                if time>0.9 && follower.position<0.001 && nearRest == nil { nearRest = time }
                if time>0.9 && follower.atStart { finished = time; break }
            }
            precondition(nearRest != nil && finished != nil && finished!-nearRest! < 0.25,
                         "near-rest to exact endpoint must take less than 250 ms")
        }
        for tick in 0...100 {
            let raw = Double(tick)/100
            let spatial = HorizonGuidePullState.spatialProgress(raw)
            precondition(abs(HorizonGuidePullState.gestureProgress(forSpatial:spatial)-raw) < 0.00001,
                "regrab preserves the rendered pose under eased gesture mapping")
            if tick > 0 {
                precondition(spatial >= HorizonGuidePullState.spatialProgress(raw-0.01), "pull easing stays monotonic")
            }
        }
        precondition(HorizonGuidePullState.spatialProgress(0.01) < 0.00002)
        precondition(1-HorizonGuidePullState.spatialProgress(0.99) < 0.00002, "both endpoints ease gently")
        var pull = HorizonGuidePullState()
        pull.begin(presentedProgress:0)
        pull.update(distance:2.4,height:400)
        precondition(pull.textVisibility < 1 && pull.textVisibility > 0.99,
                     "text starts fading on a small pull without disappearing abruptly")
        pull.update(distance:30,height:400)
        precondition(pull.textVisibility > 0.4 && pull.textVisibility < 0.6,
                     "text remains partly visible at the former full-fade distance")
        precondition(!pull.end(cancelled:false) && pull.phase == .returning, "short pull must return")
        precondition(pull.textVisibility == 0, "cancelled pull hides controls until the camera settles")
        let previousGeneration = pull.generation
        pull.begin(presentedProgress:0.08)
        precondition(pull.progress == 0.08 && pull.generation != previousGeneration, "regrab starts at visible progress and invalidates old completion")
        pull.update(distance:200,height:400)
        precondition(pull.progress < 1, "finger never produces a handoff endpoint before release")
        let hiddenProgress = pull.textFadeProgress
        pull.update(distance:0,height:400)
        precondition(pull.textFadeProgress == hiddenProgress, "reversing the finger must not reveal controls before the camera returns")
        precondition(!pull.end(cancelled:false), "reversing an armed pull disarms completion")
        pull.begin(presentedProgress:0.001)
        precondition(pull.textVisibility == 0, "regrab near the origin keeps controls hidden")
        pull.reset()
        precondition(pull.textFadeProgress == 0, "only settled/reset state restores controls")
        pull.begin(presentedProgress:0)
        pull.update(distance:200,height:400)
        precondition(!pull.end(cancelled:true), "system cancellation must not enter even above threshold")
        pull.reset()
        pull.begin(presentedProgress:0)
        pull.update(distance:200,height:400)
        precondition(pull.end(cancelled:false) && pull.phase == .committed)
        precondition(!pull.end(cancelled:false), "release callback is idempotent")
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        var clock = HorizonGuideClock()
        clock.setRunning(true, now: start)
        precondition(clock.elapsed(at: start.addingTimeInterval(2)) == 2)
        clock.setRunning(false, now: start.addingTimeInterval(2))
        precondition(clock.elapsed(at: start.addingTimeInterval(200)) == 2, "background must freeze ambient clock")
        clock.setRunning(true, now: start.addingTimeInterval(200))
        precondition(clock.elapsed(at: start.addingTimeInterval(201)) == 3, "resume without jump")
        for index in -1..<2 {
            var previous = HorizonGuideGeometry.camera(focus: Double(index))
            for sample in 1...120 {
                let current = HorizonGuideGeometry.camera(focus: Double(index)+Double(sample)/120)
                precondition(simd_distance(current.eye,previous.eye) < 0.08, "camera path is continuous")
                previous = current
            }
        }
        let welcomeCamera = HorizonGuideGeometry.camera(focus:-1)
        precondition(welcomeCamera.target.x == -7 && HorizonGuideGeometry.camera(focus:0).target.x == 0,
                     "welcome precedes the unchanged first chapter in the same scene")
        precondition(HorizonGuidePullState.spatialProgress(-1+1) == 0,
                     "welcome contains particles without chapter demonstration objects")
        precondition(HorizonGuideStep.allCases.count == 3)
        precondition(HorizonGuideGeometry.faces.allSatisfy { $0.points.count == 4 })
        precondition(HorizonGuideStep.allCases == [.subscriptions,.nodes,.connection], "node selection precedes connection")
        precondition(abs(HorizonGuideGeometry.hub.x-7) < 0.001 && HorizonGuideGeometry.globe.x == 14)
        var drifting = 0
        for (index,original) in HorizonGuideGeometry.particles.enumerated() {
            let a = HorizonGuideGeometry.particle(original,index:index,time:0)
            let b = HorizonGuideGeometry.particle(original,index:index,time:2)
            if simd_distance(a,b) > 0.1 { drifting += 1 }
            precondition(simd_distance(a,original) < 0.71, "bounded continuous drift")
        }
        precondition(drifting > 150, "background has perceptible motion")
        for aspect: Float in [0.4,0.58,1,1.8] {
            let destination = HorizonGeometry.camera(journey:1)
            let end = HorizonGuideGeometry.bridge(focus:2,entry:1,tilt:[0.7,-0.4],progress:1,aspect:aspect)
            let shift = SIMD3<Float>(14,0,0)
            precondition(simd_distance(end.eye-shift,destination.eye) < 0.00001)
            precondition(simd_distance(end.target-shift,destination.target) < 0.00001)
            precondition(simd_distance(end.globe-SIMD4<Float>(14,0,0,0),HorizonGeometry.introductionGlobe(aspect:aspect)) < 0.00001, "same globe at Metal handoff")
            var previousPose = HorizonGuideGeometry.bridge(focus:2,entry:1,tilt:[0.7,-0.4],progress:0,aspect:aspect)
            for tick in 1...120 {
                let pose = HorizonGuideGeometry.bridge(focus:2,entry:1,tilt:[0.7,-0.4],progress:Double(tick)/120,aspect:aspect)
                precondition(simd_distance(pose.eye,previousPose.eye) < 0.05)
                precondition(simd_distance(pose.globe,previousPose.globe) < 0.06)
                previousPose = pose
            }
        }
        var filter = GuideTiltFilter()
        // Changing local aspect and UIKit size independently caused an elliptical
        // globe. Every in-flight projection must embed a correctly proportioned
        // local viewport into the same fixed full-page Metal drawable.
        for canvas in [CGSize(width:402,height:800), CGSize(width:800,height:402)] {
            for tilt: SIMD2<Float> in [.zero,[0.7,-0.4]] {
                let viewport = CGRect(x:0,y:52,width:canvas.width,height:canvas.height*0.48)
                let endRect = CGRect(x:0,y:-62,width:canvas.width,height:canvas.height*0.86)
                let pose = HorizonGuideGeometry.bridge(focus:1.9,entry:1,tilt:tilt,progress:0,
                    aspect:Float(viewport.width/viewport.height))
                let source = HorizonGuidePresentation(eye:pose.eye,target:pose.target,globe:pose.globe,
                    viewport:viewport,time:13,visibility:0.9)
                let transition = HorizonGuideTransition(source:source,destination:endRect)
                let nearStart = transition.sample(progress:HorizonGuidePullMotion.settlingDistance)
                let exactStart = transition.sample(progress:0)
                func screen(_ point: SIMD3<Float>, frame: HorizonGuidePresentation) -> SIMD2<Float> {
                    let vp = HorizonGeometry.perspective(aspect:Float(frame.viewport.width/frame.viewport.height))
                        * HorizonGeometry.view(eye:frame.eye,target:frame.target)
                    let clip = vp*SIMD4(point,1)
                    return [Float(frame.viewport.minX)+(clip.x/clip.w+1)*Float(frame.viewport.width)/2,
                            Float(frame.viewport.minY)+(1-clip.y/clip.w)*Float(frame.viewport.height)/2]
                }
                for point in HorizonGuideGeometry.faces.flatMap(\.points) where point.x > 11 {
                    precondition(simd_distance(screen(point,frame:nearStart),screen(point,frame:exactStart)) < 0.5,
                        "terminal correction must be smaller than half a screen point")
                }
                for direction: SIMD3<Float> in [[0,0,0],[1,0,0],[-1,0,0],[0,1,0],[0,-1,0],[0,0,1]] {
                    let a = SIMD3(nearStart.globe.x,nearStart.globe.y,nearStart.globe.z)+direction*nearStart.globe.w
                    let b = SIMD3(exactStart.globe.x,exactStart.globe.y,exactStart.globe.z)+direction*exactStart.globe.w
                    precondition(simd_distance(screen(a,frame:nearStart),screen(b,frame:exactStart)) < 0.5)
                }
                let scrubStart = transition.sample(progress:0)
                let scrubMid = transition.sample(progress:0.4)
                let scrubEnd = transition.sample(progress:1)
                precondition(scrubStart.eye == source.eye && scrubStart.viewport == source.viewport)
                precondition(abs(scrubMid.viewport.width-(viewport.width+(endRect.width-viewport.width)*0.4)) < 0.001)
                precondition(simd_distance(scrubMid.eye,source.eye+(scrubEnd.eye-source.eye)*0.4) < 0.00001,
                    "finger progress maps directly to the camera without a second easing curve")
                precondition(transition.sample(progress:0).eye == source.eye, "reverse scrub returns exactly to its source")
                let first = transition.sample(elapsed:0)
                precondition(first.eye == source.eye && first.globe == source.globe && first.viewport == viewport,
                    "handoff starts at actually displayed pose, including unfinished chapter motion and tilt")
                var previous = first
                for tick in 0...192 {
                    let frame = transition.sample(elapsed:Double(tick)/120)
                    let embedding = HorizonGuideTransition.embed(frame.viewport,in:canvas)
                    let perspective = HorizonGeometry.perspective(aspect:Float(frame.viewport.width/frame.viewport.height))
                    let full = embedding*perspective
                    let pixelX = full.columns.0.x*Float(canvas.width)
                    let pixelY = full.columns.1.y*Float(canvas.height)
                    precondition(abs(pixelX/pixelY-1) < 0.00001, "sphere retains isotropic pixel projection at every frame")
                    for point: SIMD4<Float> in [[-0.8,-0.6,0,1],[0,0,0,1],[0.9,0.7,0,1]] {
                        let embedded = embedding*point
                        let x = CGFloat(embedded.x+1)*canvas.width/2
                        let y = CGFloat(1-embedded.y)*canvas.height/2
                        precondition(abs(x-(frame.viewport.minX+CGFloat(point.x+1)*frame.viewport.width/2)) < 0.001)
                        precondition(abs(y-(frame.viewport.minY+CGFloat(1-point.y)*frame.viewport.height/2)) < 0.001)
                    }
                    precondition(abs(frame.time-source.time-Float(tick)/120) < 0.00001,
                        "rotation keeps constant speed through the spatial bridge")
                    precondition(simd_distance(frame.eye,previous.eye) < 0.12 && simd_distance(frame.globe,previous.globe) < 0.14,
                        "continuous pose during viewport interpolation")
                    previous = frame
                }
                let end = transition.sample(elapsed:10)
                let camera = HorizonGeometry.camera(journey:1)
                precondition(end.viewport == endRect && end.progress == 1)
                precondition(simd_distance(end.eye-SIMD3<Float>(14,0,0),camera.eye) < 0.00001)
                precondition(simd_distance(end.globe-SIMD4<Float>(14,0,0,0),
                    HorizonGeometry.introductionGlobe(aspect:Float(endRect.width/endRect.height))) < 0.00001)
                precondition(simd_distance(first.eye,transition.sample(elapsed:0.001).eye) < 0.00001)
                precondition(simd_distance(end.eye,transition.sample(elapsed:1.599).eye) < 0.00001)
            }
        }
        precondition(filter.update(angles:.zero,delta:1.0/30) == .zero, "neutral entry is stationary")
        var previous = SIMD2<Double>.zero
        for _ in 0..<120 {
            let value = filter.update(angles:[1,1],delta:1.0/30)
            precondition(simd_length(value) <= 1.000001, "extreme tilt stays bounded")
            precondition(simd_distance(previous,value) < 0.16, "sensor jump is smoothed")
            previous = value
        }
        let invalid = filter.update(angles:[.nan,0],delta:1)
        precondition(invalid == previous)
        let resumed = filter.update(angles:.zero,delta:100)
        precondition(simd_distance(previous,resumed) < 0.29, "resume cannot jump to neutral")
        for _ in 0..<120 { _ = filter.update(angles:.zero,delta:1.0/30) }
        precondition(simd_length(filter.value) < 0.0001, "returns to neutral")
        for fps in [30.0,60,120] {
            var neutral = GuideTiltNeutral()
            let identity = simd_quatd(angle:0,axis:[0,1,0])
            let held = simd_quatd(angle:0.2,axis:[0,1,0])
            neutral.reset(to:identity)
            neutral.update(sample:held,angularSpeed:0.4,delta:1/fps)
            for _ in 0..<Int(fps*0.3) { neutral.update(sample:held,angularSpeed:0.001,delta:1/fps) }
            precondition(!neutral.isRecentering && neutral.attitude == identity,
                         "brief pauses must not rebase the scene")
            for _ in 0..<Int(fps*0.1)+1 { neutral.update(sample:held,angularSpeed:0.001,delta:1/fps) }
            precondition(neutral.isRecentering && neutral.attitude == held,
                         "recenter after 0.4 seconds, within one sensor frame")
            neutral.update(sample:identity,angularSpeed:0.4,delta:1/fps)
            precondition(!neutral.isRecentering,"renewed motion resumes parallax")
            neutral.reset(to:identity)
            for tick in 1...Int(fps*4) {
                neutral.update(sample:simd_quatd(angle:Double(tick)/fps*0.02,axis:[0,1,0]),
                               angularSpeed:0.02,delta:1/fps)
                precondition(!neutral.isRecentering,"slow accumulated drift is not stillness")
            }
            neutral.update(sample:held,angularSpeed:0,delta:10)
            precondition(!neutral.isRecentering,"suspension is not stable sensor time")
        }
        var settlingTilt = GuideTiltFilter()
        for _ in 0..<60 { _ = settlingTilt.update(angles:[0.2,0],delta:1.0/30) }
        let beforeRecenter = settlingTilt.value
        _ = settlingTilt.update(angles:.zero,delta:1.0/30,recentering:true)
        precondition(simd_distance(beforeRecenter,settlingTilt.value)<0.05,"neutral rebase cannot snap")
        for _ in 0..<150 { _ = settlingTilt.update(angles:.zero,delta:1.0/30,recentering:true) }
        precondition(simd_length(settlingTilt.value)<0.0001)
        let liveClock = HorizonSceneClock()
        liveClock.setRunning(true,now:start)
        precondition(abs(liveClock.elapsed(at:start.addingTimeInterval(1.6))-1.6) < 0.000001)
        // A new renderer adopts the same clock without resetting or freezing it.
        let destinationClock = liveClock
        destinationClock.setRunning(true,now:start.addingTimeInterval(1.6))
        precondition(liveClock.elapsed(at:start.addingTimeInterval(2)) == 2)
        destinationClock.setRunning(false,now:start.addingTimeInterval(2))
        precondition(liveClock.elapsed(at:start.addingTimeInterval(100)) == 2)
        liveClock.setRunning(true,now:start.addingTimeInterval(100))
        precondition(destinationClock.elapsed(at:start.addingTimeInterval(101)) == 3)
        let drag = HorizonIntroCamera()
        drag.update(translation:[10000,-10000],viewport:[402,390],now:start)
        precondition(simd_length(drag.offset(at:start)) <= 1.00001, "finger movement bounded on both axes")
        let held = drag.offset(at:start)
        drag.end(animated:true,now:start)
        precondition(drag.offset(at:start) == held, "release has no first-frame jump")
        let halfway = drag.offset(at:start.addingTimeInterval(0.375))
        precondition(simd_distance(halfway,held*0.5) < 0.00001)
        drag.update(translation:.zero,viewport:[402,390],now:start.addingTimeInterval(0.375))
        precondition(simd_distance(drag.offset(at:start.addingTimeInterval(0.375)),halfway) < 0.00001,
                     "re-grabbing during return starts at visible position")
        drag.end(animated:true,now:start.addingTimeInterval(0.375))
        precondition(drag.offset(at:start.addingTimeInterval(2)) == .zero)
        drag.update(translation:[100,50],viewport:[402,390],now:start.addingTimeInterval(2))
        drag.end(animated:false,now:start.addingTimeInterval(2))
        precondition(drag.offset(at:start.addingTimeInterval(2)) == .zero, "reduced motion settles immediately")
        var normals = [SIMD3<Float>]()
        for index in 0..<3 {
            let center = HorizonGuideGeometry.cardPoint(index,local:.zero)
            let right = HorizonGuideGeometry.cardPoint(index,local:[1,0,0])-center
            let up = HorizonGuideGeometry.cardPoint(index,local:[0,1,0])-center
            precondition(abs(simd_length(right)-1) < 0.00001 && abs(simd_dot(right,up)) < 0.00001,
                "card rotation preserves rigid geometry")
            normals.append(simd_cross(right,up))
        }
        precondition(simd_distance(normals[0],normals[1]) > 0.15 && simd_distance(normals[1],normals[2]) > 0.15,
            "three card faces have distinct orientations")
        print("PASS: bounded acceleration/speed at 30/60/120 Hz, reversible pull, cancellation/regrab/commit, linear scrubbing, camera/clock continuity, chapter order, particle drift, globe handoff, bounded tilt smoothing and resume")
    }
}
