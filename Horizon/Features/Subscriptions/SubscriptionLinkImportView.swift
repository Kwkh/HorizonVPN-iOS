import SwiftUI
import PhotosUI

struct SubscriptionLinkImportView: View {
    let tunnel: TunnelController
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scanning = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var readingPhoto = false
    @State private var recognized = false
    @State private var address = ""
    @State private var name = ""
    @State private var downloading = false
    @State private var failure: String?
    @State private var showImportFailure = false
    @State private var task: Task<Void, Never>?

    var body: some View {
        let photoLabel = settings.text("从图片识别", "Scan from image")
        ZStack {
            if let preview = tunnel.importPreview {
                ImportConfirmationView(tunnel: tunnel, preview: preview)
            } else {
                NavigationStack {
                    Form {
                        ClashListContent {
                            Section {
                                TextField(settings.text("订阅名称", "Subscription name"), text: $name)
                                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                                    .accessibilityIdentifier("subscription.linkName")
                                SecureField(settings.text("HTTPS / 节点链接 / Base64", "HTTPS / node URI / Base64"), text: $address)
                                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .privacySensitive()
                                    .accessibilityLabel(settings.text("订阅链接或节点内容", "Subscription URL or node content"))
                                    .accessibilityIdentifier("subscription.linkURL")
                                PasteButton(payloadType: String.self) { values in
                                    guard values.count == 1, let value = values.first, value.utf8.count <= PrototypeConfiguration.maximumBytes else {
                                        failure = settings.text("粘贴内容超过限制或包含多个项目。", "Paste one item up to 1 MiB."); return
                                    }
                                    address = value; failure = nil; recognized = true
                                }
                                .accessibilityIdentifier("subscription.pasteContent")
                            }.disabled(downloading || readingPhoto)
                            Section {
                                Button { scanning = true } label: {
                                    Label {
                                        Text(settings.text("扫描二维码", "Scan QR code"))
                                    } icon: {
                                        Image(systemName: "qrcode.viewfinder").foregroundStyle(actionColor)
                                    }
                                }.accessibilityIdentifier("subscription.scanQR")
                                PhotosPicker(selection: $selectedPhoto, matching: .images, preferredItemEncoding: .current) {
                                    HStack {
                                        Label { Text(photoLabel) } icon: {
                                            Image(systemName: "photo").foregroundStyle(actionColor)
                                        }
                                        Spacer()
                                        if readingPhoto { ProgressView() }
                                    }
                                }.accessibilityIdentifier("subscription.photoQR")
                                if recognized {
                                    Label(settings.text("已识别", "Recognized"), systemImage: "checkmark.circle")
                                        .foregroundStyle(.secondary).transition(.opacity)
                                }
                            }.disabled(downloading || readingPhoto)
                            Section {
                                Button(action: download) {
                                    HStack {
                                        Label {
                                            Text(settings.text("导入并校验", "Import & validate"))
                                        } icon: {
                                            Image(systemName: "arrow.down.doc").foregroundStyle(actionColor)
                                        }
                                        Spacer()
                                        if downloading { ProgressView() }
                                    }
                                }
                                .disabled(downloading || readingPhoto || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !tunnel.canManageSubscriptions)
                                .accessibilityIdentifier("subscription.download")
                                if let failure { Text(failure).foregroundStyle(.red).transition(.opacity); CompatibilityInfoButton(report: tunnel.compatibilityReport) }
                            }
                        }
                    }
                    .clashScreen()
                    .navigationTitle(settings.text("链接导入", "Import from URL"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(settings.text("取消", "Cancel")) { task?.cancel(); dismiss() }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            InformationButton(title: settings.text("链接导入说明", "About URL import"), paragraphs: [
                                settings.text("二维码在本机识别，仅访问你选中的图片。识别后不会自动下载或连接。", "QR codes are decoded on device, using only your selected image. Scanning does not download or connect automatically."),
                                settings.text("支持 HTTPS 订阅地址、节点分享链接、Base64 列表和 YAML。不使用公共转换服务。", "Supports HTTPS subscription URLs, node links, Base64 lists and YAML. No public conversion service is used."),
                                settings.text("来源链接与配置保存在本机钥匙串，可手动刷新，不自动更新。订阅名称可留空。", "The source URL and configuration are saved in device Keychain for manual refresh. Updates are not automatic. The name is optional."),
                                settings.text("订阅最大 1 MiB，导入联网最多等待 30 秒。自定义依赖单项最大 32 MiB，总计 64 MiB。", "Subscriptions: up to 1 MiB and 30 seconds for import network activity. Custom dependencies: up to 32 MiB each, 64 MiB total."),
                                settings.text("默认 Geo 数据已内置；其他依赖通过当前网络下载，不会自动开启 VPN。", "Default Geo data is bundled. Other dependencies download over your current network without starting VPN.")
                            ])
                        }
                    }
                }
            }
        }
        .clashTint()
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: downloading)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: failure)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: readingPhoto)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: recognized)
        .importFailureAlert(isPresented: $showImportFailure, detail: failure ?? "")
        .sheet(isPresented: $scanning) {
            SubscriptionScannerView { link in
                address = link; failure = nil; recognized = true
            }
        }
        .task(id: selectedPhoto) {
            guard let selectedPhoto else { return }
            await readPhoto(selectedPhoto)
            if !Task.isCancelled { self.selectedPhoto = nil }
        }
        .interactiveDismissDisabled(downloading)
        .onDisappear {
            guard !scanning else { return }
            task?.cancel()
            address = ""
        }
    }
    // Explicit symbol colors avoid depending on Form/PhotosPicker's automatic
    // Label tint resolution when the sheet is presented or restored.
    private var actionColor: Color {
        settings.isHorizon ? .white : ClashStyle.accent(colorScheme)
    }
    private func readPhoto(_ photo: PhotosPickerItem) async {
        readingPhoto = true; failure = nil; recognized = false
        defer { readingPhoto = false }
        do {
            guard let image = try await photo.loadTransferable(type: QRCodeImageTransfer.self) else { throw SubscriptionQRCode.Failure.unreadableImage }
            try Task.checkCancellation()
            let worker = Task.detached(priority: .userInitiated) { try QRCodeImageReader.read(image.data) }
            let link = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
            try Task.checkCancellation()
            address = link; recognized = true
        } catch is CancellationError { }
        catch SubscriptionQRCode.Failure.multiple {
            failure = settings.text("图片包含多个订阅链接，请裁剪到一个二维码后重试。", "The image contains multiple subscription URLs. Crop to one QR code and retry.")
        } catch {
            if !Task.isCancelled {
                failure = settings.text("无法从图片识别支持的订阅或节点链接，请选择清晰的二维码图片（不超过 20 MiB）。", "Could not read a supported subscription or node URI. Choose a clear QR image up to 20 MiB.")
            }
        }
    }
    private func download() {
        guard !downloading else { return }
        downloading = true; failure = nil
        task = Task { @MainActor in
            defer {
                downloading = false; task = nil
                if failure != nil && !Task.isCancelled { showImportFailure = true }
            }
            do {
                let deadline = ContinuousClock.now.advanced(by: .seconds(30))
                let payload = try await SubscriptionImportLoader.load(address, permitsNetwork: tunnel.permitsNetwork, deadline: deadline)
                try Task.checkCancellation()
                let cleanName = SubscriptionSummary.cleanName(name)
                if await tunnel.prepareDownloadedImport(payload.data, title: cleanName.isEmpty ? settings.text("链接订阅", "URL configuration") : cleanName, sourceURL: payload.sourceURL, deadline: deadline) {
                    address = ""
                } else { failure = settings.text(tunnel.message, DiagnosticText.importEnglish(tunnel.message)) }
            } catch is CancellationError { }
            catch {
                switch error as? SubscriptionDownloader.Failure {
                case .invalidURL: failure = settings.text("请输入完整 HTTPS 链接，不支持内嵌账号密码或片段。", "Enter a complete HTTPS URL without embedded login credentials or fragments.")
                case .redirect: failure = settings.text("跳转受限，请使用最终 HTTPS 下载地址。", "Redirect blocked. Use the final HTTPS download URL.")
                case .tooLarge: failure = settings.text("配置超过 1 MiB，现有订阅未改变。", "The configuration exceeds 1 MiB. Existing configurations are unchanged.")
                case .empty: failure = settings.text("服务器返回空内容。", "The server returned an empty response.")
                case .response: failure = settings.text("服务器未返回成功响应，请检查链接是否有效。", "The server did not return a successful response. Check the subscription URL.")
                case .timedOut: failure = settings.text("订阅下载超时，请检查当前网络后重试。", "Subscription download timed out. Check the current network and retry.")
                case .dns: failure = settings.text("无法解析订阅服务器，请检查 DNS 或当前网络。", "Could not resolve the subscription server. Check DNS or the current network.")
                case .offline: failure = settings.text("当前网络不可用或未获网络访问权限。", "Network unavailable or network access not permitted.")
                case .tls: failure = settings.text("订阅服务器的 TLS 或证书校验失败。", "Subscription server TLS or certificate validation failed.")
                case .connectionLost, .unreachable: failure = settings.text("无法连接订阅服务器或下载途中断线，请重试。", "Could not connect to the subscription server or the connection was lost. Retry.")
                default: failure = settings.text("内容格式不支持，或下载失败；请检查输入后重试。", "Unsupported input or download failure. Check the input and retry.")
                }
            }
        }
    }
}
