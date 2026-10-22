import SwiftUI

/// A neutral first-load surface; don't stage a fake disconnected home before reading iOS.
struct StartupView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme
    @State private var showProgress = false

    var body: some View {
        ZStack {
            (settings.isHorizon ? Color.black : ClashStyle.background(scheme)).ignoresSafeArea()
            if showProgress {
                ProgressView(settings.text("正在读取状态", "Reading status"))
                    .tint(settings.isHorizon ? .white : ClashStyle.accent(scheme))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            // No artificial minimum launch delay. Only slow reads need a visible indicator.
            do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
            showProgress = true
        }
    }
}
