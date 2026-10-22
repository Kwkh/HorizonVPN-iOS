import SwiftUI

/// A compact, accessible entry point for optional explanations shared by feature pages.
struct InformationButton: View {
    let title: String
    let paragraphs: [String]
    @State private var presented = false

    var body: some View {
        Button { presented = true } label: {
            Image(systemName: "info.circle").frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
        .accessibilityIdentifier("info.\(title)")
        .sheet(isPresented: $presented) {
            InformationSheetView(title: title, paragraphs: paragraphs)
        }
    }
}
