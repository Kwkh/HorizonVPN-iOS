import SwiftUI

struct SubscriptionQRCodeView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tunnel: TunnelController
    let subscription: SubscriptionSummary
    @State private var share: SubscriptionQRShare?
    @State private var image: UIImage?
    @State private var failed = false
    @State private var tooLong = false
    @State private var shareVisible = false
    @State private var generation = UUID()

    private var current: SubscriptionSummary? { tunnel.subscriptions.first { $0.id == subscription.id } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    Text(current?.title ?? subscription.title)
                        .font(.title2.weight(.medium))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    ZStack {
                        if let share {
                            SubscriptionQRCodeArtwork(pattern: share.pattern) { [generation] in
                                guard self.generation == generation else { return }
                                shareVisible = true
                            }
                                .id(generation)
                                .accessibilityLabel(settings.text("订阅二维码", "Subscription QR code"))
                        } else if failed {
                            ContentUnavailableView(
                                tooLong ? settings.text("链接过长", "Link too long") : settings.text("无法生成二维码", "QR code unavailable"),
                                systemImage: "qrcode",
                                description: Text(tooLong
                                    ? settings.text("此链接超出了二维码的容量。", "This link exceeds QR code capacity.")
                                    : settings.text("请检查订阅的来源链接后重试。", "Check the subscription’s source URL and try again.")))
                        } else {
                            Color.clear
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 360)
                    if let share, let image {
                        ShareLink(item: share, preview: SharePreview(current?.title ?? subscription.title, image: Image(uiImage: image))) {
                            Label(settings.text("分享二维码", "Share QR code"), systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .frame(maxWidth: 360)
                        .accessibilityIdentifier("subscription.shareQRImage")
                        .opacity(shareVisible ? 1 : 0)
                        .allowsHitTesting(shareVisible)
                        .accessibilityHidden(!shareVisible)
                        .animation(.easeInOut(duration: reduceMotion ? 0.12 : 0.35), value: shareVisible)
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity)
            }
            .clashScreen()
            .navigationTitle(settings.text("分享二维码", "Share QR code"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(settings.text("完成", "Done")) { dismiss() }
                }
            }
            .task(id: current?.updatedAt) { await load() }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: failed)
        }
        .clashTint()
    }

    private func load() async {
        generation = UUID(); shareVisible = false
        share = nil; image = nil; failed = false; tooLong = false
        do {
            guard current != nil else { throw SubscriptionQRShare.Failure.unavailable }
            let url = try await tunnel.loadSubscriptionShareURL(subscription.id)
            let value = try await SubscriptionQRShare.generate(sourceURL: url)
            try Task.checkCancellation()
            guard let rendered = UIImage(data: value.png) else { throw SubscriptionQRShare.Failure.rendering }
            share = value; image = rendered
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled else { return }
            tooLong = (error as? SubscriptionQRShare.Failure) == .tooLong
            failed = true
        }
    }
}
