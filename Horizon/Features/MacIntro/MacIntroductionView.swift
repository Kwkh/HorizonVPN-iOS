#if os(macOS)
import SwiftUI

struct MacIntroductionView: View {
    var destination: HorizonMotion.Phase = .idle
    let completed: () -> Void
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = -1
    @State private var focus = -1.0
    @State private var camera = HorizonIntroCamera()
    @State private var playback = HorizonGuidePlayback()
    @State private var progress = HorizonSceneProgress()
    @State private var cinema: UUID?
    @State private var bridging = false
    @State private var interactive = false
    @State private var skip = false
    @State private var handoff = false
    @State private var pull = 0.0
    @State private var transitioning = false
    @State private var copyEntered = false
    @State private var returningToWelcome = false
    private var active: Bool { scenePhase == .active }
    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            let viewport = guideViewport(geometry.size)
            ZStack {
                Color.black
                if let cinema {
                    MacMetalScene(phase: destination, progress: progress, active: active, animate: !reduceMotion,
                        brickScale: Float(settings.brickScale), globeScale: Float(settings.globeScale),
                        introductionID: cinema, holdIntroduction: !handoff, skipIntroduction: skip, guideClock: playback.clock)
                }
                if !handoff {
                    HorizonGuideScene(focus: focus, entry: 1, interactive: interactive, bridging: bridging,
                        sourceViewport: viewport, bridgePresented: { sample in
                            if sample.progress >= 1, cinema == nil { cinema = UUID() }
                        }, playback: playback, camera: camera, destinationHeight: geometry.size.height,
                        active: active, moving: !reduceMotion,
                        minimumFrameInterval: 1.0/60, fullWidthMask: true)
                    .allowsHitTesting(false)
                }
                if step == -1 {
                    HorizonWelcomeView(active: active, beginNext: {
                        withAnimation(reduceMotion ? .easeInOut(duration: 0.18) : .easeInOut(duration: 1.5)) { focus = 0 }
                    }, next: { step = 0 })
                        .frame(maxWidth: 680)
                } else if !bridging && cinema == nil {
                    VStack(alignment: .leading, spacing: 18) {
                        Spacer()
                        Text(String(format: "%02d", step+1) + "   QUICK TOUR").font(.caption.monospaced()).foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: step)
                        Text(title).font(.system(size: 34, weight: .light))
                            .contentTransition(.opacity)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: step)
                        Text(caption).font(.title3).foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: step)
                        HStack {
                            Button { move(to: step-1) } label: { Image(systemName: "arrow.left").padding(10) }.buttonStyle(.glass)
                            Spacer()
                            if step < 2 {
                                Button { move(to: step+1) } label: { Label(settings.text("继续", "Next"), systemImage: "arrow.right").padding(10) }.buttonStyle(.glass)
                            } else {
                                Button { beginBridge(bounds) } label: { Label(settings.text("开始", "Start"), systemImage: "arrow.right").padding(10) }.buttonStyle(.glass)
                            }
                        }.padding(.top, 12)
                    }.padding(40).frame(maxWidth: 680).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .opacity(copyEntered ? 1 : 0)
                        .offset(y: copyEntered || reduceMotion ? 0 : 12)
                        .animation(.easeOut(duration: reduceMotion ? 0.18 : 0.55), value: copyEntered)
                        .allowsHitTesting(copyEntered && !transitioning)
                        .accessibilityHidden(!copyEntered)
                        .opacity(1-min(1,pull*3)).animation(.easeInOut(duration: 0.25), value: pull)
                }
                if step >= 0 {
                    VStack { HStack { Text("H O R I Z O N").font(.caption).tracking(2).foregroundStyle(.secondary); Spacer(); Button(settings.text("跳过", "Skip")) { if cinema != nil { skip = true } else { completed() } }.buttonStyle(.glass) }; Spacer() }.padding(28)
                        .opacity(copyEntered ? 1 : 0)
                        .animation(.easeOut(duration: reduceMotion ? 0.18 : 0.45), value: copyEntered)
                        .allowsHitTesting(copyEntered && !transitioning)
                        .accessibilityHidden(!copyEntered)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { value in
                guard cinema == nil, !transitioning else { return }
                if step == 0 || step == 1 {
                    camera.update(translation: [Float(value.translation.width), Float(value.translation.height)], viewport: [Float(geometry.size.width), Float(geometry.size.height)])
                    return
                }
                guard step == 2 else { return }
                if !bridging {
                    guard value.translation.height > 0, playback.beginInteractiveTransition(to: bounds) else { return }
                    bridging = true; interactive = true
                }
                pull = min(1, max(0, value.translation.height / max(180, geometry.size.height*0.4)))
                playback.targetInteractiveProgress(pull)
            }.onEnded { _ in
                camera.end(animated: !reduceMotion)
                guard interactive else { return }
                if pull > 0.45 { playback.targetInteractiveProgress(1) }
                else { playback.targetInteractiveProgress(0); pull = 0 }
            })
            .onChange(of: geometry.size) { _, size in playback.resizeTransition(source: guideViewport(size), destination: CGRect(origin: .zero, size: size)) }
        }
        .onChange(of: progress.preparedIntroduction) { _, id in if id == cinema { handoff = true } }
        .onChange(of: progress.completedIntroduction) { _, id in if id == cinema { completed() } }
        .task(id: step >= 0 && active && !returningToWelcome) {
            guard step >= 0, active, !returningToWelcome, !copyEntered else { return }
            // Mount the copy at its initial presentation before revealing it.
            do { try await Task.sleep(for: .milliseconds(60)) } catch { return }
            guard !Task.isCancelled else { return }
            copyEntered = true
        }
        .task(id: returningToWelcome) {
            guard returningToWelcome else { return }
            // Keep Part 1's identity and copy until its local exit has finished.
            let exitDuration = reduceMotion ? 0.18 : 0.55
            do { try await Task.sleep(for: .seconds(exitDuration)) } catch { return }
            guard !Task.isCancelled else { return }
            step = -1
            // The camera continues the original return while Welcome draws in.
            do { try await Task.sleep(for: .seconds(reduceMotion ? 0.02 : 1.5-exitDuration)) } catch { return }
            guard !Task.isCancelled else { return }
            transitioning = false
            returningToWelcome = false
        }
        .task(id: bridging && interactive && pull < 0.45) {
            guard bridging, interactive else { return }
            while !Task.isCancelled && cinema == nil {
                if playback.interactiveRestingAtStart && pull == 0 { playback.cancelTransition(); bridging = false; interactive = false; return }
                do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
            }
        }
        .background(.black)
    }
    /// Keep the desktop scene above the copy; use this exact viewport for the
    /// globe handoff as well, so reserving text space never changes its identity.
    private func guideViewport(_ size: CGSize) -> CGRect {
        let stage = CGRect(x: 0, y: 56, width: size.width, height: max(180, size.height - 300))
        return HorizonGuideFraming.viewport(stage, tablet: true)
    }
    private var title: String { switch step { case 0: settings.text("带上你的世界", "Bring your world"); case 1: settings.text("选你想走的路", "Choose your path"); default: settings.text("看见这个世界", "Beyond the wall") } }
    private var caption: String { switch step { case 0: settings.text("导入 Clash 订阅链接或文件", "Import a Clash subscription URL or file"); case 1: settings.text("选择节点 · 测试延迟 · 查看实时流量", "Choose nodes · Test latency · See live traffic"); default: settings.text("现在，开启你的 HORIZON 之旅！", "Now start your journey at HORIZON!") } }
    private func move(to next: Int) {
        guard !transitioning else { return }
        transitioning = true
        if next < 0 {
            returningToWelcome = true
            copyEntered = false
            withAnimation(reduceMotion ? .easeInOut(duration: 0.18) : .easeInOut(duration: 1.5)) { focus = -1 }
            return
        }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.18) : .easeInOut(duration: 1.5)) { step = next; focus = Double(next) }
        Task { try? await Task.sleep(for: .seconds(reduceMotion ? 0.2 : 1.5)); transitioning = false }
    }
    private func beginBridge(_ bounds: CGRect) {
        guard !bridging, playback.beginTransition(to: bounds) else { return }
        bridging = true
    }
}
#endif
