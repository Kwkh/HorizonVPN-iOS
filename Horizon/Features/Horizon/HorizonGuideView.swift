import SwiftUI

/// First-run guide, deliberately separate from the real connection controls.
struct HorizonGuideView: View {
    let destinationFrame: CGRect
    let sceneReady: Bool
    let prepareScene: (Double?, Double?, HorizonSceneClock?) -> Void
    let continueToScene: () -> Void
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var showingWelcome = true
    @State private var welcomeDeparting = false
    @State private var step = HorizonGuideStep.subscriptions
    @State private var leaving = false
    @State private var entered = false
    @State private var sceneFrame = CGRect.zero
    @State private var revealing = false
    @State private var bridging = false
    @State private var bridgeArrived = false
    @State private var playback = HorizonGuidePlayback()
    @State private var camera = HorizonIntroCamera()
    @State private var pull = HorizonGuidePullState()
    @State private var interactiveBridge = false
    @State private var chapterSettled = false
    @State private var descriptionHeight: CGFloat = 0
    @State private var contentViewportHeight: CGFloat = 0
    @State private var hintVisible = false
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 32
    @AccessibilityFocusState private var titleFocused: Bool

    private var welcomePresented: Bool { showingWelcome && !welcomeDeparting }
    private var sceneFocus: Double { welcomePresented ? -1 : Double(step.rawValue) }

    private var textVisibility: Double {
        pull.textVisibility
    }

    var body: some View {
        GeometryReader { geometry in
            let sceneHeight = max(220, min(430, geometry.size.height * 0.48))
            let localDestination = destinationFrame.offsetBy(dx: -geometry.frame(in: .global).minX,
                                                             dy: -geometry.frame(in: .global).minY)
            let initialFrame = HorizonGuideFraming.viewport(sceneFrame.isEmpty ? CGRect(x:0,y:52,width:geometry.size.width,height:sceneHeight) : sceneFrame, tablet: UIDevice.current.userInterfaceIdiom == .pad)
            ZStack(alignment: .topLeading) {
                HorizonGuidePullSurface(
                    enabled:step == .connection && !showingWelcome && !leaving && chapterSettled,
                    referenceHeight:sceneHeight,
                    changed: { distance, height in updatePull(distance:distance,height:height,destination:localDestination) },
                    ended: { cancelled in endPull(cancelled:cancelled,destination:localDestination) }) {
                VStack(spacing: 0) {
                    HStack {
                        Text("HORIZON").font(.caption.weight(.medium)).tracking(5)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(settings.text("跳过指南", "Skip guide")) { finish(destination:localDestination) }
                            .font(.callout).buttonStyle(.plain)
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityIdentifier("guide.skip")
                            .disabled(bridging)
                    }.padding(.horizontal, 26).padding(.top, 8)
                        .opacity(textVisibility)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Group {
                                if step == .connection {
                                    Color.clear.contentShape(Rectangle())
                                        .accessibilityElement(children:.ignore)
                                        .accessibilityLabel(settings.text("在页面任意位置下滑进入；辅助功能可轻点两下继续", "Pull down anywhere to enter; double-tap to continue with accessibility"))
                                        .accessibilityAddTraits(.isButton)
                                        .accessibilityAction { finish(destination:localDestination) }
                                        .accessibilityIdentifier("guide.pullToContinue")
                                } else {
                                    HorizonCameraDragSurface(camera:camera,enabled:!leaving,animated:settings.particles)
                                        .accessibilityHidden(true)
                                }
                            }
                                .frame(height:sceneHeight)
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("horizonGuide")) } action: { sceneFrame = $0 }
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(spacing: 10) {
                                    Text(String(format: "%02d", step.rawValue + 1))
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                        .contentTransition(.numericText())
                                    Rectangle().fill(.white.opacity(0.22)).frame(height: 0.5)
                                    Text(settings.text("功能导览", "QUICK TOUR"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Text(settings.text(step.title.chinese, step.title.english))
                                    .font(.system(size: titleSize, weight: .light))
                                    .frame(maxWidth: .infinity, minHeight: titleSize * 2.4, alignment: .topLeading)
                                    .contentTransition(.opacity)
                                    .accessibilityAddTraits(.isHeader)
                                    .accessibilityFocused($titleFocused)
                                Text(settings.text(step.caption.chinese, step.caption.english))
                                    .font(.body).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
                                    .contentTransition(.opacity)
                                    .accessibilityLabel(settings.text(step.accessibilityDescription.chinese, step.accessibilityDescription.english))
                            }
                            .padding(.horizontal, 28)
                            .onGeometryChange(for:CGFloat.self) { $0.size.height } action: { descriptionHeight = $0 }
                            .animation(.easeInOut(duration: reduceMotion ? 0.2 : 0.35), value: step)
                            .opacity(entered ? 1 : 0)
                            .animation(.easeInOut(duration: 0.45).delay(reduceMotion ? 0 : 0.15), value: entered)
                            .opacity(textVisibility)
                            // Keep identity/layout while leaving Part 3 so the hint
                            // can fade instead of disappearing with its branch.
                            HorizonGuideSwipeHint(active:step == .connection)
                                    .padding(.horizontal,28)
                                    .frame(maxWidth:.infinity,
                                           minHeight:max(80,contentViewportHeight-sceneHeight-descriptionHeight-16))
                                    .opacity(hintVisible && !leaving && step == .connection ? 1 : 0)
                                    .animation(.easeInOut(duration:hintVisible ? (reduceMotion ? 0.3 : 0.9) : 0.22),value:hintVisible)
                                    .animation(.easeOut(duration:0.22),value:step)
                                    .opacity(textVisibility)
                                    .accessibilityHidden(step != .connection || !hintVisible || leaving || textVisibility == 0)
                        }.padding(.bottom, 16)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDisabled(step == .connection && !voiceOver)
                    .onGeometryChange(for:CGFloat.self) { $0.size.height } action: { contentViewportHeight = $0 }
                    ZStack {
                      HStack(spacing: 18) {
                        Button {
                            if step == .subscriptions { showWelcome() }
                            else if let previous = HorizonGuideStep(rawValue:step.rawValue-1) { select(previous) }
                        } label: {
                            Image(systemName: "arrow.left").frame(width: 44, height: 44)
                        }
                        .buttonStyle(.glass).buttonBorderShape(.circle)
                        .disabled(bridging)
                        .accessibilityLabel(settings.text("上一步", "Previous"))
                        .accessibilityIdentifier("guide.previous")
                        Spacer()
                        Button {
                            if let next = HorizonGuideStep(rawValue: step.rawValue + 1) { select(next) }
                        } label: {
                            Label(settings.text("继续", "Next"), systemImage: "arrow.right")
                                .font(.callout.weight(.medium)).padding(.horizontal, 18).frame(minHeight: 44)
                                .contentTransition(.opacity)
                        }
                        .buttonStyle(.glass).buttonBorderShape(.capsule)
                        .accessibilityIdentifier("guide.next")
                        .opacity(step == .connection ? 0 : 1)
                        .disabled(step == .connection)
                        .accessibilityHidden(step == .connection)
                      }
                      if step != .connection {
                        HStack(spacing:8) {
                            ForEach(HorizonGuideStep.allCases,id:\.rawValue) { item in
                                Capsule().fill(.white.opacity(item == step ? 1 : 0.25))
                                    .frame(width:item == step ? 22 : 6,height:4)
                            }
                        }
                        .accessibilityElement(children:.ignore)
                        .accessibilityLabel(settings.text("第 \(step.rawValue+1) 步，共 3 步", "Step \(step.rawValue+1) of 3"))
                      }
                    }
                    .frame(minHeight:64)
                    .animation(.easeInOut(duration: 0.3), value: step)
                    .padding(.horizontal, 26).padding(.vertical, 18)
                    .opacity(textVisibility)
                }
                }
                .opacity(leaving || welcomePresented ? 0 : 1)
                .animation(.easeInOut(duration:0.35),value:leaving)
                .animation(reduceMotion ? .easeInOut(duration:0.2)
                           : HorizonWelcomeView.departureAnimation,value:welcomePresented)
                .allowsHitTesting(!showingWelcome && !leaving)
                .accessibilityHidden(showingWelcome || leaving)
                HorizonGuideScene(focus: sceneFocus, entry: reduceMotion || entered ? 1 : 0,
                    interactive:interactiveBridge,
                    bridging:bridging, sourceViewport:initialFrame, bridgePresented:bridgeDidPresent,
                    playback:playback, camera:camera, destinationHeight:destinationFrame.height,
                    active:scenePhase == .active, moving:!welcomePresented && !reduceMotion && settings.particles)
                    .frame(width:geometry.size.width,height:geometry.size.height)
                    .animation(reduceMotion ? nil : (welcomeDeparting
                        ? HorizonWelcomeView.departureAnimation
                        : .timingCurve(0.22,0,0.16,1,duration:HorizonWelcomeView.departureDuration)),value:sceneFocus)
                    .opacity(entered ? 1 : 0)
                    .animation(.easeInOut(duration:reduceMotion ? 0.25 : 1.1),value:entered)
                    .allowsHitTesting(false).accessibilityHidden(true)
                // Remove the retired glass controls after their fade; transparent
                // glass views can still alter controls behind them in composition.
                ZStack {
                    if showingWelcome {
                        HorizonWelcomeView(active:!leaving,
                            beginNext: { welcomeDeparting = true },
                            next: { select(.subscriptions) })
                            .opacity(entered && !leaving ? 1 : 0)
                            .animation(.easeInOut(duration:0.35),value:leaving)
                            .animation(.easeInOut(duration:0.2),value:entered)
                            .allowsHitTesting(!leaving)
                            .accessibilityHidden(leaving)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration:reduceMotion ? 0.2 : 0.4),value:showingWelcome)
            }
            .coordinateSpace(name:"horizonGuide")
            .onChange(of: initialFrame) { _, frame in
                if UIDevice.current.userInterfaceIdiom == .pad {
                    playback.resizeTransition(source: frame, destination: localDestination)
                }
            }
            .onChange(of: localDestination) { _, destination in
                if UIDevice.current.userInterfaceIdiom == .pad {
                    playback.resizeTransition(source: initialFrame, destination: destination)
                }
            }
        }
        .background(.black).foregroundStyle(.white).tint(.white)
        .opacity(revealing ? 0 : 1)
        .preferredColorScheme(.dark)
        .allowsHitTesting(!leaving)
        .task {
            await Task.yield()
            entered = true
            if voiceOver && !showingWelcome { titleFocused = true }
        }
        .onChange(of:sceneReady) { _, _ in revealIfReady() }
        .task(id:step == .connection && scenePhase == .active && !leaving) {
            hintVisible = false
            guard step == .connection, scenePhase == .active, !leaving else { return }
            do { try await Task.sleep(for:.seconds(2)) } catch { return }
            guard !Task.isCancelled else { return }
            hintVisible = true
        }
        .task(id:sceneFocus) {
            chapterSettled = false
            guard !welcomePresented else { return }
            // Capture a settled chapter pose so reversing a pull returns to the
            // same camera rather than the endpoint of an unfinished chapter move.
            try? await Task.sleep(for:.seconds(reduceMotion ? 0.2 : HorizonWelcomeView.departureDuration + 0.05))
            guard !Task.isCancelled else { return }
            chapterSettled = true
        }
    }
    private func select(_ next: HorizonGuideStep) {
        chapterSettled = false
        hintVisible = false
        playback.cancelTransition()
        pull.reset()
        interactiveBridge = false
        bridging = false
        camera.reset()
        step = next
        showingWelcome = false
        welcomeDeparting = false
        if voiceOver { titleFocused = true }
    }
    private func showWelcome() {
        select(.subscriptions)
        showingWelcome = true
        titleFocused = false
    }
    private func finish(destination: CGRect) {
        guard !leaving else { return }
        interactiveBridge = false
        bridging = step == .connection && !reduceMotion && settings.particles
            && !HorizonParticlePass.points.isEmpty && playback.beginTransition(to:destination)
        leaving = true
        if !bridging { prepareScene(nil,nil,nil) }
    }
    private func updatePull(distance: CGFloat, height: CGFloat, destination: CGRect) {
        guard !leaving, chapterSettled else { return }
        if pull.phase != .dragging {
            let presented = interactiveBridge
                ? HorizonGuidePullState.gestureProgress(forSpatial:playback.presentedProgress) : 0
            if !interactiveBridge && !reduceMotion && settings.particles && !HorizonParticlePass.points.isEmpty {
                interactiveBridge = playback.beginInteractiveTransition(to:destination)
                bridging = interactiveBridge
            }
            var transaction = Transaction(animation:nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { pull.begin(presentedProgress:presented) }
        }
        withAnimation(.easeOut(duration:0.22)) {
            pull.update(distance:Double(distance),height:Double(height))
        }
        if interactiveBridge { playback.targetInteractiveProgress(HorizonGuidePullState.spatialProgress(pull.progress)) }
    }
    private func endPull(cancelled: Bool, destination: CGRect) {
        guard pull.phase == .dragging, !leaving else { return }
        let committed = withAnimation(.easeOut(duration:0.2)) { pull.end(cancelled:cancelled) }
        if committed {
            if interactiveBridge {
                leaving = true
                playback.targetInteractiveProgress(1)
            } else { finish(destination:destination) }
        } else {
            if interactiveBridge {
                // Wait for the actual bounded follower to settle, not a separate
                // SwiftUI completion that can remove the scene mid-deceleration.
                playback.targetInteractiveProgress(0)
                return
            }
            // No animated scene exists in this fallback, so there is nothing
            // to wait 0.85 seconds for before restoring the controls.
            playback.cancelTransition()
            interactiveBridge = false
            bridging = false
            withAnimation(.easeOut(duration:0.16)) { pull.reset() }
        }
    }
    private func bridgeDidPresent(_ sample: HorizonGuidePresentation) {
        if interactiveBridge, pull.phase == .returning, sample.progress == 0,
           playback.interactiveRestingAtStart {
            playback.cancelTransition()
            interactiveBridge = false
            bridging = false
            withAnimation(.easeOut(duration:0.16)) { pull.reset() }
            return
        }
        guard leaving, bridging, !bridgeArrived, sample.progress >= 1 else { return }
        bridgeArrived = true
        prepareScene(-0.4+Double(sample.time)*0.055,Double(sample.time),playback.clock)
    }
    private func revealIfReady() {
        guard leaving, sceneReady, !revealing, !bridging || bridgeArrived else { return }
        if bridging {
            // Both Metal surfaces now contain the same pose. Fading a transparent
            // drawable and its black backing separately causes a brightness dip.
            // Swap the matched frames without opacity blending or a removal fade.
            var transaction = Transaction(animation:nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { continueToScene() }
            return
        }
        withAnimation(.easeInOut(duration:0.35), completionCriteria:.removed) {
            revealing = true
        } completion: {
            continueToScene()
        }
    }
}
