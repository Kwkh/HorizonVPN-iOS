#if os(macOS)
import SwiftUI

struct MacSettingsView: View {
    @Environment(\.macSubpageTokens) private var subpageTokens
    let library: MacLibraryStore
    let replayIntroduction: () -> Void
    @Environment(AppSettings.self) private var settings
    var body: some View {
        @Bindable var settings = settings
        Form {
            Section(settings.text("界面", "Interface")) {
                Picker(settings.text("语言", "Language"), selection: $settings.language) {
                    Text(settings.text("跟随系统", "System")).tag(AppSettings.Language.system)
                    Text("简体中文").tag(AppSettings.Language.chinese)
                    Text("English").tag(AppSettings.Language.english)
                }
                Toggle(settings.text("粒子动态效果", "Particle motion"), isOn: $settings.particles)
                Toggle(settings.text("显示原始节点名称", "Show original node names"), isOn: $settings.showOriginalNames)
                LabeledContent(settings.text("砖块大小", "Brick size")) {
                    Slider(value: $settings.brickScale, in: 1...3, step: 0.1).frame(width: 180)
                    Text(settings.brickScale, format: .number.precision(.fractionLength(1))).monospacedDigit().frame(width: 35)
                }
                LabeledContent(settings.text("地球大小", "Globe size")) {
                    Slider(value: $settings.globeScale, in: 1...2, step: 0.1).frame(width: 180)
                    Text(settings.globeScale, format: .number.precision(.fractionLength(1))).monospacedDigit().frame(width: 35)
                }
                Button(settings.text("重播入场动画", "Replay introduction"), action: replayIntroduction)
            }
            Section(settings.text("连接与流量", "Connection & traffic")) {
                Toggle(settings.text("连接前确认", "Confirm before connecting"), isOn: $settings.confirmVPNConnection)
                Picker(settings.text("流量曲线", "Traffic curve"), selection: $settings.trafficMapping) {
                    Text(settings.text("对数", "Logarithmic")).tag(AppSettings.TrafficMapping.logarithmic)
                    Text(settings.text("线性", "Linear")).tag(AppSettings.TrafficMapping.linear)
                }
                if settings.trafficMapping == .linear {
                    Picker(settings.text("量程", "Scale"), selection: $settings.trafficScale) { ForEach(AppSettings.TrafficScale.allCases, id: \.self) { Text($0.label).tag($0) } }
                }
            }
            Section(settings.text("订阅", "Subscriptions")) {
                NavigationLink { MacICloudSubscriptionSyncView(library: library).modifier(MacSubpageTracking(tokens: subpageTokens)) } label: {
                    Label(settings.text("iCloud 同步", "iCloud sync"), systemImage: "icloud")
                }
                .accessibilityIdentifier("settings.icloud")
            }
            Section {
                NavigationLink(settings.text("关于 HORIZON", "About HORIZON")) { MacAboutView().modifier(MacSubpageTracking(tokens: subpageTokens)) }
            }
        }.formStyle(.grouped).scrollContentBackground(.hidden).background(.black)
            .navigationTitle(settings.text("设置", "Settings"))
    }
}
#endif
