import SwiftUI

struct InterfaceStyleSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        List {
            ClashListContent {
                ForEach(AppSettings.InterfaceStyle.allCases, id: \.self) { style in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { settings.interfaceStyle = style }
                    } label: {
                        HStack(spacing: 18) {
                            Image(systemName: style == .classic ? "circle.hexagongrid" : "globe.europe.africa")
                                .font(.title2).frame(width: 32)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(style == .classic ? settings.text("经典", "Classic") : settings.text("Horizon", "Horizon"))
                                    .font(.title3)
                                Text(style == .classic ? settings.text("经典VPN布局", "Classic VPN layout") : settings.text("专为Horizon设计", "Designed for Horizon"))
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if settings.interfaceStyle == style { Image(systemName: "checkmark") }
                        }.padding(.vertical, 14).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).listRowBackground(Color.clear)
                    .accessibilityAddTraits(settings.interfaceStyle == style ? .isSelected : [])
                    .accessibilityIdentifier("style.\(style.rawValue)")
                }
            }
        }.listStyle(.plain).clashScreen()
            .navigationTitle(settings.text("界面风格", "Interface style"))
    }
}
