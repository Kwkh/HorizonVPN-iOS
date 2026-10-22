import SwiftUI

/// Stable group/member identity and local feedback keep selections from moving the list.
struct NodeGroupSection: View {
    struct Member: Identifiable {
        let id: Int
        let title: String
        let isSelected: Bool
        let isPending: Bool
    }
    let title: String
    let kind: String
    let selectedTitle: String?
    let groupID: Int
    let members: [Member]
    let isExpanded: Bool
    let canCollapse: Bool
    let canSelect: Bool
    let toggle: () -> Void
    let select: (Int) -> Void
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Section {
            if isExpanded {
                ForEach(members) { member in
                    GroupMemberRow(member: member, canSelect: canSelect) { select(member.id) }
                        .accessibilityIdentifier("selection.\(groupID).\(member.id)")
                }
            }
        } header: {
            Button(action: toggle) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        // Use the semantic text color rather than the Section
                        // header's inherited (secondary) foreground hierarchy.
                        Text(title).font(.headline).foregroundStyle(Color.primary)
                        HStack(spacing: 6) {
                            Text(kind)
                            Text("·")
                            Text(selectedTitle ?? settings.text("尚未选择", "No selection"))
                                .contentTransition(.opacity)
                                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: selectedTitle)
                        }.font(.subheadline).foregroundStyle(.secondary)
                    }.lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
                .padding(.top, 16).padding(.bottom, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(GroupSelectionButtonStyle())
            .disabled(!canCollapse)
            .textCase(nil)
            .accessibilityLabel(title)
            .accessibilityValue((isExpanded ? settings.text("已展开", "Expanded") : settings.text("已折叠", "Collapsed")) + ", " + (selectedTitle ?? ""))
            .accessibilityHint(canCollapse ? settings.text("点击展开或折叠策略组", "Tap to expand or collapse the group") : settings.text("搜索时显示匹配节点", "Matching nodes are expanded while searching"))
            .accessibilityIdentifier("selection.group.\(groupID)")
        }
    }
}

private struct GroupMemberRow: View {
    let member: NodeGroupSection.Member
    let canSelect: Bool
    let action: () -> Void
    @State private var showProgress = false
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var emphasized: Bool { member.isSelected || member.isPending }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(member.title)
                    .font(.body.weight(.regular))
                    .foregroundStyle(Color.primary.opacity(emphasized ? 1 : 0.72))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: emphasized)
                Spacer(minLength: 8)
                ZStack {
                    Image(systemName: "checkmark")
                        .opacity(member.isSelected && !showProgress ? 1 : 0)
                    if showProgress { ProgressView().controlSize(.small).transition(.opacity) }
                }
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showProgress)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: member.isSelected)
            }
            // Inset the whole child row, including its selection/progress mark,
            // while keeping the full row available as the tap target.
            .padding(.horizontal, 16)
            .frame(minHeight: 32).contentShape(Rectangle())
        }
        .buttonStyle(GroupSelectionButtonStyle())
        .disabled(!canSelect)
        .accessibilityAddTraits(member.isSelected ? .isSelected : [])
        .accessibilityValue(member.isPending ? settings.text("切换中", "Switching") : member.isSelected ? settings.text("已选择", "Selected") : "")
        .task(id: member.isPending) {
            showProgress = false
            guard member.isPending else { return }
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard !Task.isCancelled else { return }
            showProgress = true
        }
    }
}

/// Preserve readable labels while the controller briefly locks selection.
private struct GroupSelectionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}
