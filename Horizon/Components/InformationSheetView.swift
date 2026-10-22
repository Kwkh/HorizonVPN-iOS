import SwiftUI

struct InformationSheetView: View {
    let title: String
    let paragraphs: [String]
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(paragraphs.indices, id: \.self) { index in
                        Text(paragraphs[index]).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.body).textSelection(.enabled).padding(24)
            }
            .clashScreen()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(settings.text("完成", "Done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
