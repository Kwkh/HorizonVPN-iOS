import SwiftUI

struct SettingsView: View {
    let tunnel: TunnelController
    var replayIntroduction: (() -> Void)? = nil
    @Environment(AppSettings.self) private var settings
    @Environment(VPNLiveActivityController.self) private var liveActivity
    var body: some View {
        @Bindable var preferences = settings
        List {
            ClashListContent {
                Section(settings.text("外观", "Appearance")) {
                    NavigationLink { InterfaceStyleSettingsView() } label: {
                        LabeledContent {
                            Text(settings.isHorizon ? settings.text("Horizon", "Horizon") : settings.text("经典", "Classic"))
                                .foregroundStyle(.secondary)
                        } label: { Label(settings.text("界面风格", "Interface style"), systemImage: "square.stack.3d.up") }
                    }
                    if !settings.isHorizon {
                    Picker(selection: $preferences.appearance) {
                        Text(settings.text("深色", "Dark")).tag(AppSettings.Appearance.dark)
                        Text(settings.text("浅色", "Light")).tag(AppSettings.Appearance.light)
                        Text(settings.text("跟随系统", "System")).tag(AppSettings.Appearance.system)
                    } label: { Label(settings.text("显示模式", "Theme"), systemImage: "circle.lefthalf.filled") }
                    .pickerStyle(.menu)
                    }
                    if settings.isHorizon {
                        SceneScaleControl(title: settings.text("砖块大小", "Brick size"), symbol: "rectangle.split.3x3",
                            value: $preferences.brickScale, range: 1...3, identifier: "settings.brickScale")
                        SceneScaleControl(title: settings.text("地球大小", "Globe size"), symbol: "globe.asia.australia",
                            value: $preferences.globeScale, range: 1...2, identifier: "settings.globeScale")
                        if let replayIntroduction {
                            Button(action: replayIntroduction) {
                                Label(settings.text("重播首次入场", "Replay introduction"), systemImage: "play.circle")
                            }.accessibilityIdentifier("settings.replayIntroduction")
                        }
                    }
                    Toggle(isOn: $preferences.particles) {
                        Label(settings.text("粒子动效", "Particle motion"), systemImage: "sparkles")
                    }
                    .tint(Color(uiColor: .systemGreen))
                    NavigationLink { LanguageSettingsView() } label: {
                        Label(settings.text("语言", "Language"), systemImage: "globe")
                    }
                }.listRowBackground(Color.clear)
                Section(settings.text("连接", "Connection")) {
                    NavigationLink { RoutingSettingsView(tunnel: tunnel) } label: {
                        Label(settings.text("分流方案", "Routing"), systemImage: "arrow.triangle.branch")
                    }
                    Toggle(isOn: $preferences.confirmVPNConnection) {
                        Label(settings.text("连接前确认", "Confirm before connecting"), systemImage: "checkmark.shield")
                    }
                    .tint(Color(uiColor: .systemGreen))
                    .accessibilityIdentifier("settings.confirmVPNConnection")
                }.listRowBackground(Color.clear)
                Section(settings.text("工具", "Tools")) {
                    NavigationLink { ICloudSubscriptionSyncView(tunnel: tunnel) } label: {
                        Label(settings.text("iCloud 同步", "iCloud sync"), systemImage: "icloud")
                    }
                    NavigationLink { PingTestView(tunnel: tunnel) } label: {
                        Label(settings.text("测速", "Ping Test"), systemImage: "waveform.path.ecg")
                    }
                    NavigationLink { DiagnosticsView(tunnel: tunnel, managedExternally: true) } label: {
                        Label(settings.text("诊断与维护", "Diagnostics"), systemImage: "stethoscope")
                    }
                    NavigationLink { AboutView() } label: {
                        Label(settings.text("关于", "About"), systemImage: "info.circle")
                    }
                }.listRowBackground(Color.clear)
                Section {
                    Toggle(settings.text("显示节点原名", "Original node names"), isOn: $preferences.showOriginalNames)
                        .tint(Color(uiColor: .systemGreen))
                }.listRowBackground(Color.clear)
                Section {
                    Toggle(isOn: $preferences.liveActivityEnabled) {
                        Label(settings.text("灵动岛", "Dynamic Island"), systemImage: "platter.filled.top.iphone")
                    }.tint(Color(uiColor: .systemGreen))
                        .accessibilityIdentifier("settings.liveActivity")
                    if liveActivity.unavailable {
                        Text(settings.text("实时活动暂不可用，请检查系统设置。", "Live Activities unavailable. Check system settings."))
                            .foregroundStyle(.secondary)
                    }

                }.listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain).clashScreen()
        .navigationTitle(settings.text("设置", "Settings"))
    }
}
