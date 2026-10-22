import Foundation

struct SubscriptionImportPreview: Identifiable {
    let id = UUID()
    let fileName: String?
    let title: String
    let summary: String
    let adaptations: [String]
}
