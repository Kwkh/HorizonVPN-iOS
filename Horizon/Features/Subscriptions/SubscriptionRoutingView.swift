import SwiftUI

struct SubscriptionRoutingView: View {
    @State private var store: SubscriptionMaintenanceStore
    @Environment(AppSettings.self) private var settings
    @State private var pendingMode: ConfigurationRouting?
    @State private var showingError = false
    init(tunnel: TunnelController, id: UUID) { _store = State(initialValue: .init(id: id, tunnel: tunnel)) }
    var body: some View {
        List {
            ClashListContent {
                Section {
                    LabeledContent(settings.text("订阅", "Subscription")) {
                        HStack {
                            Text(store.tunnel.subscriptions.first(where: { $0.id == store.id })?.title ?? "—")
                            SubscriptionRowActivity(busy: store.loading)
                        }
                    }
                    ForEach([ConfigurationRouting.subscription, .smart], id: \.self) { mode in
                        Button {
                            guard !store.loading, !store.working, store.record != nil, store.routing != mode, store.tunnel.canManageSubscriptions else { return }
                            pendingMode = mode
                            store.changeRouting(mode)
                        } label: {
                            HStack {
                                Text(mode == .smart ? settings.text("智能分流", "Smart routing") : settings.text("遵循订阅", "Follow configuration"))
                                Spacer()
                                SubscriptionRowActivity(busy: store.working && pendingMode == mode,
                                                        selected: store.record != nil && store.routing == mode)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityValue(store.record != nil && store.routing == mode ? settings.text("已选择", "Selected") : "")
                    }
                }.listRowBackground(Color.clear)
                Section {
                    NavigationLink { SubscriptionMaintenanceView(tunnel: store.tunnel, id: store.id) } label: {
                        Label(settings.text("版本与回滚", "Revisions & rollback"), systemImage: "clock.arrow.circlepath")
                    }
                    NavigationLink { RuleDiagnosticsView(tunnel: store.tunnel) } label: {
                        Label(settings.text("验证分流", "Inspect routing"), systemImage: "arrow.triangle.branch")
                    }
                }.listRowBackground(Color.clear)
            }
        }.listStyle(.plain).clashScreen()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                InformationButton(title: settings.text("智能分流", "Smart routing"), paragraphs: [
                    settings.text("VPN 保持连接。原订阅规则优先，未命中的国内域名及中国大陆 IP 直连，其他流量使用原代理目标。已有特殊代理、拦截规则可能改变某项业务的出口；不按 App 名称分类。", "VPN stays connected. Existing rules take priority, then domestic domains and mainland IPs go direct; the original proxy fallback handles the rest. Existing exceptions may override this. Routing is destination-based, not per-app."),
                    settings.text("配套直连 DNS 使用阿里与腾讯的加密解析器；已有 DNS 策略与直连上游会保留。规则资源优先使用本机已校验快照或内置数据，启用时不下载；自定义资源缺失则保留原配置。", "Direct DNS uses encrypted AliDNS and Tencent resolvers. Existing DNS policies and direct resolvers are preserved. Enabling uses verified local snapshots or bundled rules without downloading. Missing custom resources leave the configuration unchanged."),
                    settings.text("选择后先预览再保存，连接中应用会确认重连。选择随订阅及版本保存，更新继续沿用；关闭恢复原订阅，可在版本历史回滚。分类并非绝对准确，请用真实业务验证。", "Review before saving. Applying while connected requires reconnect confirmation. The choice follows this configuration through refreshes and revisions. Turn it off to restore source policy, or roll back a revision. Validate classification with real traffic.")] + (store.assessment?.explanations(english: !settings.isChinese) ?? []))
            }
        }
        .sheet(item: Binding(get: { store.review }, set: { if $0 == nil { store.discardReview() } })) {
            SubscriptionRevisionReviewView(store: store, review: $0)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: store.working) { _, working in
            if !working { pendingMode = nil }
        }
        .onChange(of: store.message) { _, message in
            if message != nil && store.review == nil { showingError = true }
        }
        .alert(settings.text("操作未完成", "Couldn't complete operation"), isPresented: $showingError) {
            Button(settings.text("好", "OK"), role: .cancel) { }
        } message: {
            Text(settings.text(store.message ?? "", DiagnosticText.importEnglish(store.message ?? "")))
        }
        .task { await store.load() }
        .onDisappear { store.cancel() }
    }
}
