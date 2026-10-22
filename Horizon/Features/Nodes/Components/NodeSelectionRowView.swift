import SwiftUI

/// Fixed row geometry, with feedback isolated from the list and traffic sampling.
struct NodeSelectionRowView: View {
    let number: Int
    let title: String
    let protocolName: String
    let isSelected: Bool
    let isPending: Bool
    let isEnabled: Bool
    let action: () -> Void
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progressReady = false

    private enum Indicator: Equatable { case empty, waiting, selected }
    private var indicator: Indicator {
        if isPending && progressReady { return .waiting }
        return isSelected ? .selected : .empty
    }
    // Pending feedback begins on a normal tap and continues into confirmed selection.
    // Only the confirmed state controls the checkmark and selected accessibility trait.
    private var isEmphasized: Bool { isSelected || isPending }
    private var selectionAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.36)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Text(String(format: "%02d", number)).font(.title3.monospaced())
                    .foregroundStyle(Color.primary.opacity(isEmphasized ? 0.9 : 0.45))
                    .animation(selectionAnimation, value: isEmphasized)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline)
                        .foregroundStyle(Color.primary.opacity(isEmphasized ? 1 : 0.72))
                    Text(protocolName).font(.callout)
                        .foregroundStyle(Color.primary.opacity(isEmphasized ? 0.8 : 0.5))
                }
                .animation(selectionAnimation, value: isEmphasized)
                Spacer()
                ZStack {
                    if indicator == .selected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                            .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn.byLayer)))
                    }
                    if indicator == .waiting { ProgressView().transition(.opacity) }
                }
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: indicator)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        // Keep disabled accessibility/interaction semantics without dimming every row
        // whenever the controller briefly sets isBusy during a selection transaction.
        .buttonStyle(NodeSelectionButtonStyle())
        .disabled(!isEnabled)
        .accessibilityIdentifier("nodes.select.\(number - 1)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isPending ? settings.text("切换中", "Switching") : isSelected ? settings.text("已选择", "Selected") : "")
        .task(id: isPending) {
            progressReady = false
            guard isPending else { return }
            do { try await Task.sleep(for: .milliseconds(150)) }
            catch { return }
            guard !Task.isCancelled else { return }
            progressReady = true
        }
    }
}

private struct NodeSelectionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
