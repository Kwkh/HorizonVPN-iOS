import SwiftUI

struct AboutView: View {
    @Environment(AppSettings.self) private var settings
    @ScaledMetric(relativeTo: .largeTitle) private var brandSize: CGFloat = 46
    var body: some View {
        List {
            ClashListContent {
                Section {
                    Text("H O R I Z O N")
                        .font(.system(size: brandSize, weight: .ultraLight, design: .default))
                        .tracking(1.5)
                        .lineLimit(1).minimumScaleFactor(0.55)
                        .padding(.vertical, 18)
                        .accessibilityLabel("HORIZON")
                        .listRowSeparator(.hidden)
                    LabeledContent(settings.text("版本", "Version"), value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                        .listRowSeparator(.hidden)
                    LabeledContent(settings.text("构建", "Build"), value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")
                        .listRowSeparator(.hidden)
                    LabeledContent(settings.text("内核", "Core"), value: "Hako · 9437767")
                        .listRowSeparator(.hidden)
                    Text("GPL-3.0 · Hako / Hako-Adapter").foregroundStyle(.secondary)
                    Link(settings.text("内核源码与许可证", "Core source & license"), destination: URL(string: "https://github.com/TokenPLS/Hako/tree/9437767346a63957c60bf027b6d9fb27e51d89c4")!)
                    Link("Hako-Adapter", destination: URL(string: "https://github.com/TokenPLS/Hako-Adapter/tree/6a47cf91350ab80024e9bb4003264dd01100bdbd")!)
                    Link(settings.text("Natural Earth · 公共领域", "Natural Earth · Public domain"), destination: URL(string: "https://www.naturalearthdata.com/about/terms-of-use/")!)
                    Link(settings.text("Geo 数据 · MetaCubeX · GPL-3.0", "Geo data · MetaCubeX · GPL-3.0"), destination: URL(string: "https://github.com/MetaCubeX/meta-rules-dat")!)
                }.listRowBackground(Color.clear)
            }
        }.listStyle(.plain).clashScreen().navigationTitle(settings.text("关于", "About"))
    }
}
