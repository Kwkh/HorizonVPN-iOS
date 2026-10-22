import SwiftUI

/// Only tablet feature pages opt in; shrinking a window changes columns, not view identity.
struct TabletCardGrid<Header: View, Content: View>: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content

    static func columnCount(width: CGFloat, accessibility: Bool) -> Int {
        accessibility ? 1 : max(1, Int((max(0, width - 48) + 16) / 316))
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header()
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 16, alignment: .top),
                        count: Self.columnCount(width: geometry.size.width, accessibility: textSize.isAccessibilitySize)), spacing: 16) {
                        content()
                    }
                }.padding(24)
            }
        }
    }
}

struct TabletCardStyle: ViewModifier {
    let selected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(selected ? 0.45 : 0.12), lineWidth: 1) }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: selected)
    }
}
