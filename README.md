# Horizon iOS 客户端

2026-10-09 新增可选的 [iCloud 个人订阅同步](docs/icloud-subscription-sync.md)：默认关闭，当前订阅变更需处理，本机节点选择／分流／VPN 状态保持独立。代码、离线回归及 Development schema 已核对；2026-10-10 用户确认两端实机订阅同步通过，Production schema 已部署并回读核对。尚待 TestFlight／发布版验证 Production 实际同步。

远程仓库：<https://github.com/Kwkh/HorizonVPN-iOS>（私有）。此前仓库为 <https://github.com/Kwkh/Horizon-iOS>，原名 Clash-iOS。源码、文档与脱敏示例纳入版本管理；真实订阅、签名材料、构建缓存和 Xcode 个人设置保留在本机。

2026-10-22：将当前完整源码及既有版本历史归档到新仓库 `HorizonVPN-iOS`。本次包含 TestFlight(34) 之后的界面、订阅下载、测速与 iCloud 同步调整，以及开发中的原生 macOS 适配代码；Mac 的实现范围、验证记录和限制见 [macOS 适配进度](docs/macos-adaptation.md)。这是源码归档，不额外修改版本号、签名或网络配置，不执行商店上传、实际同步或新增真机验收。本地远程 `horizonvpn` 对应新仓库，`origin` 保留此前仓库地址。

最近带标签的源码快照为 **TestFlight(34)**（Git 标签 `testflight-34`，2026-10-10）；该快照的主 App 与扩展构建号为 34。该轮纳入可选的 iCloud 个人订阅同步、CloudKit schema、订阅来源二维码分享、本机删除后清理协调和本地化完善，并调整订阅导入、列表与相关交互。实现范围、验证记录和限制见 [iCloud 订阅同步](docs/icloud-subscription-sync.md)、[订阅管理与二维码分享](docs/subscriptions.md) 和 [诊断本地化](docs/diagnostics-localization.md)。既有配置兼容边界继续见 [通用 YAML](docs/general-yaml-compatibility.md)、[DNS](docs/dns-compatibility.md) 和 [筛选策略](docs/selection-policy-compatibility.md)。此前所有开发版本、RC 与 TestFlight 源码标签保留；归档源码不等同于 App Store Connect／TestFlight 上传、CloudKit 部署或实际订阅同步，也不新增构建或真机验收结论。手机安装与功能验收以各功能文档的最新记录为准，Production 客户端同步仍按文档待验收项执行。

自用 SwiftUI + Network Extension 工程。当前已安装 **构建 22，Ping 流量计数版**：固定 Hako 内核、公开 PacketFlow 桥接、手机文件导入和钥匙串存储。支持约定字段的 Hysteria2、VLESS TCP/TLS/Reality/Vision、多节点 select、常用域名/IP 规则及显式 DNS；导入页逐项说明 iOS 适配，未知字段明确拒绝。独立“节点与策略组”页支持断开后选择、下次连接生效；Ping 跟随 MATCH 实际选中的节点。

构建 18 已在真机验证：首页 Ping 返回 207 ms；跨主页、节点、设置页，真实采样持续增加，采样任务 starts=1、stops=0，原订阅 VPN 已恢复连接。曲线固定线性量程默认为 1 MB/s，可手动四档切换；上行亮红、下行主题色。粒子使用连续积分速度，实时数字使用 NumericText，前台采样跨 Tab 持续。60 秒横轴、90 pt 图高、约 2.5 秒图形缓冲保留。

构建 19 已通过模拟器和真机签名构建及包检查并安装到 iPhone：补充 Ping 的加载／结果／胶囊尺寸过渡、累计上下行数字滚动，以及首页状态和提示过渡。动效观感按约定由用户直接在手机上体验反馈。

构建 20 已通过构建并安装到 iPhone：按用户确认默认改为固定对数刻度，增强小流量细节，保留四档线性量程。曲线顶部固定为 10 MiB/s，不按流量自动缩放；数值仍为真实速率。模式切换有局部过渡并持久保存。真机确认默认对数、双线真实采样波形及首页 Ping 返回 172 ms；原订阅 VPN 已恢复并保持连接，手机动效观感由用户体验。

构建 21 已通过签名构建和包检查并安装到 iPhone：以相邻中点二次贝塞尔曲线柔化峰顶与转折。短促尖峰仅在图形上略作平滑，数字、累计值、固定刻度和连续滚动不变；连续切线、无过冲、成熟历史稳定性检查通过。真机 Ping 返回 239 ms，原订阅 VPN 已恢复并保持连接，观感待用户体验。

构建 22 已通过内核重建、签名构建与包检查并安装到 iPhone：将内核 HTTP 延迟测试的实际收发字节计入首页曲线及累计流量，首页 Ping 和批量测速共用计数路径；保持原延迟测量方式，不制造演示波峰。已通过本机服务器字节对账、并发、失败及取消回归；真机 Ping 返回 164 ms，随后看到速率和累计值更新，原订阅 VPN 保持连接。

构建 23 新增「越界」黑白 3D 砖墙与真实地理粒子地球；设置 → 界面风格可恢复经典布局和原深浅色偏好。已通过模拟器渲染、状态连续性检查、签名构建和包检查，真机尚未安装，手势、帧率与观感待验收，详见 [新版界面记录](docs/horizon-ui.md)。

构建 16 已在真机验证双线实时速率、批测完成、取消后重测、切订阅结果过期和断开归零；Hysteria2 与 VLESS 的原生 HTTP 延迟测试均有成功结果。新增 UI 默认深色，主页／节点／设置各自独立成页。完整限制与复测步骤见下方构建 16 记录。

订阅管理：按文件名保存多份 YAML、确认后断开切换并重连、重命名、单项或多选删除。每份订阅独立保存节点选择；原有配置迁移保留。

主机与手机离线自检均为 61/61，双协议虚构配置通过内核完整预检。构建 14 将手动测速默认对齐当前 Mac Verge：统一延迟、Cloudflare HTTP 204、10 秒超时；手机 Hysteria2 实测 217 ms、233 ms。这是测试口径改变，不代表网络提速，Mac 严格同节点对照尚未完成。旧配置的 Safari 预期出口、断开恢复及重连已有证据；构建 15 新双节点配置已实测 Hysteria2 启停、后台网页与主 App 退出后隧道继续存活。两份订阅及 Wi-Fi／5G 切换由用户确认正常，短时断网与锁屏恢复亦反馈未见明显问题。上游 DNS 诊断存在待定位超时；VLESS 真机请求、具体规则、异常中断、应用 UDP/IPv6 和长期稳定性仍待进一步验证，详见稳定性记录。

- [对照 PDF 的功能完整性评估与实施计划](docs/requirements-audit.md)
- [稳定性验收记录](docs/stability-validation.md)
- [构建 16–20：实时曲线、批量测速与界面验收](docs/live-traffic-batch-ui.md)
- [订阅管理、迁移与回退](docs/subscriptions.md)
- [最小原型使用、测试与限制](docs/phase2-prototype.md)
- [环境、候选内核与技术决策](docs/technical-plan.md)
- [兼容清单](docs/compatibility.md)
- [签名、阶段一设备证据与回退](docs/device-validation.md)
- [固定内核源码构建](docs/core-build.md)
- [Hysteria2 虚构样本](Examples/hysteria2-salamander.redacted.yaml)：仅供开发，手机会拒绝把 `.invalid` 样本用于联网。
- [双协议虚构样本](Examples/dual-protocol.redacted.yaml)：覆盖证书指纹、Reality/Vision、fake-ip、双节点和直连规则；全部凭据为测试占位。

## 工程结构

| 部分 | 职责 |
| --- | --- |
| `Horizon/App/HorizonApp.swift` | 应用入口 |
| `Horizon/App/RootTabView.swift` | 三页导航、前后台协调 |
| `Horizon/Features/Home/` | 经典连接页、粒子、共用实时双线速率图 |
| `Horizon/Features/Horizon/` | 越界首页、信息区、Metal 砖墙与地球场景 |
| `Horizon/Features/Nodes/NodesView.swift` | 订阅入口、节点列表和批测入口 |
| `Horizon/Features/Settings/` | 语言、外观、工具与关于 |
| `Horizon/Features/Diagnostics/DiagnosticsView.swift` | 设置内的连接诊断与维护 |
| `Horizon/Features/Diagnostics/Components/` | 主页专用的扩展统计、联网诊断、会话记录子 View |
| `Horizon/Features/Subscriptions/` | 订阅列表、详情、重命名分别成文件；Components 放列表行 |
| `Horizon/Features/Configuration/ImportConfirmationView.swift` | 独立的导入确认 sheet 页面 |
| `Horizon/Features/Configuration/NodeSelectionView.swift` | 独立的节点与策略组选择页，连接中禁止修改 |
| `Horizon/Features/Ping/PingTestView.swift` | 独立的手动 HTTP 延迟测试页，首页通过导航进入 |
| `Horizon/Services/TunnelController.swift` | 只管理本应用配置，观察真实 `NEVPNStatus` |
| `Horizon/Support/PrototypeSelfCheck.swift` | 使用虚构配置的离线自检 |
| `Shared/PrototypeConfiguration.swift` | 导入管线、引用检查、运行配置派生与内核差异检查 |
| `Shared/ConfigurationValidation.swift` / `ConfigurationDNS.swift` / `ConfigurationRules.swift` | 节点字段、DNS 与规则的独立校验 |
| `Shared/ConfigurationCatalog.swift` | 节点与组引用、选择结果及实际 Ping 目标 |
| `Shared/SubscriptionLibrary.swift` / `SubscriptionRepository.swift` | 多订阅索引、独立选择、旧数据迁移、提交和删除清理 |
| `Shared/ConfigurationVault.swift` | 两个 target 共享的 ThisDeviceOnly 钥匙串配置，不开启 iCloud 同步 |
| `Shared/CoreRuntime.swift` | 扩展与真机离线生命周期检查共用的内核初始化、服务创建策略 |
| `Shared/PingReport.swift` | 对齐 Verge 的测试地址与超时、固定结果分类与毫秒数，不传原始错误或节点信息 |
| `PacketTunnel/PacketTunnelProvider.swift` | 内核初始化、启动／停止、固定日志和统计 IPC |
| `PacketTunnel/CorePlatform.swift` | 系统路由/DNS、物理接口绑定和公开 PacketFlow 桥接 |
| `Configuration/Core.lock.json` | 固定源码、工具链与隐私补丁哈希 |

原始模板的 `ContentView.swift` 与 `Item.swift` 保留但不在启动路径中。没有账号、后端、订阅下载、自动连接、App Groups。

每个主要页面单独成文件，按功能分目录；首页与进入后的功能页分别维护，独立 sheet 也算页面。子 View 仅在有独立职责或复用需求时创建，功能内部组件放入该功能的 `Components/`。未来有跨功能复用需求时再创建 `Horizon/Components/`，不与 App／扩展共用的 `Shared/` 混用。Xcode 使用同步文件夹，导航器与磁盘目录对应。持续维护约定见 [AGENTS.md](AGENTS.md)。

## 工程名称与已有安装

打开 `Horizon.xcodeproj`，选择 `Horizon` scheme。源码目录为 `Horizon/`，测试目录为 `HorizonTests/` 与 `HorizonUITests/`，App 桌面名称为 Horizon。

本次只更名工程与产品：已有 `Kenote.Clash` Bundle ID、PacketTunnel / LiveActivity 扩展 ID、开发团队、钥匙串访问组和持久存储键保持原值，以继续更新原 App。请覆盖安装，不要为了改名卸载 App。旧阶段报告中的 `Clash/` 源码路径对应现在的 `Horizon/`；历史构建产物及 Git 快照路径保留，远程仓库改名为 `Horizon-iOS`。外层工作区目录仍为 `Apps/Clash`，不影响 Xcode 工程名称和安装显示名。

本次重命名验证：iPhone Debug 签名构建通过；HorizonTests 中导入呈现、Live Activity 与网络状态相关的 8 项测试通过；包检查确认显示名、可执行文件及扩展关系正确。未安装真机，安装后显示名称和已有订阅延续仍待确认。

## 重建

在仓库根目录执行，验证环境为 Apple Silicon、Xcode 26.5 (17F42)：

```sh
python3 scripts/build-core.py --build
xcodebuild -project Horizon.xcodeproj -scheme Horizon -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/Clash-Phase2 \
  CODE_SIGNING_ALLOWED=NO build
python3 scripts/check-bundle.py /private/tmp/Clash-Phase2/Build/Products/Debug-iphoneos/Horizon.app
```

源码、工具、许可证与 XCFramework 位于 `.build/`，不加入 Git；构建脚本会重新准备它们。签名安装说明见设备文档。没有匹配签名时不要自行加 `-allowProvisioningUpdates`。

完成固定工具链准备后，可运行 `python3 scripts/check-configuration.py` 复测实际 Swift 校验器和固定内核。检查本地文件可加 `--profile '/本地路径/配置.yaml'`：文件只在内存处理，仅输出固定错误分类和数量，不启动服务、不写钥匙串、不导出原文。参数只能传路径，不能把配置内容或订阅 URL 写在命令行。脚本导出的示例与运行 JSON 始终来自虚构测试数据。

真实 YAML 保留在用户控制的本机／手机位置，通过手机导入页确认保存；不要放进源码目录、命令行参数、日志或 Git。`.gitignore` 不是安全存储。将编译、安装、离线运行、隧道启动和真实联网分别验收。
