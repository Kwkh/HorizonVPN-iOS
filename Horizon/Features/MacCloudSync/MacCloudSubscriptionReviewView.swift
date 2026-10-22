#if os(macOS)
import SwiftUI

struct MacCloudSubscriptionReviewView: View {
    let item: CloudSyncReviewItem
    let library: MacLibraryStore
    @Environment(AppSettings.self) private var settings
    @Environment(MacICloudSubscriptionSyncStore.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmsCloud = false
    var body: some View {
        Form {
            Group {
                Section {
                    Text(item.title).font(.headline)
                    Text(explanation).foregroundStyle(.secondary)
                }.listRowBackground(Color.clear)
                Section {
                    Button(item.deleted ? settings.text("删除本机副本…", "Delete local copy…") : settings.text("应用云端版本…", "Apply cloud revision…")) { confirmsCloud = true }
                    if item.localID.map({ id in library.index.entries.contains { $0.id == id } }) == true {
                        Button(item.deleted ? settings.text("保留订阅", "Keep subscription") : settings.text("保留本机版本", "Keep local version")) {
                            sync.resolve(item, resolution: .keepLocal)
                        }
                        if !item.deleted {
                            Button(settings.text("保留两份", "Keep both")) { sync.resolve(item, resolution: .keepBoth) }
                        }
                    }
                }.disabled(sync.working || library.busy || (item.localID == library.index.activeID && !library.vpn.isIdle))
                    .listRowBackground(Color.clear)
                if item.localID == library.index.activeID && !library.vpn.isIdle {
                    Text(settings.text("请先断开 VPN，再处理当前订阅。", "Disconnect VPN before changing the selected subscription.")).foregroundStyle(.secondary).listRowBackground(Color.clear)
                }
                if sync.reviewFailed {
                    Text(settings.text("未能应用，原版本已保留。请同步后重试。", "Could not apply. Your existing version is preserved. Sync and retry."))
                        .foregroundStyle(.red).listRowBackground(Color.clear)
                }
            }
        }.formStyle(.grouped).scrollContentBackground(.hidden).background(.black)
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: sync.reviewFailed)
            .navigationTitle(settings.text("订阅同步", "Subscription sync"))
            .alert(item.deleted ? settings.text("删除本机副本？", "Delete local copy?") : settings.text("应用云端版本？", "Apply cloud revision?"), isPresented: $confirmsCloud) {
                Button(settings.text("取消", "Cancel"), role: .cancel) { }
                Button(settings.text("确认", "Confirm"), role: item.deleted ? .destructive : nil) { sync.resolve(item, resolution: .useCloud) }
            } message: {
                Text(settings.text("此操作会更改本机保存的这份订阅，不会连接 VPN。", "This changes the subscription saved on this device and does not connect VPN."))
            }
            .onChange(of: sync.reviews) { _, reviews in if !reviews.contains(where: { $0.id == item.id }) { dismiss() } }
    }
    private var explanation: String {
        if item.deleted { return settings.text("此订阅已在其他设备删除。本机副本仍保留，等待你处理。", "Another device deleted this subscription. Your local copy is retained for review.") }
        switch item.reason {
        case .current: return settings.text("当前订阅有云端更新，确认后应用并保留上一版本。", "A cloud update is available for the selected subscription. Applying it retains the previous revision.")
        case .conflict: return settings.text("两台设备修改了同一订阅。请选择采用的版本，或保留两份。", "Devices changed the same subscription. Choose a version or keep both.")
        case .invalid: return settings.text("云端版本尚未通过本机恢复与校验。原版本未改变，可重试或保留本机版本。", "The cloud revision could not be restored and validated on this device. The existing version is unchanged. Retry or keep the local version.")
        }
    }
}

#Preview {
    let library = MacLibraryStore(offline: true)
    NavigationStack {
        MacCloudSubscriptionReviewView(item: .init(id: UUID(), version: UUID(), localID: nil, title: "Example subscription", deleted: true, reason: .current), library: library)
    }
    .environment(AppSettings(defaults: UserDefaults(suiteName: "Horizon.MacCloudPreview")!))
    .environment(MacICloudSubscriptionSyncStore(repository: library.cloudRepository, permitsNetwork: false))
    .preferredColorScheme(.dark)
    .frame(width: 700, height: 520)
}

#endif
