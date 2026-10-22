#if os(macOS)
import Foundation

nonisolated enum MacText {
    static var isChinese: Bool {
        switch UserDefaults.standard.string(forKey: "ui.language") {
        case "chinese": true
        case "english": false
        default: Locale.preferredLanguages.first?.hasPrefix("zh") == true
        }
    }
    static func value(_ chinese: String, _ english: String) -> String { isChinese ? chinese : english }
    static func error(_ error: Error) -> String {
        if let failure = error as? MacVPNFailure { return failure.summary }
        if let failure = error as? SubscriptionDownloader.Failure {
            return isChinese ? failure.safeReason : failure.englishReason
        }
        if let failure = error as? SubscriptionError {
            if isChinese { return failure.summary }
            switch failure {
            case .staleRevision: return "This configuration changed. Open a new preview and try again."
            case .invalidTitle: return "Enter a valid configuration name."
            case .missingEntry: return "This configuration no longer exists. Refresh the list."
            case .tooMany: return "You can save up to 128 configurations."
            default: return "The saved configuration could not be updated. Your data is retained."
            }
        }
        if isChinese, let issue = error as? ConfigurationIssue { return issue.detail }
        if let failure = error as? PrototypeError {
            if isChinese { return failure.summary }
            switch failure {
            case .keychain: return "Cannot access the shared Keychain. Check the Mac signing configuration."
            case .certificateConsent: return "Confirm the certificate setting before connecting."
            case .missingConfiguration: return "Import and select a configuration first."
            default: return "The operation could not complete. Your saved configuration is retained."
            }
        }
        return value("操作未完成，现有订阅已保留。请检查配置或系统权限后重试。", "The operation could not complete. Check the configuration or system permissions and try again. Your saved subscriptions are retained.")
    }
}

#endif
