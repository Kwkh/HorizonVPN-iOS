#if os(macOS)
import AppKit
import SwiftUI

struct MacMenuBarLabel: View {
    let actions: MacMenuBarActions
    @Environment(AppSettings.self) private var settings

    private var connected: Bool {
        actions.library.vpn.status == .connected
    }

    var body: some View {
        let _ = settings.language
        let icon = connected ? Icons.connected : Icons.disconnected

        Group {
            if let icon {
                Image(nsImage: icon)
                    .renderingMode(.template)
            } else {
                Image(systemName: connected
                      ? "globe.europe.africa.fill"
                      : "globe.europe.africa")
            }
        }
        .accessibilityLabel("Horizon · " + actions.statusTitle)
        .help("Horizon · " + actions.statusTitle)
    }

    @MainActor
    private enum Icons {
        // 主要调节这里，先尝试 19，再比较 20。
        private static let iconHeight: CGFloat = 13

        static let disconnected = make("globe.europe.africa")
        static let connected = make("globe.europe.africa.fill")

        private static func make(_ name: String) -> NSImage? {
            guard let symbol = NSImage(
                systemSymbolName: name,
                accessibilityDescription: nil
            ) else {
                return nil
            }

            let configuration = NSImage.SymbolConfiguration(
                pointSize: iconHeight,
                weight: .medium,
                scale: .large
            )

            let configured =
                symbol.withSymbolConfiguration(configuration) ?? symbol

            guard let image = configured.copy() as? NSImage,
                  image.size.height > 0 else {
                return nil
            }

            // 保留纵横比，避免直接拉伸成正方形。
            let ratio = image.size.width / image.size.height
            image.size = NSSize(
                width: iconHeight * ratio,
                height: iconHeight
            )
            image.isTemplate = true
            return image
        }
    }
}
#endif
