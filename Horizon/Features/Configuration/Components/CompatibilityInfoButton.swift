import SwiftUI

struct CompatibilityInfoButton: View {
    let report: ConfigurationCompatibility?
    var isLoading = false
    var onPresentationChange: (Bool) -> Void = { _ in }
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showing = false
    @State private var showProgress = false

    var body: some View {
        Button { showing = true } label: {
            // Keep one toolbar button and one footprint throughout navigation/loading.
            ZStack {
                Image(systemName: "info.circle").opacity(showProgress ? 0 : 1)
                if showProgress {
                    ProgressView().controlSize(.small).transition(.opacity)
                }
            }
            .frame(width: 44, height: 44)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showProgress)
        }
        .disabled(isLoading)
        .accessibilityLabel(isLoading
            ? settings.text("正在检查配置", "Checking configuration")
            : settings.text("兼容性诊断与说明", "Compatibility & information"))
        .sheet(isPresented: $showing) { ConfigurationCompatibilityView(report: report) }
        .onChange(of: showing) { _, value in onPresentationChange(value) }
        .task(id: isLoading) {
            guard isLoading else { showProgress = false; return }
            // Cached/quick reports must not flash a spinner during the push transition.
            do { try await Task.sleep(for: .milliseconds(200)) }
            catch { return }
            guard !Task.isCancelled else { return }
            showProgress = true
        }
    }
}
