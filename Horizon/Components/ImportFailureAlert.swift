import SwiftUI

/// Keep the first failure message short; sanitized diagnostics remain available on demand.
private struct ImportFailureAlert: ViewModifier {
    @Binding var isPresented: Bool
    let detail: String
    @Environment(AppSettings.self) private var settings
    @State private var showingDetail = false

    func body(content: Content) -> some View {
        content
            .alert(settings.text("导入失败", "Import failed"), isPresented: $isPresented) {
                Button(settings.text("查看原因", "Details")) { showingDetail = true }
                Button(settings.text("好", "OK"), role: .cancel) { }
            } message: {
                Text(settings.text("请尝试导入标准 Clash / Mihomo 格式的订阅。", "Try importing a standard Clash / Mihomo subscription."))
            }
            .sheet(isPresented: $showingDetail) {
                InformationSheetView(
                    title: settings.text("失败原因", "Failure details"),
                    paragraphs: [settings.text(detail, DiagnosticText.importEnglish(detail))]
                )
            }
    }
}

extension View {
    func importFailureAlert(isPresented: Binding<Bool>, detail: String) -> some View {
        modifier(ImportFailureAlert(isPresented: isPresented, detail: detail))
    }
}
