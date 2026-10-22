#if DEBUG
import SwiftUI

/// Explicitly opt-in visual harness. It never calls TunnelController or starts VPN.
struct HorizonScenePreviewView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: HorizonMotion.Phase = .idle
    private var statusTitle: String {
        switch phase {
        case .idle: "Disconnected"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .recovering: "Reconnecting"
        case .disconnecting: "Disconnecting"
        }
    }
    @State private var sceneProgress = HorizonSceneProgress()
    @State private var stoppingTask: Task<Void, Never>?
    @State private var refreshing = false
    private var unavailable: Bool {
        ProcessInfo.processInfo.environment["CLASH_BUTTON_UNAVAILABLE"] == "1"
    }

    private var buttonAction: HorizonConnectionButton.Action {
        switch phase {
        case .idle: .connect
        case .connecting: .cancel
        case .disconnecting: .stopping
        case .connected, .recovering: .disconnect
        }
    }

    private func togglePreviewConnection() {
        guard phase != .disconnecting else { return }
        if phase == .idle { phase = .connected; return }
        phase = .disconnecting
        stoppingTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(80)) }
            catch { return }
            phase = .idle
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("3D 预览 · 虚构状态 · 无网络请求").font(.callout).padding()
            if ProcessInfo.processInfo.environment["CLASH_HORIZON_SLOW_TEXT"] == "1" {
                HStack {
                    Text("原生数字对照").font(.caption)
                    Text("\(phase == .connected ? 2 : phase == .connecting ? 1 : 0)")
                        .font(.title)
                        .contentTransition(.numericText())
                        .animation(.linear(duration: 3.25), value: phase)
                        .frame(width: 60)
                    Text(reduceMotion ? "Reduced" : "Motion")
                        .font(.caption)
                }
            }
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        ZStack(alignment: .top) {
                            HorizonSceneView(progress: sceneProgress, phase: phase, active: scenePhase == .active, animate: !reduceMotion)
                            HorizonTitleView(status: statusTitle, progress: sceneProgress,
                                viewport: geometry.size)
                            VStack {
                                Spacer()
                                GlassEffectContainer {
                                    HorizonConnectionButton(action: buttonAction, disabled: refreshing || unavailable,
                                                            unavailable: unavailable,
                                                            onTap: togglePreviewConnection)
                                }
                                Image(systemName: "chevron.compact.down").font(.title3)
                                    .frame(width: 60, height: 44).padding(.top, 8)
                            }.padding(.bottom, 22)
                        }.frame(height: geometry.size.height)
                        Text("滚动验证区域 · 不操作网络").frame(maxWidth: .infinity).frame(height: 260)
                    }
                }
                .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y > 30 } action: { _, revealed in
                    print("HORIZON_PREVIEW_SCROLLED", revealed)
                }
            }
            HStack {
                Button("连接中") { phase = .connecting }
                Button("成功") { phase = .connected }
                Button("恢复") { phase = .recovering }
                Button("断开 / 失败") { phase = .idle }
            }.buttonStyle(.glass).padding()
        }.background(.black).foregroundStyle(.white).tint(.white).preferredColorScheme(.dark)
            .onDisappear { stoppingTask?.cancel() }
            .task {
                guard ProcessInfo.processInfo.environment["CLASH_BUTTON_STARTUP_AUDIT"] == "1" else { return }
                // Reproduce an overlapping foreground refresh without system VPN access.
                refreshing = true
                do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
                refreshing = false
            }
    }
}
#endif
