import SwiftUI
import UniformTypeIdentifiers

/// A single presentation owner for drops anywhere in the iPad workspace.
struct TabletFileImportModifier: ViewModifier {
    let tunnel: TunnelController
    let enabled: Bool
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cloudReviewPromptBlocked) private var reviewPromptBlocked
    @State private var targeted = false
    @State private var loading = false
    @State private var preview: SubscriptionImportPreview?
    @State private var error: String?

    private var acceptsDrop: Bool {
        enabled && !loading && preview == nil && tunnel.importPreview == nil && tunnel.canManageSubscriptions
    }

    func body(content: Content) -> some View {
        content
            .environment(\.cloudReviewPromptBlocked, reviewPromptBlocked || targeted || loading || preview != nil || error != nil)
            .onDrop(of: [UTType.data], isTargeted: $targeted, perform: receive)
            .overlay {
                if targeted && acceptsDrop {
                    RoundedRectangle(cornerRadius: 22).strokeBorder(.primary.opacity(0.5), lineWidth: 2)
                        .padding(10).allowsHitTesting(false)
                }
            }
            .overlay(alignment: .top) {
                if (targeted && acceptsDrop) || loading {
                    HStack(spacing: 10) {
                        if loading { ProgressView() }
                        else { Image(systemName: "square.and.arrow.down") }
                        Text(loading ? settings.text("正在导入…", "Importing…") : settings.text("松开以导入配置文件", "Drop to import configuration"))
                    }
                    .padding(.horizontal, 20).padding(.vertical, 14)
                    .glassEffect().padding(.top, 12)
                    .allowsHitTesting(false).transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: targeted && acceptsDrop)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: loading)
            .sheet(item: $preview, onDismiss: { tunnel.cancelImport() }) { value in
                ImportConfirmationView(tunnel: tunnel, preview: value)
            }
            .alert(settings.text("无法导入", "Could not import"), isPresented: Binding(
                get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(settings.text("好", "OK"), role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
    }

    private func receive(_ providers: [NSItemProvider]) -> Bool {
        guard acceptsDrop else { return false }
        guard providers.count == 1, let provider = providers.first else {
            error = settings.text("请一次拖入一份配置文件。", "Drop one configuration file at a time.")
            return true
        }
        loading = true
        Task {
            defer { loading = false }
            do {
                let file = try await DroppedConfigurationFile.load(provider)
                defer { file.remove() }
                // Another import or library action may have started while Files was loading.
                guard enabled, tunnel.canManageSubscriptions, tunnel.importPreview == nil else {
                    error = settings.text("请完成当前操作后再拖入文件。", "Finish the current operation, then drop the file again.")
                    return
                }
                if await tunnel.prepareImport(file.url), let value = tunnel.importPreview { preview = value }
                else { error = settings.text(tunnel.message, DiagnosticText.importEnglish(tunnel.message)) + "\n" + settings.text("请尝试导入标准 Clash 配置。", "Try importing a standard Clash configuration.") }
            } catch DroppedConfigurationFile.Failure.tooLarge {
                error = settings.text("文件过大，请使用不超过 1 MB 的配置文件。", "Use a configuration file no larger than 1 MB.")
            } catch {
                self.error = settings.text("无法读取文件，请先在“文件”中下载到本机，再重试。", "Could not read the file. Download it in Files, then try again.")
            }
        }
        return true
    }
}
