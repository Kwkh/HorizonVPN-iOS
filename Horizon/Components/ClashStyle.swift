import SwiftUI

enum ClashStyle {
    static let mint = Color(red: 0.38, green: 0.94, blue: 0.80)
    static let blue = Color(red: 0.42, green: 0.62, blue: 1.0)
    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.025, green: 0.036, blue: 0.055) : Color(red: 0.96, green: 0.97, blue: 0.965)
    }
    static func accent(_ scheme: ColorScheme) -> Color { scheme == .dark ? mint : Color(red: 0.02, green: 0.42, blue: 0.34) }
}

struct ClashScreen: ViewModifier {
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.scrollContentBackground(.hidden)
            .background(settings.isHorizon ? .black : ClashStyle.background(scheme))
            .tint(settings.isHorizon ? .white : ClashStyle.accent(scheme))
    }
}
struct ClashTint: ViewModifier {
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View { content.tint(settings.isHorizon ? .white : ClashStyle.accent(scheme)) }
}
extension View {
    func clashScreen() -> some View { modifier(ClashScreen()) }
    func clashTint() -> some View { modifier(ClashTint()) }
}
