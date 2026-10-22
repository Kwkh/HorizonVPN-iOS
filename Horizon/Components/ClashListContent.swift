import SwiftUI

/// Apply one separator treatment to native List and Form rows, including rows
/// supplied by feature components. Keep SwiftUI's section and subview identities.
struct ClashListContent<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var separatorColor: Color {
        .primary.opacity(contrast == .increased ? 0.35 : (scheme == .dark ? 0.14 : 0.17))
    }

    var body: some View {
        ForEach(sections: content) { section in
            Section {
                ForEach(subviews: section.content) { row in
                    row
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .alignmentGuide(.listRowSeparatorLeading) { dimensions in
                            max(dimensions[.leading] + 8, dimensions[.listRowSeparatorLeading])
                        }
                        .alignmentGuide(.listRowSeparatorTrailing) { dimensions in
                            dimensions[.trailing] - 8
                        }
                        .listRowSeparatorTint(separatorColor)
                }
            } header: {
                section.header
            } footer: {
                section.footer
            }
            .listSectionSeparator(.hidden)
        }
    }
}
