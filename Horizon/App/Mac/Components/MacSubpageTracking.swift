#if os(macOS)
import SwiftUI

private struct MacSubpageTokensKey: EnvironmentKey {
    static let defaultValue: Binding<Set<UUID>>? = nil
}

extension EnvironmentValues {
    var macSubpageTokens: Binding<Set<UUID>>? {
        get { self[MacSubpageTokensKey.self] }
        set { self[MacSubpageTokensKey.self] = newValue }
    }
}

/// Reports pushed content without owning or replacing its native navigation path.
/// Tokens allow nested destinations to appear/disappear in either callback order.
struct MacSubpageTracking: ViewModifier {
    // Capture at the NavigationLink site; native destinations have a separate environment.
    let tokens: Binding<Set<UUID>>?
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .environment(\.macSubpageTokens, tokens)
            .onAppear { tokens?.wrappedValue.insert(token) }
            .onDisappear { tokens?.wrappedValue.remove(token) }
    }
}
#endif
