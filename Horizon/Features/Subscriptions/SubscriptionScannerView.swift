import SwiftUI
import AVFoundation
import VisionKit

struct SubscriptionScannerView: View {
    let onScan: (String) -> Void
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorizing = false
    @State private var ready = false
    @State private var message: String?
    @State private var delivered = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if ready {
                    SubscriptionCameraView(active: scenePhase == .active && !delivered, onPayloads: receive) {
                        ready = false
                        message = settings.text("相机暂不可用，请返回后重试或从相册识别。", "Camera unavailable. Try again or scan an image from Photos.")
                    }
                } else if message == nil { ProgressView().tint(.white) }
            }
            .safeAreaInset(edge: .bottom) {
                if let message {
                    Text(message).font(.callout).foregroundStyle(.white)
                        .padding().frame(maxWidth: .infinity).background(.black.opacity(0.8))
                }
            }
            .navigationTitle(settings.text("扫描订阅二维码", "Scan subscription QR"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(settings.text("取消", "Cancel")) { delivered = true; dismiss() }
                }
            }
        }
        .clashTint()
        .onDisappear { delivered = true; ready = false }
        .task { await authorize() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await authorize() } }
        }
    }
    private func authorize() async {
        guard !delivered, !authorizing else { return }
        authorizing = true
        defer { authorizing = false }
        guard DataScannerViewController.isSupported else {
            message = settings.text("此设备不支持实时扫码，可返回选择二维码图片。", "Live scanning is unavailable on this device. Choose a QR image instead.")
            return
        }
        var permission = AVCaptureDevice.authorizationStatus(for: .video)
        if permission == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            guard !Task.isCancelled, !delivered else { return }
            permission = AVCaptureDevice.authorizationStatus(for: .video)
        }
        guard permission == .authorized else {
            ready = false
            message = settings.text("未获得相机权限。可在系统设置中为 HORIZON 允许相机，或返回从相册识别。", "Camera permission is unavailable. Allow Camera for HORIZON in Settings, or scan an image from Photos.")
            return
        }
        ready = DataScannerViewController.isAvailable
        message = ready ? nil : settings.text("相机暂不可用，请稍后重试。", "Camera unavailable. Try again later.")
    }
    private func receive(_ payloads: [String]) {
        guard !delivered else { return }
        do {
            let link = try SubscriptionQRCode.uniqueLink(in: payloads)
            delivered = true
            onScan(link)
            dismiss()
        } catch SubscriptionQRCode.Failure.multiple {
            message = settings.text("请只对准一个订阅二维码。", "Frame one subscription QR code at a time.")
        } catch {
            message = settings.text("未识别到支持的订阅或节点链接。", "No supported subscription or node URI found.")
        }
    }
}
