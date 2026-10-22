import SwiftUI

/// Welcome typography owns its local choreography; the parent owns navigation.
struct HorizonWelcomeView: View {
    static let departureDuration = 1.5
    static let departureStagger = 0.04
    private static let dividerDuration = 0.8
    static var departureAnimation: Animation {
        .timingCurve(0.42,0,0.58,1,duration:departureDuration)
    }
    let active: Bool
    let beginNext: () -> Void
    let next: () -> Void
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .largeTitle) private var brandSize: CGFloat = 46
    @ScaledMetric(relativeTo: .title2) private var welcomeSize: CGFloat = 24
    @ScaledMetric(relativeTo: .body) private var captionSize: CGFloat = 19
    @AccessibilityFocusState private var titleFocused: Bool
    @State private var revealedRows = 0
    @State private var captionRevealed = false
    @State private var wordmarkComplete = false
    @State private var entranceComplete = false
    @State private var exiting = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing:0) {
                // Preserve the welcome composition without a skip control.
                Color.clear
                    .frame(height:52)
                    .accessibilityHidden(true)
                ScrollView {
                    VStack(spacing:20) {
                        VStack(spacing:10) {
                            line(settings.text("欢迎来到", "Welcome to"),index:0,size:welcomeSize,
                                 tracking:1,width:geometry.size.width)
                            HorizonWelcomeWordmark(revealed: revealedRows > 1,
                                active: active && !exiting, fontSize: brandSize,
                                completed: { wordmarkComplete = true })
                                .offset(x: exiting && !reduceMotion ? -geometry.size.width-80 : 0)
                                .opacity(!exiting ? 1 : 0)
                                .animation(reduceMotion ? .easeOut(duration: 0.18)
                                           : Self.departureAnimation.delay(Self.departureStagger), value: exiting)
                                .accessibilityHidden(revealedRows < 2 || exiting)
                        }
                        .accessibilityElement(children:.combine)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($titleFocused)
                        divider(width:geometry.size.width)
                        line(settings.text("在这里，你可以……", "Here, you can…"),index:2,
                             size:captionSize,tracking:0,width:geometry.size.width)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal,28).padding(.vertical,32)
                    .frame(minHeight:max(260,geometry.size.height-152))
                }
                .scrollIndicators(.hidden)
                #if os(macOS)
                // Keep desktop typography centered without cutting its exit
                // at the narrower welcome column's scrolling bounds.
                .scrollClipDisabled()
                #endif
                HStack {
                    Spacer()
                    Button { beginExit() } label: {
                        Label(settings.text("继续", "Next"),systemImage:"arrow.right")
                            .font(.callout.weight(.medium))
                            .padding(.horizontal,18).frame(minHeight:44)
                    }
                    .buttonStyle(.glass).buttonBorderShape(.capsule)
                    .accessibilityIdentifier("welcome.next")
                    .disabled(!entranceComplete)
                }
                .frame(minHeight:64)
                .padding(.horizontal,26).padding(.vertical,18)
                .opacity(entranceComplete && !exiting ? 1 : 0)
                .allowsHitTesting(entranceComplete && !exiting)
                .accessibilityHidden(!entranceComplete || exiting)
                .animation(.easeInOut(duration:reduceMotion ? 0.18 : 0.35),value:entranceComplete)
                .animation(.easeOut(duration:0.2),value:exiting)
            }
            #if !os(macOS)
            .clipped()
            #endif
            .disabled(exiting)
        }
        .task(id:active && scenePhase == .active && !exiting) {
            guard active, scenePhase == .active, !exiting else { return }
            while revealedRows < 2 {
                do { try await Task.sleep(for:.seconds(reduceMotion ? 0.06 : 0.18)) } catch { return }
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? .easeOut(duration:0.18) : .smooth(duration:0.6)) {
                    revealedRows += 1
                }
            }
        }
        .task(id:wordmarkComplete && active && scenePhase == .active && !exiting) {
            guard wordmarkComplete, active, scenePhase == .active, !exiting,
                  !entranceComplete else { return }
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? .easeOut(duration:0.18) : .smooth(duration:0.6)) {
                revealedRows = 3
            }
            let captionDelay = reduceMotion ? 0.06 : 0.5
            do { try await Task.sleep(for:.seconds(captionDelay)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? .easeOut(duration:0.18) : .smooth(duration:0.6)) {
                captionRevealed = true
            }
            // Wait for both the divider and the staggered caption to finish.
            let remaining = reduceMotion ? 0.18 : max(0.6, Self.dividerDuration - captionDelay)
            do { try await Task.sleep(for:.seconds(remaining)) } catch { return }
            guard !Task.isCancelled else { return }
            entranceComplete = true
            titleFocused = true
        }
        .task(id:exiting) {
            guard exiting else { return }
            // Wait for the final staggered line to leave before retiring the page.
            do { try await Task.sleep(for:.seconds(reduceMotion ? 0.2
                : Self.departureDuration + 2 * Self.departureStagger)) } catch { return }
            guard !Task.isCancelled, active else { return }
            next()
        }
    }

    private func line(_ value: String, index: Int, size: CGFloat, tracking: CGFloat, width: CGFloat) -> some View {
        let revealed = index == 2 ? captionRevealed : revealedRows > index
        return ZStack {
            // Reserve final text metrics while the stable Text changes content.
            Text(value).hidden().accessibilityHidden(true)
            Text(revealed ? value : " ")
                .contentTransition(reduceMotion ? .opacity : .numericText(value:revealed ? 1 : 0))
        }
        // Keep the system wordmark family with an airy welcome-only treatment.
        .font(.system(size:size,weight:index == 1 ? .ultraLight : .light,
                      design:index == 1 ? .default : .monospaced))
        .tracking(tracking)
        .lineLimit(1).minimumScaleFactor(0.55)
        .frame(maxWidth:.infinity)
        .offset(x:exiting && !reduceMotion ? -width-80 : 0)
        .opacity(!exiting ? 1 : 0)
        .animation(reduceMotion ? .easeOut(duration:0.18)
                   : Self.departureAnimation.delay(Double(index)*Self.departureStagger),value:exiting)
        .accessibilityHidden(!revealed || exiting)
    }

    private func divider(width: CGFloat) -> some View {
        let length = min(230,max(0,width-96))
        let revealed = revealedRows > 2
        return Path { path in
            path.move(to:CGPoint(x:0,y:0.5))
            path.addLine(to:CGPoint(x:length,y:0.5))
        }
        .trim(from:reduceMotion || revealed ? 0 : 0.5,
              to:reduceMotion || revealed ? 1 : 0.5)
        .stroke(.white.opacity(0.34),style:StrokeStyle(lineWidth:0.75,lineCap:.round))
        .frame(width:length,height:1)
        // Trim alone reveals the stroke at its final brightness. Fading it too
        // would obscure the first segment of the center-out drawing motion.
        .opacity(reduceMotion && !revealed ? 0 : 1)
        .animation(reduceMotion ? .easeOut(duration:0.18)
                   // Approximate the wordmark's quartic ease-out: fast start,
                   // with most of the remaining time spent gently settling.
                   : .timingCurve(0.25,1,0.5,1,duration:Self.dividerDuration),value:revealed)
        .offset(x:exiting && !reduceMotion ? -width-80 : 0)
        .opacity(!exiting ? 1 : 0)
        .animation(reduceMotion ? .easeOut(duration:0.18)
                   : Self.departureAnimation.delay(1.5*Self.departureStagger),value:exiting)
        .accessibilityHidden(true)
    }

    private func beginExit() {
        guard active, !exiting, entranceComplete else { return }
        titleFocused = false
        exiting = true
        // Start the camera in this same update, retaining the text until it exits.
        beginNext()
    }
}
