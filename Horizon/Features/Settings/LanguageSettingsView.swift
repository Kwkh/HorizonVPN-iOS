import SwiftUI

struct LanguageSettingsView: View {
    @Environment(AppSettings.self) private var settings
    var body: some View {
        List {
            ClashListContent {
                row(.system, title: settings.text("跟随系统", "System default"))
                row(.chinese, title: "简体中文")
                row(.english, title: "English")
            }
        }.listStyle(.plain).clashScreen()
            .navigationTitle(settings.text("语言", "Language"))
    }
    private func row(_ language: AppSettings.Language, title: String) -> some View {
        Button { settings.language = language } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if settings.language == language { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }.padding(.vertical, 10)
        }.listRowBackground(Color.clear)
            .accessibilityAddTraits(settings.language == language ? .isSelected : [])
    }
}
