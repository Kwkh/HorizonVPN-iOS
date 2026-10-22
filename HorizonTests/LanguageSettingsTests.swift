import Foundation
import Testing
@testable import Horizon

struct LanguageSettingsTests {
    @Test @MainActor func freshInstallFollowsSystemAndPreservesExplicitChoice() throws {
        let suite = "Horizon.LanguageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.language == .system)
        #expect(settings.isChinese == (Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true))
        settings.language = .english
        #expect(!AppSettings(defaults: defaults).isChinese)
        settings.language = .chinese
        #expect(AppSettings(defaults: defaults).isChinese)
    }

    @Test func installationDeclaresBothManuallyManagedLanguages() {
        let localizations = Bundle.main.localizations
        #expect(localizations.contains("zh-Hans"))
        #expect(localizations.contains("en"))
        #expect(Bundle.preferredLocalizations(from: localizations, forPreferences: ["zh-Hans-CN", "en"]).first == "zh-Hans")
        #expect(Bundle.preferredLocalizations(from: localizations, forPreferences: ["en-US", "zh-Hans"]).first == "en")
    }
}
