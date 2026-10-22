#if os(macOS)
import SwiftUI

struct MacHomeView: View {
    let library: MacLibraryStore
    var visible = true
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var progress = HorizonSceneProgress()
    @State private var confirmConnection = false
    @State private var connectionButtonFrame = CGRect.null
    private var phase: HorizonMotion.Phase {
        if library.vpn.working && library.vpn.isIdle { return .connecting }
        return switch library.vpn.status { case .connected: .connected; case .connecting: .connecting; case .reasserting: .recovering; case .disconnecting: .disconnecting; default: .idle }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 0) {
                    VStack(spacing: 16) {
                        Text("H O R I Z O N").font(.system(size: 14, weight: .light)).tracking(1.5).padding(.leading, -1.5).foregroundStyle(.secondary)
                        MacConnectionTitleView(library: library, progress: progress)
                    }.padding(.top, 34).padding(.bottom, 18)
                    ZStack(alignment: .bottom) {
                        MacMetalScene(phase: phase, progress: progress, active: visible && scenePhase == .active,
                            animate: settings.particles && !reduceMotion,
                            brickScale: Float(settings.brickScale), globeScale: Float(settings.globeScale),
                            homeGlobeFraming: true,
                            wallHoverEnabled: true, wallExclusion: connectionButtonFrame)
                            .frame(height: 360)
                        MacConnectionButtonView(idle: library.vpn.isIdle,
                            unavailable: library.offline || library.prepared == nil,
                            enabled: library.pendingRouting == nil && !library.busy && !library.vpn.working && library.vpn.status != .disconnecting,
                            frameChanged: { connectionButtonFrame = $0 }) {
                            if library.vpn.isIdle {
                                if settings.confirmVPNConnection { confirmConnection = true }
                                else { Task { await library.connect() } }
                            } else { library.vpn.disconnect() }
                        }
                            .padding(.bottom, 24)
                    }
                    .coordinateSpace(name: "mac.home.scene")
                }
                VStack(alignment: .leading, spacing: 25) {
                    MacTrafficChart(telemetry: library.telemetry, active: visible && scenePhase == .active)
                    Divider()
                    MacRoutingPickerView(library: library)
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(settings.text("当前订阅", "Subscription")).font(.caption).foregroundStyle(.secondary)
                            Text(library.activeTitle).font(.title3)
                        }
                        Spacer()
                        if let catalog = library.prepared?.catalog, let name = catalog.resolvedTarget(runtimeChoices: library.runtimeChoices), let index = catalog.nodes.firstIndex(where: { $0.name == name }) {
                            MacHomePingView(probes: library.probes, index: index,
                                enabled: !library.offline, visible: visible && scenePhase == .active) {
                                Task { await library.test([index]) }
                            }
                        }
                    }
                }.frame(maxWidth: 760).padding(.horizontal, 36).padding(.bottom, 36)
            }
        }.background(.black)
        .alert(settings.text("连接 Horizon？", "Connect Horizon?"), isPresented: $confirmConnection) {
            Button(settings.text("取消", "Cancel"), role: .cancel) {}
            Button(settings.text("连接", "Connect")) { Task { await library.connect() } }
        } message: { Text(settings.text("Horizon 将使用当前订阅建立 VPN 连接。", "Horizon will establish a VPN connection using your selected configuration.")) }
    }
}
#endif
