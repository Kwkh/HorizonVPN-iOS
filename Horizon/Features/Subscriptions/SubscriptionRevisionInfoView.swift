import SwiftUI

struct SubscriptionRevisionInfoView: View {
    let review: SubscriptionMaintenanceStore.Review
    @State private var showingCompatibility = false
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ClashListContent {
                    Section(settings.text("完整变化", "All changes")) {
                        ForEach(review.changes, id: \.self) { Text(settings.text($0, DiagnosticText.importEnglish($0))).listRowSeparator(.hidden) }
                    }.listRowBackground(Color.clear)
                    Section(settings.text("分流检查", "Routing checks")) {
                        ForEach(review.assessment.explanations(english: !settings.isChinese), id: \.self) { Text($0).listRowSeparator(.hidden) }
                    }.listRowBackground(Color.clear)
                    Section {
                        Label(settings.text("上一版本可回滚", "Previous revision can be restored"), systemImage: "clock.arrow.circlepath")
                        Button(settings.text("兼容性诊断", "Compatibility")) { showingCompatibility = true }
                    }.listRowBackground(Color.clear)
                }
            }.listStyle(.plain).clashScreen()
                .navigationTitle(settings.text("更新详情", "Update details"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(settings.text("完成", "Done")) { dismiss() } } }
        }.clashTint()
            .sheet(isPresented: $showingCompatibility) { ConfigurationCompatibilityView(report: review.report) }
    }
}
