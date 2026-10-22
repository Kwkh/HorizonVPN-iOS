import SwiftUI

struct NetworkUnavailableAlert: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(AppSettings.self) private var settings

    func body(content: Content) -> some View {
        content.alert(settings.text("无网络连接", "No network connection"), isPresented: $isPresented) {
            Button(settings.text("好", "OK"), role: .cancel) { }
        } message: {
            Text(settings.text("请检查 Wi-Fi 或蜂窝数据。", "Check Wi-Fi or cellular data."))
        }
    }
}
