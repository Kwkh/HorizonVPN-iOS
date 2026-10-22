import SwiftUI

struct RoutingSettingsView: View {
    let tunnel: TunnelController
    @Environment(AppSettings.self) private var settings
    var body: some View {
        Group {
            if let id = tunnel.activeSubscriptionID {
                SubscriptionRoutingView(tunnel: tunnel, id: id).id(id)
            } else {
                ContentUnavailableView(settings.text("请先选择订阅", "Select a configuration first"), systemImage: "square.stack.3d.up")
                    .clashScreen()
            }
        }.navigationTitle(settings.text("分流方案", "Routing"))
    }
}
