#if os(macOS)
import SwiftUI

struct MacAboutView: View {
    @Environment(AppSettings.self) private var settings
    var body: some View {
        VStack(spacing: 28) {
            Text("H O R I Z O N").font(.system(size: 38, weight: .ultraLight)).tracking(1.5)
            Text(settings.text("适用于 macOS 的个人代理客户端", "A personal proxy client for macOS")).foregroundStyle(.secondary)
            Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))").font(.caption).foregroundStyle(.secondary)
            Text(settings.text("基于 Clash / Mihomo 兼容内核。许可证随 App 一并提供。", "Powered by a Clash / Mihomo compatible core. Licenses are included with the app.")).font(.callout).foregroundStyle(.secondary)
            if let url = Bundle.main.url(forResource: "CoreLicenses", withExtension: nil) { Button(settings.text("开源许可证", "Open-source licenses")) { NSWorkspace.shared.open(url) } }
        }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
            .navigationTitle(settings.text("关于", "About"))
    }
}
#endif
