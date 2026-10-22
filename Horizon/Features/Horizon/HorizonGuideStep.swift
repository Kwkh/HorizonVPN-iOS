import Foundation

/// Guide content describes the existing controls; it never performs the demonstrated action.
enum HorizonGuideStep: Int, CaseIterable {
    case subscriptions, nodes, connection
    var title: (chinese: String, english: String) {
        switch self {
        case .subscriptions: ("带上你的世界", "Bring your world")
        case .connection: ("看见这个世界", "Beyond the wall")
        case .nodes: ("选你想走的路", "Choose your path")
        }
    }
    var caption: (chinese: String, english: String) {
        switch self {
        case .subscriptions: ("节点页导入 · 文件 / 链接 / 扫码", "Import in Nodes · File / URL / QR")
        case .connection: ("现在，开启你的 HORIZON 之旅！", "Now start your journey at HORIZON!")
        case .nodes: ("切换节点 · Ping 测速 · 首页实时流量", "Switch nodes · Test Ping · Live traffic on Home")
        }
    }
    var accessibilityDescription: (chinese: String, english: String) {
        switch self {
        case .subscriptions: ("在节点页进入订阅管理，可从文件、链接或二维码导入订阅。", "Open Configurations in Nodes to import a file, URL or QR code.")
        case .connection: ("在页面任意位置向下滑动，足够距离后松手进入；提前松手会退回。辅助功能可激活场景继续。这里仅为演示，不连接 VPN。导入配置后，可在首页点击连接或下滑越墙。", "Pull down anywhere on the page and release to enter; a short pull returns to the guide. Accessibility can activate the scene to continue. This demonstration does not connect VPN. After importing a configuration, tap Connect or pull down on Home.")
        case .nodes: ("点击节点切换路径；无需连接 VPN 也能测速，连接后在首页查看实时流量。这里的动画仅为操作示意。", "Tap a node to select it. Test Ping with or without VPN, and see live traffic on Home while connected. This animation is only a demonstration.")
        }
    }
}
