# macOS 适配进度

## 2026-10-11：第一阶段，隔离验证与原生内核准备

本阶段开始时正式工程为 iOS／iPadOS target，支持 Apple Silicon 上的 Designed for iPad 运行方式。原生目标已在下面的第二阶段新增。

### 已验证

- 原有 App 在 My Mac (Designed for iPad) 下签名构建并由 Xcode 启动。
- 使用独立 `Horizon Mac Offline` scheme：虚构订阅、内存仓库、隔离 UserDefaults、`permitsNetwork = false`，首次引导使用预览模式。未读取真实订阅或钥匙串，未发起 VPN／iCloud 操作。
- 欢迎页、三段引导、鼠标下拉继续、后续入场、首页与节点页可进入。这里只验证操作链路与稳定性，不代表动画观感已验收。
- 首次运行在 `com.apple.CoreMotion.MotionThread` 触发 `EXC_BREAKPOINT`；改为 Mac 不创建 `CMMotionManager` 后，重新走通完整引导。iPhone／iPad 仍使用原来的传感器与平滑算法。
- Mac 侧栏选中项出现白底白字，局部覆盖 Mac 上的 Horizon 侧栏 tint；iPad 路径保持原样。
- 独立生成 `.build/macos/artifacts/Hako.xcframework`，包含原生 `macos-arm64_x86_64` 切片。iOS 框架、构建 manifest 及许可证目录在 Mac 构建前后逐文件 SHA-256 一致。
- 原生 macOS arm64 与 x86_64 Swift 导入／链接通过；仅在当前 arm64 Mac 执行解析，不将链接成功表述为 Intel 实机验证。
- 真实原生框架直接链接共享配置代码，146／146 个离线自检通过；iOS、macOS 隧道及 macOS 应用三个 profile 的差异报告和资源规划 API 均通过虚构输入检查。
- 原有 iPhone／iPad target 构建通过；现有引导相机、拖拽、粒子交接、倾斜平滑回归通过。

### 可复验命令

```sh
# 相同固定源码、Go 工具链及已记录补丁，产物与 iOS 分开。
python3 scripts/build-macos-core.py --build

# 两种原生架构链接；本机真实框架离线配置检查。
python3 scripts/check-macos-core.py
```

Mac 产物与许可证在 `.build/macos/artifacts/`，不进入移动端 App 包，不改变 iOS `Core.lock.json`、现有构建脚本或 Xcode 框架引用。

本地日志：`build/mac-native-core-build.log`、`build/mac-native-core-check.log`、`build/mac-mobile-regression-build.log`。阶段开始前的未提交修改、HEAD 及源文件备份保留在 `build/rollback/macos-stage1-20261011/`；回滚只恢复本轮的两个平台适配源文件并移除新增验证文件，不覆盖先前的界面修改。

### 下一阶段的明确阻碍

1. 原生 Mac 隧道：现有隐私补丁仅允许 `iosPacketTunnel` 的临时服务。原生框架可以解析配置，不代表 `macosPacketTunnel` 已能创建或启动服务。应独立扩展 Mac 隐私约束与生命周期回归后再接入 target。
2. 原生存储：配置依赖的默认存储在 `os(macOS)` 仍走测试注入；需要接入 Mac Data Protection Keychain、访问组与 App Group，保持手机存储路径不变。
3. 独立原生 App／扩展 target：按桌面窗口与侧栏组织，逐项替换 UIKit、手机手势、曲线显示时钟、权限和应用生命周期调用。ActivityKit 不作为 Mac 自有 VPN 状态界面。
4. 配置兼容策略：共享校验仍沿用手机规则；不能仅切换 core profile 就宣称支持桌面进程规则、系统代理或所有 Verge 功能。
5. 真正的隧道联网、iCloud 和签名分发需要单独验收。此次没有安装系统扩展、添加 VPN、改变当前网络或同步现有订阅。

Apple 的 [Network Extension 部署说明](https://developer.apple.com/documentation/technotes/tn3134-network-extension-provider-deployment) 区分 Mac App Extension 与 System Extension 的分发方式；原生 target 的后续分发方案需遵循该约束。Apple Silicon 上运行现有 iOS App 的途径见 [官方说明](https://developer.apple.com/documentation/apple-silicon/running-your-ios-apps-in-macos)。

## 2026-10-11：第二阶段，原生 App／隧道与本机仓库

新增独立的 `HorizonMac.xcodeproj`，最低 macOS 26。`HorizonMac` App 与 `HorizonMacTunnel` App Extension 使用 `Kenote.Horizon.Mac` 与 `Kenote.Horizon.Mac.PacketTunnel`；共享访问组为 `$(AppIdentifierPrefix)Kenote.Horizon.Mac`。入口与桌面页面位于 `Horizon/App/Mac`、`Horizon/Features/MacHome`／`MacConfigurations`／`MacNodes`，服务位于 `Horizon/Services/Mac`，目录与导航器对应。独立工程使原有移动 target、框架引用与签名配置无需改写。

### 已接通

- 原生单窗口 `NavigationSplitView`、订阅矩阵、可搜索的节点／策略组、文件和链接导入预览、显式保存与连接状态控制。解析、依赖准备和 Keychain 写入由独立 actor 执行，不占用 UI actor。
- 复用现有配置解析、依赖下载策略、事务仓库、完整内核预检、证书例外授权和实际 Packet Tunnel 实现，没有另建一套订阅解析器。
- Mac 的 Keychain 查询采用 Data Protection Keychain，保留非同步、设备本地的保护策略；Mac App／隧道使用独立访问组。没有在访问失败时降级成明文文件。
- `HORIZON_NATIVE_MAC` 只在新工程中定义，选用 `macosPacketTunnel`，以 128 MiB 作为 Go GC 提示；手机版仍为原来的 iOS profile 和 40 MiB 提示。128 MiB 不代表系统内存保证。
- 原生 Mac 没有移动端小组件／灵动岛发布动作。隧道状态由 Mac 的 `NEVPNStatus` 接入；本轮没有新增 Mac Widget、ActivityKit 或 CloudKit 上传。
- `Configuration/MacCore.lock.json` 锁定移动基础 lock 的 SHA-256 与 Mac 增量补丁。Mac 专用源码 checkout 在 `.build/macos/core-patched/`；没有编辑移动端 patched checkout。
- Mac 增量补丁允许明确的 macOS Packet Tunnel 临时服务，但仍要求 private diagnostics、禁用持久缓存，以及实际 NE 平台。普通 application profile、非 NE 平台仍被拒绝；Unix 控制 socket 保持关闭。

### 验证结果与边界

- arm64 Debug 原生 App／扩展构建通过；x86_64 Release 原生 App／扩展构建通过。Intel 结果只代表编译／链接，不代表 Intel 实机验收。
- 原有 iOS／iPadOS 工程构建通过。第二阶段开始前后的移动工程文件与 `Configuration/Core.lock.json` 字节一致；Mac SDK 构建前后的移动框架、manifest、许可证 SHA-256 一致。
- 真实原生 SDK 的共享离线配置自检 146／146 通过；三个 profile 的资源规划和适配报告检查通过。
- Mac 隐私 Go 检查通过：拒绝不安全初始化参数／普通 application profile／非 NE 平台；三次服务创建和重复关闭正常；不启动服务、网络监控、Unix 控制接口或持久数据库，也没有残留文件。
- Mac 实际订阅 worker 的离线检查通过：虚构仓库、订阅切换、组选择、离线禁止下载与连接、文件预览不提前提交、显式保存、超大文件拒绝并保留原仓库。真实 Swift `CoreRuntime.setup` 与完整本地预检通过，临时资源删除正常。
- 原生窗口实际离线启动，检查了侧栏、矩阵、虚构订阅切换、节点选择、系统文件选择器、导入预览和 Save 后单次收起。此项仅证明操作链路，不是最终视觉验收。
- 离线预览退出后被工具重新拉起时曾丢失命令行参数，触发一次默认存储访问；ad hoc App 无访问组权限，查询失败，没有读取到订阅。已将离线标记写入预览构建，并验证无参数重新启动仍为虚构数据。
- **尚未验证**App／扩展真实 Keychain 跨进程读写、系统 VPN 配置登记、实际连接／断开、国内直连／国外代理或 Mac iCloud 同步。签名和独立启动成功不能作为 VPN 可用证明。
- 用户已确认首版通过 Mac App Store 分发，沿用 Packet Tunnel App Extension。初次自动签名因 Xcode 开发者账户凭据失效而失败；重新登录后，命令行首次仍报 `No Accounts`。在 Xcode 界面打开原生工程并构建成功后，两个 Mac Team Provisioning Profile 已生成，随后命令行签名构建也通过。
- 已逐项检查实际签名产物：App／扩展均属于团队 `68WND8JR7P`，Bundle ID 分别为 `Kenote.Horizon.Mac` 与 `Kenote.Horizon.Mac.PacketTunnel`，包含 `packet-tunnel-provider`、App Sandbox 和客户端网络权限，并共享 `68WND8JR7P.Kenote.Horizon.Mac` 访问组；两者 `codesign --verify --strict` 通过。正常签名版独立启动、初始空仓库读取和订阅页打开无错误；未导入真实订阅、创建 VPN 或上传商店。镜像通道曾短暂关闭，恢复后同一进程及订阅页正常，未发现相应崩溃报告。
- 用户已授权本地 DIRECT 配置的真实隧道联调，结束保持未连接。开始前 `scutil --nc list` 确认已有 VPN 均未连接；本地 `MacDirectTunnelTest.yaml` 仅含 `MATCH,DIRECT`，无真实节点凭据或远程依赖。已通过正常签名版完整预检、导入预览和 Keychain 保存。Apple 公开测试网页在基线下返回 HTTP 200；腾讯首页返回 HTTP 501，不能将该响应当作正常业务成功基线。连接请求日志到达 `Saving configuration Horizon`，截至本轮检查尚无 native Horizon VPN 配置登记，等待系统授权回调；自动化工具禁止操作 UserNotificationCenter，已请用户手动查看／处理系统提示。不能据此宣称隧道启动或跨进程 Keychain 读取通过。过程记录位于 `build/mac-vpn-integration-20261011.json` 及 `build/mac-vpn-*.log`。
- 后续用户完成系统授权，保存请求成功并自动继续原来的连接流程；扩展日志先后出现 `provider.entered`、`config.accepted`、`core.setup`，已证实扩展成功读取 App 保存的测试配置及完成内核 setup。之后在系统 DNS bootstrap 阶段以 2019 失败，尚未调用物理路径准备或安装 Horizon 路由。用户随后说明 Mac 正在使用其他 VPN，要求暂不连接 Horizon；已暂停联调，没有重试、停止其他 VPN 或修改 DNS。只读复核 Horizon 为 Disconnected，控制器也没有自动重试逻辑。当前不能判断 DNS 失败是其他 VPN 的解析器环境还是 Mac 专项适配缺陷；需后续允许切换网络时再对照。此次限制取代原先的联网测试授权，恢复测试前重新确认。

### 复验

```sh
python3 scripts/build-macos-core.py --build
python3 scripts/check-macos-privacy.py
python3 scripts/check-macos-core.py
python3 scripts/check-macos-library.py

# 独立原生项目，正常运行／归档入口。
xcodebuild -project HorizonMac.xcodeproj -scheme 'Horizon Mac' \
  -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build

# 本机离线 UI 预览；YES 写入 Debug App，重新打开仍然隔离。
xcodebuild -project HorizonMac.xcodeproj -scheme 'Horizon Mac Offline' \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/MacNative \
  CODE_SIGN_IDENTITY=- CODE_SIGN_ENTITLEMENTS= CODE_SIGN_STYLE=Manual \
  HORIZON_OFFLINE_PREVIEW=YES build
```

本地日志：`build/mac-native-core-stage2-build.log`、`build/mac-native-privacy-check.log`、`build/mac-native-core-stage2-check.log`、`build/mac-native-library-check.log`、`build/mac-native-offline-build.log`、`build/mac-native-intel-build.log`、`build/mac-stage2-mobile-regression.log`、`build/mac-native-development-signing.log`。

### 后续工作

1. 首版已确定 Mac App Store 分发，开发签名已通过；下一步验证实际 Data Protection Keychain 跨 App／隧道读写。当前使用 Packet Tunnel App Extension；独立分发的 System Extension 安装流程不在本轮内。
2. 授权后再添加 Mac VPN 配置并验证真实流量、物理网卡绑定、重连、DNS／Geo 规则与系统睡眠唤醒。不借用手机的历史网络测试授权。
3. 移植首页 Metal 墙／地球、完整 introduction、实时曲线、测速、连接时节点切换、分流设置、订阅维护、设置及用户主动开启的 iCloud，同步现有功能后再做桌面交互细化。当前主页地球为 SF Symbol，是桌面基础功能验证界面，尚未达到手机版视觉／功能完整度。
4. 现阶段 Mac 仍沿用已有配置兼容合同，桌面监听／系统代理／进程规则未启用，不宣称与 Verge 功能对等。

第二阶段回滚备份位于 `build/rollback/macos-stage2-20261011/`，包含本轮开始时的 diff、HEAD、已存在源文件和第一阶段新增文件。回滚只恢复本轮修改的共享文件及 `scripts/build-macos-core.py`／检查输入／进度文档，移除第二阶段新增的 Mac 工程、各 `Horizon/` 下新增的 Mac 目录、`Configuration/Mac/`、Mac lock／补丁／测试；第一阶段和用户原有修改保留。不要使用全仓库 reset。

## 2026-10-11：第三阶段，桌面日常功能与共享场景

本阶段以现有 iPad 六项侧栏为布局参考，独立实现原生 Mac 页面：主页、节点、订阅、策略组、延迟测试、设置。保留原生 NavigationSplitView 侧栏材质、工具栏、搜索和窗口缩放；不修改 iPhone／iPad 的布局。

- 订阅矩阵进入独立详情页，支持重命名、删除、激活、更新预览和最多五份历史版本回滚；支持拖入文件与 Command-O。解析、资源准备、Keychain 和指纹计算均在 actor 中进行。更新共用 30 秒 deadline；回滚使用对应版本缓存的依赖，不依赖在线下载。应用前比较 revision／source／choices，拒绝过期预览；当前 Horizon 连接未断开时禁止替换或删除活动订阅。
- 节点矩阵、策略组折叠、单节点测速和批量测速使用同一五并发队列；运行中可追加其他节点测试，也能排序与选择。结果绑定订阅 UUID 和内容摘要；切换或更新后清空旧结果，取消后旧回调不会写回新订阅。离线 UI 预览禁用真实测速。
- 连接时选择节点通过 session／configuration identity 校验的 NE IPC 执行，确认内核结果后才保存；丢失回复会读取真实状态进行核对，无法确认时请求停止 Horizon 自己的隧道。持久化失败尝试恢复原选择；不操作其他 VPN。
- 首页复用原 Metal renderer、粒子数据、shader 和连接／恢复时间线。Mac 的 NSViewRepresentable 负责窗口、Retina 比例和鼠标输入，墙反馈的 0.08 秒与 0.3 秒拖动阈值沿用移动端；连接状态只允许地球拖动。设置提供语言、原始名称、砖块／地球大小、动态效果、流量曲线和连接确认。
- 实时流量读取扩展的有界计数历史，复用 TrafficWindow 与 Bézier 几何；没有用 UI 生成假速率。场景失去前台、页面离开或介绍覆盖首页时暂停，动画遵循 Reduce Motion。介绍页复用 welcome 笔画、三章场景、宽屏隔离、粒子 globe 和实际呈现回调；拖动可撤回，最终帧呈现后交给主页。正式首启只在空库且没有完成标记时显示，也可在设置重播；不会因介绍播放自动连接或申请 VPN 权限。
- iOS 共享源码仅增加两个平台分支：welcome 的 AppKit 字体和 guide 的桌面宽屏隔离；iOS 原分支原样保留。没有修改移动端工程、内核 lock 或框架。

验证：Mac Debug 正常签名及隔离预览构建通过，arm64／x86_64 双架构 Release 编译和链接通过（不代表 Intel 实机验证）；原 iOS／iPadOS 目标构建通过。扩展后的 `scripts/check-macos-library.py` 验证改名、活动／最后一项删除、历史版本、过期候选拒绝、离线回滚、五并发、增量入队、单独重测和取消后的结果隔离，带 provider 的回滚也确认恢复对应版本的缓存资源、没有在线下载，全部通过；共享 `check-horizon-motion.swift` 连续性检查通过。测试数据全部虚构并在内存中，未操作 Keychain、CloudKit、VPN 或网络。

本轮没有进行真实节点测速、连接时切换、流量或 DNS 联调，遵守用户当前正在使用其他 VPN 的限制；这些仍需后续授权后验证。Mac iCloud、桌面进程规则／系统代理及商店上传不在本阶段范围。动效观感仍由用户验收，编译通过不代表视觉验收。

本阶段回滚快照：`build/rollback/macos-stage3-20261011/`。包含开始时的 `baseline.patch`、HEAD、文件清单和当时所有已改／新增源码副本。回滚只恢复本阶段触及的文件、移除本阶段新文件；保留前两阶段及用户原有工作，禁止全仓库 reset。构建及回归日志：`build/mac-stage3-*.log`。


### 解锁后的离线窗口复查

使用固定写入离线标记的 Debug 预览，仅操作内存中的虚构订阅；未连接 Horizon、变更其他 VPN、读取真实节点凭据或请求 CloudKit。完成六项侧栏、详情／维护导航、策略组折叠、节点选择、窗口缩放、welcome 与三章介绍、part 3 拖动推进及完整结束返回设置的检查。系统文件面板成功选择额外的六节点虚构 YAML，导入预览后 Save 单次收起，订阅矩阵新增并选中该项，节点矩阵显示全部六项；宽窗口为两列，缩窄后为一列。未进行真实测速。短拖后的静止归位可见，但中途动效观感仍由用户确认。

本次修正限于四个 Mac 文件：

- 首页标题独立于 360pt 场景区域，避免墙顶穿过连接状态文字；保持原 renderer、shader 和粒子资源。
- 介绍场景预留顶部与下方文案空间，part 2 示意屏及 part 3 墙壁不再覆盖文案；播放期间隐藏底层窗口工具栏。globe 交接仍使用对应场景 viewport 与最终呈现回调。
- 订阅详情的隐藏加载器不再生成空的玻璃工具栏背景；离线说明明确标为仅保存在内存。
- 离线重播结束不再写入正式的首次介绍完成标记；正常模式保持原有行为。

修正后正常签名 Debug 构建通过，离线预览构建通过。此次没有修改移动端源码或工程。主要界面检查完成后 Mac 再次锁屏，最后一次补查未能继续；不将本次检查当作最终动效验收。真实 VPN／DNS 联调仍暂停。补充视觉修正的独立回滚副本位于 `build/rollback/macos-stage3-visual-20261011/`；第三阶段总回滚清单已更新文件摘要，原始副本不变。


## 2026-10-11：Mac 订阅与节点矩阵优化

保持独立原生 Mac 方案，本轮只调整 MacConfigurationsView／MacNodesView，新增各自 Components 下的 MacConfigurationCard／MacNodeCard。移动端布局、共享订阅解析、VPN、Keychain 与测速队列均未修改。

- 订阅矩阵缩小页面边距与卡片间距，卡片集中呈现名称、节点／策略组／规则数量、当前状态和直接使用入口。进入详情继续由父页面注册的 UUID 导航目的地负责；直接使用仍调用原 activate 并保留空闲状态限制。支持按名称搜索与无结果提示，不展示来源链接或凭据。
- 节点矩阵最小列宽由 290pt 调至 230pt，页边距由 28pt 调至 24pt，列距由 16pt 调至 12pt。名称区与协议／Ping 区分开，名称保留两行等高位置，选中标记固定占位；选中及悬停仅局部改变背景与边框，不缩放卡片。
- 节点增加原始／名称／延迟排序；未测得延迟的节点排在有效结果之后，同值保留原始次序。运行中仍可排序，重排遵循 Reduce Motion。卡片身份在同一订阅、同一搜索条件内稳定，grid 绑定 probeScope 与搜索条件；排序保留身份，切换订阅或搜索后重建缓存单元。原延迟测试列表与策略组页面保持原样。

离线 Debug 预览及正常签名构建日志：`build/mac-dense-layout-build.log`、`build/mac-dense-layout-signed.log`。解锁后使用内存虚构订阅完成窗口复查：约 1200pt 宽窗口下为三列，约 878pt 窄窗口下为两列。订阅搜索／无结果、直接使用、详情导航、文件导入及 Save 单次收起均正常；节点选择与排序菜单可用。发现清除搜索或导入后，LazyVGrid 可能保留不可见的旧单元；订阅网格现绑定可见 UUID 集合，节点网格绑定订阅范围与搜索条件，修复后已复验两页搜索恢复、导入及窗口缩放，卡片全部可见。离线预览和修复后的正常签名 Debug 构建均通过，git diff --check 通过。未进行真实测速、延迟结果重排或 VPN 联调；动效观感仍由用户确认。没有读取真实订阅或请求 CloudKit，也没有连接或改变当前 VPN。本轮独立回滚副本位于 `build/rollback/macos-dense-layout-20261011/`，恢复其中 files 的四份副本并移除 changes.json 标记的两个新增组件即可保留上一轮界面。


## 2026-10-11：Mac 文字列表左右留白

延迟测试、订阅详情及更新与版本三个原生 plain List 增加 24pt 左右外边距，列表原生行内边距继续保留；文字、右侧操作及分隔线一并内收。没有修改卡片矩阵、设置、弹窗、移动端页面或业务逻辑。macOS plain List 对 scrollContent contentMargins 未产生预期视觉变化，因此最终使用列表级 horizontal padding，避免依赖无效修饰符。

离线预览已确认三个页面的左右留白，并检查约 878pt 窄窗口下测速页的标题、行文字与右侧按钮没有拥挤；预览数据仅保存在内存，未连接 VPN 或执行真实测速。离线构建与正常签名 Debug 构建通过，日志：`build/mac-list-margins-build.log`、`build/mac-list-margins-signed.log`。独立回滚副本：`build/rollback/macos-list-margins-20261011/`，恢复 files 中四份副本即可。


## 2026-10-11：统一 App Store Connect 应用记录

Mac 主 App 的 Debug／Release Bundle ID 改为 `Kenote.Clash`，与现有 iOS 主 App 一致；独立 Mac 工程、target 和原生界面继续保留。Mac 隧道扩展使用 `Kenote.Clash.Mac.PacketTunnel`，MacVPNController 的 provider 查找／创建与此同步，区别于移动端 `Kenote.Clash.PacketTunnel`。依据 Apple 的 Add platforms 文档，同一记录下各平台共用主 Bundle ID：https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms 。

Mac 的 SharedKeychainGroup 与两份 entitlements 保持 `$(AppIdentifierPrefix)Kenote.Horizon.Mac`，继续访问原 Mac 订阅仓库，不改为移动端组；商店记录统一不要求钥匙串组相同。原 Mac 开发版的沙盒偏好属于旧 Bundle ID，不承诺自动迁移；旧标识的 VPN profile 不会在启动时迁移、删除或连接。新版本只有用户显式 Connect 时才创建／启用自身新扩展对应的配置，仍遵循既有网络操作边界。

验证：Xcode 已获取新标识的 Mac 开发 provisioning profiles；Debug 签名构建与本地 Release archive 通过。核对两种产物的 App／扩展 Info.plist、实际 application identifier、OSX provisioning profiles、NetworkExtension 权限、保留的共享钥匙串组及 codesign --verify --strict 均通过；归档顶层 ApplicationProperties 标识为 `Kenote.Clash`。移动端工程与两份主配置文件摘要未变化。没有启动新 App、操作 VPN、读取订阅数据、请求 CloudKit 或上传商店。商店分发验证／重签名仍由 Organizer 的 Distribute App 流程完成；随后登录 Safari 核对现有 Horizon VPN 记录（Apple ID 6819066250、Bundle ID Kenote.Clash）：记录中已出现 macOS 1.0 Prepare for Submission，刷新后仍保留。平台添加已完成，无需重复创建；Mac 构建尚未上传，用户将自行上传。

归档：`build/HorizonMac-UnifiedRecord.xcarchive`。日志：`build/mac-unified-record-build.log`、`build/mac-unified-record-archive.log`。本轮回滚副本：`build/rollback/macos-unified-record-20261011/`，恢复 files 的工程、MacVPNController 和文档三份副本即可。

## 2026-10-11 — 紧凑订阅卡片与右键管理

- Mac 订阅卡片移除节点／策略组／规则统计、底部 Use 操作及详情导航箭头，改为名称与固定占位的当前订阅标记；保留自适应矩阵与 24pt 页面边距。
- 单击仅调用订阅激活操作，不调用 VPN 连接；当前 VPN 未断开或库正在处理事务时保留原有切换保护。
- 右键菜单提供订阅信息、检查更新、历史版本预览、改名与删除。历史回滚仍先进入原有更新预览，删除仍需确认；正在使用的连接订阅不可删除。
- 菜单元数据由后台 actor 读取，只有版本编号、日期与更新能力返回 UI；配置正文、凭据与来源 URL 不进入菜单。历史操作按版本 UUID 在 worker 内重新查找，过期版本拒绝执行。
- 验证：离线 Debug 构建、正常签名 Debug 构建通过；10 项原有 Mac 库回归检查通过，补充菜单元数据与无效版本 ID 检查。隔离身份的离线窗口验证单击选中／保留页面／首页仍未连接、右键信息、改名、搜索过滤及清除恢复。未操作真实订阅、VPN 或 CloudKit。视觉动效仍由用户体验确认。
- 本轮回滚副本：`build/rollback/macos-compact-configurations-20261011/changes.json`。iOS／iPadOS 页面无改动。

## 2026-10-11 — 订阅时间、账户额度与刷新入口

- Mac 卡片恢复导入时间（刚刚／相对时间，悬停可看完整时间），右上角独立刷新按钮保留固定占位；刷新时仅该图标过渡为加载指示，卡片名称、选中标记与布局不变。卡片单击仍只切换订阅。
- 下载器增加返回数据及可选账户元数据的 `fetchResponse`；现有 `fetch` 仍返回相同 Data，URL 校验、重定向、TLS、大小与超时限制不变。导入 loader 透传可选元数据，移动端未使用此信息，未修改移动端界面或云同步结构。
- 参考 https://www.clashverge.dev/guide/url_schemes.html 接收 `subscription-userinfo`，兼容对象存储的 `*-subscription-userinfo` 前缀。余量为总量减上传／下载之和，超额归零；总量为零、计数缺失或响应头异常时不猜测额度，不影响 YAML 导入。
- Mac 将服务商返回的额度与采集时间保存到现有受保护存储的独立可选元数据项。导入及成功校验的在线刷新更新账户额度；回滚历史不会回退当前账户余量。下载失败保留上次数据，成功响应不含额度则清除旧额度。删除订阅同步清理此元数据；额度写入失败不把已经提交的订阅报告成失败。
- 卡片展示“剩余 / 总量”与剩余额度进度条；文件导入或未提供额度时只展示导入时间。原有订阅需手动刷新后获得额度；额度是服务商上次响应的快照，不是实时 VPN 计数。刷新仍沿用更新预览／应用流程，不直接连接 VPN。
- 验证：正常签名 Mac 构建、离线 Mac 构建、iOS/iPadOS Simulator 构建通过；10 项 Mac 订阅库回归通过，覆盖额度读取、删除清理与回滚保留。URLProtocol 下载回归覆盖标准／前缀响应头、缺失／异常／溢出数值及既有超时、取消、TLS 分类、重定向和大小限制，不访问真实网络。离线窗口检查有／无额度卡片、宽窄布局、单击选中与独立刷新区域。真机动效由用户确认；未修改当前 VPN 连接。
- 本轮回滚副本：`build/rollback/macos-subscription-usage-20261011/changes.json`。

## 2026-10-11 — 刷新图标后台更新与等高卡片

- 卡片刷新图标改为后台下载、完整校验及应用，不设置 `revisionPreview`，因此不弹更新预览。右键的检查更新／历史版本仍保留显式预览流程。
- 更新仍走现有 compare-before-commit 事务和版本历史。内容及选择未变化时只保留最新额度，不新增重复版本；内容变化时保存原版本供回滚。失败保留现有配置并使用原有简洁错误提示。
- 不自动改变 VPN 连接。正在连接／连接中的当前订阅禁用后台刷新；下载期间若外部状态变为使用该订阅，也会在应用前再次拒绝替换。
- 卡片信息区固定 54pt，总高度一致；没有用量时保留空白，把导入时间下沉到底部。额度更新仅在固定区域内过渡，图标与加载占位不变。菜单元数据重读不先清空，避免刷新图标消失后再出现。
- 英文相对时间移除 `min.` 的句点，显示 `Imported 3 min ago`。
- 验证：离线及正常签名 Mac 构建通过；11 项内存虚构订阅回归通过，新增后台应用无变化／有变化／过期候选、历史保留及选中订阅不变的检查。离线窗口确认有／无用量卡片外框等高与无用量时间下沉。未操作真实网络、订阅或 VPN，实际刷新动效仍由用户确认。移动端源码无改动。
- 本轮回滚副本：`build/rollback/macos-background-refresh-20261011/changes.json`。


### 连接期间刷新与拖入直接导入（2026-10-11）

- Mac 已连接时允许通过卡片刷新图标后台更新当前订阅；右键更新预览同样允许保存。更新只写入订阅库，不重启隧道、不发送切换节点命令，新配置下次连接时生效。连接／断开过渡中暂不更新当前订阅。
- 将运行中配置与订阅库保存版本分离：受保护的运行快照按隧道 session／配置摘要校验，节点、策略组、测速及流量继续使用运行版本。退出 App 再打开仍可恢复同一运行版本；完全断开后载入新版，仍存在的手动策略组选择按名称保留。
- 依赖回收增加 `#if os(macOS)` 保留根，保护运行版本的原始和编译依赖，防止连续刷新使原版本超出历史保留范围后无法切换节点。iOS／iPadOS 分支原样保留。
- 卡片取消选中勾号，保留背景／边框以及辅助功能选中语义，卡片高度和刷新区域不变。
- Mac 拖入文件完成结构、依赖与内核校验后直接保存，不弹导入确认，也不改变已有订阅选择或 VPN；无效文件只提示错误。文件选择器和 URL 导入保持确认流程。
- 验证：14 项 Mac 回归通过，覆盖 12 次连续更新后的依赖保留、扩展读取旧资源、运行版测速、重启恢复、session 不匹配拒绝、运行版节点切换、新版生效、有效／无效文件直接导入。离线窗口确认卡片无勾号且等高。Mac 正常签名和离线构建、iOS／iPadOS Simulator 构建通过。全部自动测试使用虚构数据及内存存储，未连接、更改现有 VPN 或下载真实订阅；真实连接下的网络连续性仍待用户体验确认。
- 本轮回滚：`build/rollback/macos-connected-refresh-drop-20261011/changes.json`。


### 局部刷新反馈与侧栏实时流量（2026-10-11）

- 确认刷新曾复用全局 `busy`，引起其他卡片刷新按钮、导入按钮与首页连接按钮同时变灰。现将事务串行协调与可见加载状态分离：后台刷新只更新对应卡片的加载图标，不显示全局加载。重复点击同一卡片会合并；不同卡片及其他操作按顺序执行，取消的排队操作不会提交。
- 排队执行前重新核对 VPN 状态和节点目录作用域，避免等待期间连接／订阅变化导致错误切换、删除当前连接配置或使用旧节点索引。当前卡片加载时保留图标的正常颜色，仅屏蔽重复点按。
- Mac 侧栏底部加入紧凑实时流量曲线及上下行读数，各页面常驻；与首页共用现有遥测窗口、刻度及贝塞尔路径，不增加 IPC 采样。未连接时显示空读数，支持减少动态效果，空窗口暂停逐帧绘制；保留原生侧栏材质。
- 新组件分别放在 `Horizon/App/Mac/Components/MacSidebarTrafficView.swift` 与 `Horizon/Services/Mac/MacLibraryActivity.swift`，仅加入 Mac 主 App target。iOS／iPadOS 工程和页面没有改动。
- 验证：15 项 Mac 库回归通过，新增后台操作不打开全局加载、FIFO 串行顺序及排队取消检查；Mac 正常签名及离线构建通过。离线窗口核对常规／窄侧栏布局与订阅页面，未使用真实订阅或更改现有 VPN。真实流量与刷新动效观感仍由用户确认。
- 本轮回滚：`build/rollback/macos-local-refresh-sidebar-20261011/changes.json`。


### Nodes 集中测速（2026-10-11）

- Mac 侧栏移除独立 Latency tests 入口；Nodes 统一提供单节点 Ping、测试所有节点、延迟／名称排序和搜索。保留节点矩阵及直接选择节点的交互。
- 将测试计数、最多 5 并发提示和停止操作迁入 Nodes，进度区与停止按钮固定占位，数字与显隐只做局部过渡并响应减少动态效果。排序在测试中保持可用，单节点测试仅展示实际计数。
- 删除不再使用的 MacLatencyTestsView、MacNodeRow 及其 Mac 工程引用；未修改 iOS／iPadOS 页面和测速服务。
- 验证：15 项内存 Mac 库回归检查通过，包括五并发、增量入队、单节点重测及旧作用域结果隔离；Mac 正常签名及离线构建通过。隔离的离线窗口确认侧栏仅保留五项，Nodes 的工具栏、测速提示和节点卡片显示正常；真实测速及动效观感由用户确认；未访问真实订阅或操作 VPN。
- 本轮回滚：`build/rollback/macos-nodes-integrated-tests-20261011/changes.json`。


### Nodes 状态稳定与首页墙壁悬停（2026-10-11）

- 检查确认节点选择只改变运行身份，不改变由订阅 UUID 与原文摘要构成的网格／测速作用域；补充回归断言，确保同作用域重载不清空结果。搜索仍可重建筛选网格，排序保留节点索引身份和位置过渡。
- 测速标签固定宽高，避免 Ping、等待、测试中、失败与数字结果改变同行排布。选中／悬停动画收窄至勾号、背景和边框，不再隐式作用于整张卡片；当前节点标题保持单行高度并局部淡变，进度总数也做局部过渡。
- 排序先解析每个显示名称，再比较缓存于本次计算的字符串／结果；原始顺序且无查询时直接返回索引，避免每次比较反复扫描目录。
- Mac 首页墙壁改为 AppKit 鼠标进入／移动持续反馈，移除墙壁点击的计时器和松开脉冲。连接按钮按 SwiftUI 实际几何范围排除，即使按钮禁用也不触发墙壁；离开可见墙壁、窗口失焦、隐藏页面或连接过渡时释放。原有已连接地球拖动保留；介绍场景不启用悬停互动，减少动态效果仍走原有渲染器降级。
- 验证：正常签名与离线 Mac 构建、15 项内存库回归通过；隔离窗口使用 18 个虚构节点检查节点选择、排序控件和等高卡片。源码状态及布局检查不等于动效验收；真实测速、排序连续性和鼠标悬停手感由用户在新版确认。未下载真实订阅或更改当前 VPN；iOS／iPadOS 源码和工程未改动。
- 本轮回滚：`build/rollback/macos-nodes-hover-20261011/changes.json`。


### Mac 侧栏页面过渡（2026-10-11）

- 确认此前主页面 switch 没有过渡。现在右侧内容使用 0.2 秒 easeInOut 淡入淡出，只由侧栏选择变化触发；侧栏、底部实时流量与根遥测任务不参与过渡，普通测速／流量更新不触发页面动画。开启减少动态效果时直接切换。
- 每个侧栏目标使用以页面为身份的 NavigationStack，移除跨页面共享的 NavigationPath，保留切换页面后返回目标起始层级的行为，避免旧子页面短暂残留。相同页面的订阅／状态更新不重建导航栈。
- 验证：Mac 正常签名和离线构建通过；隔离离线窗口核对 Nodes、Settings、Configurations 的内容与工具栏，以及 About → Configurations → Settings 返回设置起始页。未操作真实订阅或 VPN；淡入淡出连续观感仍由用户验收。iOS／iPadOS 无改动。
- 本轮回滚：`build/rollback/macos-page-transitions-20261011/changes.json`。


### Mac 介绍入场与场景连续性（2026-10-11）

- 确认 Part 1 文案此前没有独立入场状态；现在首次进入时标题、说明和导航区以 0.55 秒淡入并轻移 12pt，顶部标识和跳过按钮同步淡入。返回 Welcome 后再次进入可重播；初始隐藏时不参与点击或辅助功能。章节文案变化使用局部内容过渡，减少动态效果时取消位移与章节动画。
- Mac 指南正常阶段由 30 Hz 时间采样改为 60 Hz；Metal 地球在对应 SwiftUI Timeline 样本更新时直接提交绘制，避免 AppKit 延迟失效刷新造成合帧及与 Canvas 不同步。保留原有暂停、低功耗粒子降级、相机路径及交接确认逻辑；此项消除已发现的顿挫来源，不代表已测得稳定 60 FPS。
- 窄视口继续负责相机构图和地球交接，Mac 遮罩单独扩展到整个窗口宽度，移除横向硬裁切边缘；保留上下羽化及外层窗口裁切。共享组件新增参数均以原行为为默认值，iOS／iPadOS 调用不变。
- 验证：正常签名与隔离离线 Mac 构建、iOS／iPadOS Simulator 构建通过；现有指南回归覆盖 30／60／120 Hz 拉动、反向与取消、后台时钟连续性、相机和地球交接。隔离离线窗口走通 Welcome → 三章 → 地球交接 → 返回原页面，文案、地球和全宽场景均显示；动效连续观感由用户确认。未操作现有 VPN 或真实订阅。
- 本轮回滚：`build/rollback/macos-intro-continuity-20261011/changes.json`。


### Mac Welcome 文字退场裁切（2026-10-11）

- 排查发现 Welcome 虽在 680pt 居中列中排版，横向退场仍会被内部 ScrollView 和外层 VStack 的矩形裁切截断，形成可见竖直边缘。仅 macOS 对 ScrollView 使用 `scrollClipDisabled()`，并移除该列外层 `.clipped()`；最终由窗口边界裁切。
- 保留 680pt 排版、字号、文字错峰、1.5 秒退场曲线、淡出与按钮时机。iOS／iPadOS 继续使用原有滚动和外层裁切；以本轮前副本核对，去除 Mac 条件分支后移动端源码完全一致。
- 验证：正常签名 Mac、离线 Mac、iOS／iPadOS Simulator 构建通过；隔离离线窗口核对 Welcome 横向退场和 Part 1 入场，连续观感仍由用户确认。未操作现有 VPN 或真实订阅。
- 本轮回滚：`build/rollback/macos-welcome-exit-clip-20261011/changes.json`。


### Mac 指南返回与 Start（2026-10-11）

- 修复 Part 1 返回 Welcome 时立即移除文案容器的问题：返回过程先保留 Part 1 的页面身份，标题／说明／操作区完成 0.55 秒淡出和轻移、顶部元素完成淡出后再挂载 Welcome。相机同步开始原有 1.5 秒返回运动，剩余时间保留导航过渡锁；减少动态效果沿用短淡出并取消位移。任务随页面移除取消，期间恢复前台不会重新点亮正在退出的文案。
- Mac Part 3 按钮改为「开始／Start」及向右箭头，继续触发现有地球交接。下拉交互保留，iOS／iPadOS 文案与流程不变；本轮只修改 Mac 专属 View。
- 正常签名和离线 Mac 构建、现有指南交接回归通过；隔离离线窗口验证 Part 1 → Welcome → 重新进入指南与 Part 3 Start。动效观感仍由用户体验确认；未操作现有 VPN 或真实订阅。
- 本轮回滚：`build/rollback/macos-intro-back-start-20261011/changes.json`。


### Mac VPN 改名后的启动失败排查（2026-10-11）

- 现场系统日志证实 `startVPNTunnel` 已发出，但 neagent 对新版 `Kenote.Clash.Mac.PacketTunnel` 发起扩展请求时，仍访问旧 `Kenote.Horizon.Mac.PacketTunnel.apple-extension-service`，随后报 NSCocoaErrorDomain 4099 / No such process，系统以 Plugin failed 终止，尚未进入配置／内核启动阶段。运行构建的 Bundle ID、签名及授权有效；二进制内未残留旧 provider ID。由此定位为开发机改名后的扩展注册／服务缓存问题，而非订阅格式失败；不据此推断其他安装环境也一定存在该问题。
- 只对本机 Horizon 扩展执行 pluginkit 注销旧版与重复开发注册、再注册新版签名产物。核对现在仅一条新版注册、旧版无匹配。不移除 VPN profile、钥匙串或订阅，不操作其他 VPN；尚未进行真实连接复测，后台服务是否仍持有缓存需实测确认。
- Mac 连接操作现在等待系统真实 Connected；首次请求保留 1 秒状态送达宽限，开始连接后回到 Idle 立即按失败处理，最长等待 30 秒。失败读取系统最后断开错误，按固定安全分类给出双语言提示，保留 provider 固定错误码；取消／超时只停止本次 Horizon 隧道。解决请求提交成功却异步失败时没有提示的问题。
- 正常签名 Mac 构建与 16 项内存回归通过，新增覆盖即时／异步失败、真实连接成功、停止、超时及错误分类不泄露原始配置。实际 VPN 连接与流量转发尚待用户授权复测。只修改 Mac 服务与 Mac 检查脚本，iOS／iPadOS、共用内核和配置转换没有改动。
- 本轮回滚：`build/rollback/macos-vpn-startup-20261011/changes.json`。注册修复是本机开发环境操作，源码回滚不自动恢复旧注册；必要时可重新注册对应旧版 appex。

用户选择保留当前其他 VPN，稍后手动复测。已退出未连接的旧开发进程，打开 `build/MacUnifiedRecord/Build/Products/Debug/HorizonMac.app` 修复版；UI 核对当前订阅 Ken、Disconnected、Connect 可用，未发起连接。若再次遇到扩展启动失败，保留提示与时间继续核对缓存；不预先重启系统网络服务。
# Mac Smart Routing（2026-10-11）

- Mac 首页在实时流量与当前订阅之间提供「遵循订阅 / 智能分流」原生分段选择器，按订阅保存。点击立即反馈选中状态；后台准备期间不增加加载行、不使其他控件变灰。连接状态变化的库协调也不再触发全局 loading。
- 复用移动端现有 `ConfigurationRouting`、`SubscriptionResourceLoader` 与打包 Geo 数据，没有修改 iOS/iPadOS 工程、共享代码或核心。原规则优先，在末尾 MATCH 前增加国内域名/IP 直连，保留显式 DNS 策略。不能保证所有国内服务都直连；原有规则仍可优先代理。
- 准备与完整内核预检在 Mac worker actor 内执行，复用缓存 provider/Geo，不发起依赖下载。原文、来源链接与历史保留。关闭智能分流恢复原订阅策略。证书确认绑定版本，不能由分流切换隐式批准。
- 未连接时只保存；已连接时先完成准备与预检，再等待 Horizon 隧道停止、提交并重新连接。如果准备期间连接已改变则终止操作。更新过的订阅采用最新保存版本，并保留仍有效的运行中手动节点选择。
- 启动失败后，确认隧道停止再通过比较版本回滚保存的配置；不会覆盖其他写入者，也不会静默重连未经验证的待生效版本。此时保持未连接并显示失败提示。若系统连停止状态都无法确认，则先报错，不在运行中替换源配置。
- 22 组离线回归通过，包含真实 Mac framework 的 Geo/规则预检、provider 缓存复用、原文/DNS 优先级、切回、证书确认、失败回滚、过期事务与原测速/刷新行为。所有测试使用虚构数据和内存存储；未连接真实 VPN。Release 与开发签名 Debug 构建通过。
- 回滚快照：`build/rollback/mac-smart-routing-20261011/manifest.json`，含本轮前文件与移动/共享文件基准哈希。新增组件为 `Horizon/Features/MacHome/Components/MacRoutingPickerView.swift`。

## 21:45 截图中的扩展启动失败

同一时段系统日志（21:45:53）请求新标识 `Kenote.Clash.Mac.PacketTunnel`，但 XPC 仍指向 `Kenote.Horizon.Mac.PacketTunnel.apple-extension-service`，报 `NSCocoaErrorDomain 4099 / No such process`，随后 `Validation of the extension failed / Plugin failed`。本次失败尚未进入节点、DNS 或分流规则阶段。

只读检查发现两个开发构建位置均注册了新标识。新构建主 App/扩展标识、Network Extension 授权、Team 与描述文件一致，严格签名验证通过。证据指向本机此前改 Bundle ID 后的旧服务/注册缓存；仅重新构建并不能证明该缓存已清除。下一步应退出重复开发副本、保留一个安装位置，重启 Mac 后由用户复测。不要通过删除用户订阅/Keychain、关闭证书校验或改回旧 Bundle ID 来绕过。

本轮仅构建和只读诊断，没有安装/启动 App、终止系统服务、添加/删除 VPN 配置或改变网络连接。真实连接与动效观感仍待用户验证。

# Mac UDP 沙盒权限回归

Mac 主程序（独立节点测速）与 Packet Tunnel 扩展均需要 `network.client` 和
`network.server`。Go 的 UDP ListenPacket／QUIC 会绑定本地 UDP 端口；仅声明
client 时，本机签名沙盒验证得到 EPERM。此权限不启用代理监听器，内核的
本地控制端口仍保持关闭，也不改变 iOS／iPadOS 的权限。

使用 `python3 scripts/check-macos-network-sandbox.py --identity <本机开发签名身份>`
可复现 client-only 失败、App／Tunnel 权限成功的对照。该测试只绑定回环 UDP
端口，不发送数据、不连接 VPN。实际节点连通性仍需单独验证。



## 2026-10-12 — Mac App Store 上传准备及服务器验证

- Mac 主 App 接入移动端现有 `Horizon/Assets.xcassets` 的 `AppIcon`，补齐 macOS 16/32/128/256/512pt 的 1x/2x 槽位。1024px 图案直接复用 `download.png`，其余尺寸从原图缩小生成；iOS 原有三个槽位及原图保持不变。Mac Debug/Release 的 Primary App Icon Set Name 均为 `AppIcon`。
- `Configuration/Mac/App-Info.plist` 增加 `NSHumanReadableCopyright = Copyright © 2026 Horizon. All rights reserved.`。
- 首次 Organizer Validate App 返回服务器错误 90347：扩展 Bundle ID 在主 App ID 后只能再有一层句点。因此 Mac 扩展由 `Kenote.Clash.Mac.PacketTunnel` 改为 `Kenote.Clash.MacPacketTunnel`，同时更新 `MacVPNController.providerID`；主 App 仍为 `Kenote.Clash`，移动端仍为 `Kenote.Clash.PacketTunnel`。共享钥匙串组及其权限不变。Xcode 已取得新扩展标识的 Mac 开发 provisioning profile。本轮未修改旧 VPN profiles；以后用户显式 Connect 时会使用新标识，可能需要重新允许添加 Horizon 的 VPN 配置。
- 最终 Release 归档：`build/HorizonMac-AppStore-Ready.xcarchive`，版本 `1.0 (1)`；App 和扩展均含 arm64/x86_64。图标、版权字段、Bundle ID、profile、实际签名权限、版本一致性及 codesign 严格验证通过，非离线演示构建。22 项 Mac 离线功能回归通过；独立 iOS Simulator actool 编译通过，移动端源码、工程及原图摘要与本轮开始前一致。
- 已在 Xcode Organizer 执行真实 App Store Connect Validate App，最终结果：`HorizonMac 1.0 (1) validated — Your app successfully passed all validation checks.`。仅验证，没有上传构建或提交审核。正式上传选择本次 Ready 归档，执行 Distribute App → App Store Connect。不要使用本轮 12:17 的旧标识归档（其状态为 Validation failed）。
- 本轮未启动新 App、连接 VPN 或更改其他 VPN；原开发扩展注册仍仅有 canonical Xcode Debug 副本。实际 VPN 功能仍待用户连接复测，服务器验证通过不代表运行功能验收。
- 日志：`build/mac-store-ready-archive.log`、`build/mac-store-library-tests.log`、`build/mac-store-ios-icons.log`。回滚副本及前后摘要：`build/rollback/mac-store-readiness-20261012/manifest.json`；恢复其中 files 并移除 newFiles 即可撤回本轮源码／资源改动。


## macOS 个人订阅 iCloud 同步（2026-10-12）

原生 Mac 的「设置 → iCloud 同步」现已接入移动端同一个 `iCloud.Kenote.Clash` 私有容器、`PersonalSubscriptionsV1` zone、V1 加密字段和资源格式。默认关闭，用户确认开启后才注册 APNs／访问 CloudKit；Mac 离线预览强制不访问云端。没有创建新 schema，也没有修改 Production 数据。

共用 `SubscriptionCloudSyncEngine`、资源缓存、三方合并／删除 tombstone、账户切换保护和审核通知记录；Mac 单独负责应用生命周期、设置／审核界面及串行库协调。新增、改名、更新和删除会触发合并后的主动同步，回到前台主动拉取；「立即同步」真实发起请求，成功后图标 Replace 为勾号，停留一秒恢复。时间按分钟显示，小于一分钟为「刚刚」。

自动接收只更改非当前订阅并刷新摘要，不重建当前运行配置／测速 scope。当前订阅更新／删除和并发冲突保留待审核入口；连接期间禁止处理当前订阅，审核不会自动连接或断开 VPN。订阅页面发现新待审核版本后，在导航／弹窗稳定后简要提示，先关闭提示再跳转。关闭同步保留本机和云端数据。设备当前订阅、节点选择、智能分流、证书风险确认、历史版本与测速结果不参与同步。

Mac 主 App 增加 CloudKit 和 macOS APNs 权限；扩展权限和 bundle ID 不变。Debug 使用 Development，Release 使用 Production，与移动端环境约定一致。Mac Release 与 iPhone／iPad TestFlight 才能看到同一个正式环境数据；Debug 与 TestFlight 的数据库相互隔离。唯一共用源码改动是为原生 Mac 的 `ConfigurationImportWorker.validate` 启用同样的原生内核预检；iOS 条件分支和移动工程未改。

验证：31 项 Mac 内存／虚构数据检查，包括云端内容往返、当前订阅更新／删除保护、无效内容拒绝、保留本地 Smart Routing／Geo 缓存／节点选择、冲突日志隔离、明确开启、同步请求去重、修改后主动同步和前台重新拉取；移动端 5 个同步 suite 共 30 项测试通过。Mac Debug 签名构建、Release 通用二进制归档与严格签名验证通过。没有开启真实同步、上传用户订阅或更改 VPN。跨设备实际同步及界面动效仍待用户实机确认。

本轮回滚快照：`build/rollback/mac-icloud-sync-20261012/manifest.json`。保留旧的已通过 ASC 校验的归档；新功能归档为 `build/HorizonMac-iCloud-Ready.xcarchive`，尚未上传 App Store Connect。


### 2026-10-12：Mac 同步完整性与延迟排查

已确认的客户端问题：Mac 失去键盘焦点会取消同步观察；原有三秒 tick 只处理本地队列，没有主动拉取远端；导入提交后、记账前的取消存在衔接缺口。用户报告的实机“四份只显示一份”仍需新版 Production 验证，不能把离线用例当作真实云端根因证据。

- Mac 同步观察不再随窗口焦点退出；回到前台主动拉取，前台 30 秒／非前台 120 秒进行一次兜底远端检查，仍使用 CKSyncEngine 增量游标。
- Mac 首次启动同步、手动 Sync now 和重试时额外遍历完整订阅元数据清单（所有分页），独立于增量游标；仅请求 payload/digest/bytes，不批量下载所有资产。缺失头信息进入原有验证、依赖下载、合并和当前订阅保护流程，不依据清单缺项删除本机订阅、不重置引擎状态。
- 完整清单分页期间若正常同步已观察到更新版本，保留新的观察结果；分页失败／取消不会当作完整清单。该核对实现只加入 Mac target。
- 共享引擎在落库成功后先确认并持久化安装记录，再检查取消；确认不会抹掉后续远端版本。快照存在待处理传输或隔离记录时不再被 fetch 成功回调误报为 ready。没有改变冲突选择或当前订阅的自动覆盖策略。
- 诊断只记录云端批次数量、完整清单头数量、本机订阅数量、阶段分类和 CloudKit 错误码，不记录订阅名称、链接、Token、凭据或账户／记录标识。页面布局保持不变。

验证：35 项 Mac 离线检查、31 项移动端云同步测试通过；包括分页从本机 1 份恢复到 4 份、失败／取消、失去焦点后的修改触发、手动核对跨快照保留落库标记，以及前台／非前台兜底间隔。Mac Release 构建与签名归档成功。未安装到用户设备，未上传用户数据、修改云端 schema 或改变 VPN。

归档：`build/HorizonMac-CloudCompleteness.xcarchive`（沿用现有版本号；再次上传前需使用未上传过的构建号）。日志：`build/mac-cloud-completeness-tests.log`、`build/mac-cloud-completeness-mobile-tests.log`、`build/mac-cloud-completeness-archive.log`。本轮回滚快照：`build/rollback/mac-cloud-completeness-20261012/manifest.json`。

### 2026-10-13：本地 Run 的扩展注册整理

00:17 的系统日志显示：开发版发起连接时实际启动了 `/Applications/HorizonMac.app` 的扩展，随后 NetworkExtension 报 `Signature check failed` / `Validation of the extension failed`。当时 PlugInKit 同时注册了四份相同标识的扩展。

Mac shared scheme 的 LaunchAction 新增 Run pre-action，执行 `scripts/prepare-macos-extension.py`，由 Xcode 的 `TARGET_BUILD_DIR/FULL_PRODUCT_NAME` 选择当前构建。先验证主程序和扩展 bundle ID、签名及 Horizon VPN 未连接，再注册当前构建、移除其他同标识扩展的注册。不会删除 App、数据、钥匙串或 VPN 配置，不会连接／断开或操作其他 VPN；Horizon 隧道运行或过渡中跳过。脚本失败尝试恢复先前的注册集合。只影响本地 Run，不进入 App 包，也不参与 Archive 或移动端工程。

手动运行（默认不修改，确认计划后追加 `--apply`）：

```sh
/usr/bin/python3 scripts/prepare-macos-extension.py --app /absolute/path/HorizonMac.app
```

需要恢复已安装版时，可指向 `/Applications/HorizonMac.app` 并追加 `--apply`。重新启动或安装其他同标识副本可能使系统重新发现它们；因此后续 CLI 构建运行也应先执行同一脚本。Xcode Run 的日志／登记快照写入 `PROJECT_TEMP_DIR/horizon-extension-registration.json`。若 pre-action 失败，应先查看 Run 的准备日志，而非继续连接。

本轮已将注册从四份收敛为当前 Release 构建一份，五项离线安全检查通过。尚未执行真实连接测试，不能据此认定启动签名问题已全部解决。旧 scheme 保存在 `build/rollback/mac-extension-launch-20261013/`；实际整理前后的登记快照保存在 `build/mac-extension-registration-applied.json`。

## 2026-10-13：Mac 共享动态内核减重

正式 `HorizonMac.xcodeproj` 的主 App 与 Packet Tunnel 现在链接同一个动态 `Hako.framework`，只在主 App 的 `Contents/Frameworks` 嵌入、签名一份。扩展通过现有 `@executable_path/../../../../Frameworks` 加载；不在扩展内再复制内核。Bundle ID、VPN 权限、订阅格式、智能分流、云同步及页面代码未改。

`scripts/build-macos-dynamic-core.py` 从现有完整静态 SDK 分架构取出归档，使用 `force_load` 封装为 extension-safe 动态 Framework，再合并 arm64/x86_64。Go 源码、工具链、补丁和 build tags 不变，协议没有裁剪；只去除调试符号。原静态 SDK 保留在 `.build/macos/artifacts/Hako.xcframework`，动态 SDK 独立输出为 `HakoDynamic.xcframework`。`build-macos-core.py --build` 在生成静态 SDK 后自动完成此步骤。Xcode Embed Frameworks 的 CodeSignOnCopy 为 App 内副本重新开发／分发签名。

可复验：

```sh
# 已有 HakoSymbols.xcframework 时，只重封装 Mac 动态 SDK。
# 首次迁移旧的无符号 SDK：python3 scripts/build-macos-core.py --build
python3 scripts/build-macos-dynamic-core.py
python3 scripts/check-macos-core.py
python3 scripts/check-macos-library.py
python3 scripts/check-macos-dynamic-runtime.py
```

归档 App 的逻辑文件大小（十进制 MB，未压缩；不是 App Store 下载大小）：

| 内容 | 此前静态归档 | 本次动态归档 |
| --- | ---: | ---: |
| 主程序 | 128.93 | 6.52 |
| Packet Tunnel | 125.24 | 2.51 |
| 共用动态内核 | — | 135.91 |
| 完整 App | 285.73 | 176.51 |

基准为 2026-10-12 20:59 的已存档 Mac App；本次归档为 `build/HorizonMac-SharedDynamic.xcarchive`，减少约 109.22 MB／38.2%。两者均保留 Intel 与 Apple Silicon。共享文件减少磁盘占用，两个进程仍各自初始化 Go runtime，不据此声称运行内存减半。

验证：Debug、Release 构建及 Release Archive 成功；App／扩展／Framework 严格签名通过；归档中恰好一份内核，主程序和扩展无静态 Go metadata，双方的 rpath 与动态依赖正确。原生内核兼容检查、39 项 Mac 离线功能检查通过。arm64 与 Intel/Rosetta 各完成三轮真实 Go 初始化、五并发无效输入处理、取消及进程退出。161 项移动工程／锁文件／内核产物摘要全部不变。未修改移动源码、未连接 VPN、未上传 App Store Connect；真实节点连接和 ASC 服务端验证仍需后续确认。

回滚快照：`build/rollback/mac-shared-dynamic-core-20261013/manifest.json` 与 `originals/`。同目录 `restore.py` 默认只核对计划，传入 `--apply` 才恢复本轮五个既有文件、移除三个新增脚本；若发现后续改动则拒绝覆盖。原静态 SDK 与旧归档保留，不需要删除订阅、缓存、钥匙串或 VPN 配置。恢复后重新构建 Mac 工程即可。验证摘要保存在 `build/mac-shared-dynamic-report.json`。


## 2026-10-13：Mac 首页 Ping 过渡、散开帧率与订阅额度核查

本轮仅改变原生 Mac 行为。首页 Ping 原有 numericText 没有对应动画事务，现独立为 MacHomePingView，结果采用局部 0.3 秒 smooth 过渡并保留固定按钮宽度；减少动态效果、隐藏首页时不播放。测速业务、队列、网络和连接流程未改。

Mac 首页 Metal surface 将正常 60 Hz 请求映射为最高 120 Hz，供高刷新率屏幕呈现散开动画；MTKView 按屏幕能力调度。Intro 仍为 60 Hz，原有低电量／严重热状态 30 Hz、隐藏暂停、减少动态效果、粒子数量、MSAA 和散开曲线保持原样。没有修改共享 renderer、particle pass 或移动端帧率。离线 Release 场景测量使用真实 renderer、几何及 shader：原先 draw 回调平均间隔约 16.67 ms，适配后约 8.34 ms；两组均无超过 25 ms 的间隔。独立 GPU 离线测量散开帧不到 1 ms，尚未复现真实 VPN 断开时的明显卡顿，因此本轮是已验证的帧率适配，不能据此认定实际断开卡顿的完整根因或视觉验收完成。用户需在新版中确认观感；未连接／断开任何 VPN。

订阅额度仍来自服务商 HTTP Subscription-Userinfo（含支持的对象存储镜像头），不是本机流量统计。确认原逻辑支持大小写、空白、缺少字段、超额、UInt64 溢出及刷新后保存；但异常可选 expire 会连同有效额度丢弃。仅 macOS 条件分支现在忽略负值、null 等不可用过期时间，重复过期时间作为未知；金额计数的歧义或错误仍拒绝。卡片在总额度已知、用量不全时显示“额度 · 用量未知”，不会假定缺少计数为零；没有有效上限但已用已知时显示“已用”。卡片高度保持不变。不提供用量头的服务商、文件导入、尚未刷新来源的 iCloud 新增副本仍不能凭空显示最新账户额度。

验证：40 组 Mac 离线功能回归、已有下载 URLProtocol 回归、签名 Release 构建通过。下载测试未请求外部服务器。移动端指纹仅共享 SubscriptionDownloader 文件不同，移除新增 macOS 条件块后与本轮前逐字节一致，其余移动端文件及工程摘要一致。日志：build/mac-home-feedback-build.log、build/mac-home-feedback-tests.log、build/mac-home-download-tests.log；场景测量：build/mac-scene-timing-before.json、build/mac-scene-timing-after.json。独立回滚快照：build/rollback/mac-home-feedback-20261013/，restore.py 默认只检查，传入 --apply 恢复；有后续改动时拒绝覆盖。


## 2026-10-13：Mac 首页连接按钮闪烁与过渡

确认 MacLibraryStore.test 的短暂准备使用了默认 showsActivity=true，切换全局 busy，导致首页原生玻璃连接按钮 disabled 来回变色。测速准备及测速证书确认分支改为 showsActivity=false，仍使用同一个串行 activity，不改测速并发、凭据校验或连接业务。真正连接的证书确认继续显示原有全局活动状态。

首页连接按钮独立为 MacConnectionButtonView，文字使用 opacity、图标使用原生 replace、宽度及居中布局采用局部动画。业务操作中的瞬时锁使用 hit testing 和 action guard，原生 disabled 只保留给离线／没有订阅的不可用状态；保留阻止重复连接／断开、减少动态效果和无障碍交互保护。测量胶囊实际范围后再加居中 frame，避免把整幅墙误当成按钮区域。仅 Mac 文件与独立 Mac 工程修改。

验证：签名 Release 构建与 40 组离线回归通过。独立离线 SwiftUI 窗口验证准备及断开锁定时点击计数不增加，按钮恢复后点击计数正常增加，Connect／Disconnect 测量宽度分别约 149／166pt，没有占据整个场景；仅核对状态、布局与点击保护，动画观感仍由用户确认。实际 Horizon 首页已显示新版 mac.home.connection 标识、原订阅及 Disconnected；未执行真实 Ping 或改变 VPN。移动端源码及工程指纹全部一致。日志：build/mac-connection-feedback-build.log、build/mac-connection-feedback-tests.log。独立回滚：build/rollback/mac-connection-feedback-20261013/restore.py（默认检查，--apply 恢复；拒绝覆盖后续修改）。


## 2026-10-13：Mac 连接按钮间距

移除连接／断开图标的 18pt 固定宽度，使用符号自然宽度；额外水平内边距由 22pt 调整为 16pt。原生玻璃样式、按钮高度、图文间距、局部状态过渡及墙壁命中排除保持不变。仅修改 MacConnectionButtonView，不改连接业务。

验证：Release 构建通过；离线独立窗口 Connect／Disconnect 胶囊宽度约 132／150pt（此前 149／166pt），两种状态正常显示。220 个移动相关文件指纹与本轮前一致。具体观感仍由用户确认。回滚快照：build/rollback/mac-connection-spacing-20261013/，restore.py 默认只核对，--apply 恢复且拒绝覆盖后续修改。


## 2026-10-13：Mac 离开订阅页后的侧栏事件保护

用户报告右侧仍能操作、主要在离开 Configurations 后侧栏偶发失效。已核对 /Applications 中商店收据版为 1.4，最初工具打开的本地副本为 1.3；随后切到已安装 1.4 作基线。常规切换与跨侧栏框选未现场稳定复现卡死，不据此认定问题不存在。

源码确认框选的窗口级 NSEvent 监听只依赖窗口、hidden 与几何范围，不读取当前导航页；SwiftUI 淡出保留旧视图期间仍可能满足这些条件。已有 bounds 修复不处理事件归属。丢失 mouse-up 后，下一次区域外 mouse-down 没有清理 origin，后续 mouse-up 仍会被旧手势吞掉。离线生产处理函数对照验证了这些缺口。

MacRootView 向订阅页传入实时页面选择闭包，每次事件与自动滚动 tick 都核对当前页；退出、隐藏、不可操作及销毁时取消手势、计时器、监听，并释放自身 first responder。新 mouse-down／上下文菜单开始前取消残留手势。开始框选还必须位于实际 NSScrollView viewport 内，且窗口 hit-test 命中属于该 viewport，避免捕获其他页面、侧栏或工具栏。保留已有拖动跨区域结束、右键、刷新、键盘全选、页面淡入和 Metal surface 生命周期；未重构 NavigationStack。

验证：scripts/check-macos-selection-events.py 的 20 项离线事件回归通过；改动前的处理函数在离页保留视图、遗失 mouse-up、覆盖内容及离页键盘事件用例中失败。测试使用隐藏 AppKit fixture 直接调用生产事件处理函数，不向桌面投递事件。签名 Release 构建通过；实际修复版窗口完成框选后回 Home、八次跨侧栏切换、搜索、导入提示取消、全选与 Escape 清理，均正常响应。220 项移动相关文件指纹一致，未修改移动端 UI、动画或网络业务，未连接或断开 VPN。偶发实机场景仍需用户继续确认。

当前运行的是本地修复版（沿用工程 1.4 构建号），没有覆盖 /Applications TestFlight 副本、没有上传；后续发布需使用新构建号。日志：build/mac-sidebar-event-build.log、build/mac-sidebar-event-tests.log。回滚：build/rollback/mac-sidebar-events-20261013/restore.py，默认只核对，--apply 恢复且拒绝覆盖后续修改。


## 2026-10-13：Mac 内核 dSYM 生成与归档

App Store Connect 提示的两个 UUID 对应上传归档中 Hako.framework/Versions/A/Hako；主 App 和扩展已有匹配 dSYM。旧流程从已使用 Go `-s -w` 剥离符号的静态 SDK 生成动态内核，因此只对旧产物运行 dsymutil 无法补回真实调试信息。

Mac 独立构建现在使用上游明确用于保留 symbols/build IDs 的 `-debug` 参数，输出 HakoSymbols.xcframework；该参数没有关闭 Go 优化，也未启用单独的 `-internal` 诊断标签。锁定版本、补丁、协议标签与双架构均保持。动态封装在链接对象仍存在时先生成 Hako.framework.dSYM，检查真实 Go 函数及源码行号和两架构 UUID，然后照旧 strip -S 发布二进制。通过 `xcodebuild -create-xcframework -debug-symbols` 登记独立 dSYMs，Xcode Archive 自动收录，无需改工程或手动复制阶段。原 Hako.xcframework 保留。

```sh
python3 scripts/build-macos-core.py --build
python3 scripts/check-macos-symbols.py
# 用 Horizon Mac scheme 重新 Archive 后：
python3 scripts/check-macos-symbols.py --archive build/HorizonMac-Symbols.xcarchive
```

已验证 Release Archive 成功、严格签名通过；归档中主 App、扩展、内核的 arm64/x86_64 dSYM 均匹配。内核实际地址可通过 atos 还原为 Go NewService 函数及 service.go:76，而非只生成空符号文件。归档仅嵌入一份共享内核，没有将 dSYM 装入 App。内核仍为 135,911,664 字节，与此前减重版一致；App 176,547,406 字节（176.55 MB，双架构未压缩逻辑大小），已上传归档为 176,546,169 字节。符号文件增大开发归档／SDK 占用，不增大用户安装包。

146/146 项离线内核自检、双架构 Swift 导入／链接、arm64 与 Rosetta 各三轮真实动态 Go 初始化及退出通过；未改变 VPN。381 项移动源码、工程与移动产物指纹一致。验证产物：build/HorizonMac-Symbols.xcarchive；摘要：build/mac-core-symbol-archive-report.json；日志：build/mac-core-symbol-{build,archive,runtime,regression}.log。本轮没有上传到 Apple，旧归档不会自动得到新二进制的符号；下次上传需使用新构建号重新 Archive（验证归档沿用工程 1.4）。

回滚：build/rollback/mac-core-symbols-20261013/restore.py。默认只检查，--apply 才恢复本轮脚本、文档、旧动态 SDK、内核清单与许可证；检测到后续改动时拒绝覆盖。新生成的 HakoSymbols.xcframework 可作为缓存保留，回滚后的脚本不使用它。需要恢复运行版本时再重新构建 Mac；无需清理订阅或 VPN 配置。


## 2026-10-13：Mac 菜单栏入口

在独立 HorizonMacApp Scene 中加入原生 MenuBarExtra（menu 样式），使用 globe.europe.africa，已连接时切换为填充版本；菜单显示真实 VPN 状态、当前订阅与节点，提供连接／断开、订阅选择、手动策略组成员选择、打开主窗口、设置和退出。当前节点无法解析为具体代理时显示“由策略组决定”，不虚构节点。名称遵循已有隐私显示设置和中英文语言设置。

MacMenuBarActions 复用主窗口同一个 MacLibraryStore／MacVPNController，不创建第二份 VPN 会话或配置库。连接使用既有连接确认及证书授权流程；提示、失败会打开主窗口。忙碌、切换中、导入／更新预览、证书确认和错误提示期间保护操作；节点切换验证菜单捕获的 probeScope 与当前配置一致。手动组按现有语义切换，自动组不提供强制选项；连接期间禁用整份订阅切换，节点切换继续走现有 runtime selection 路径。关闭主窗口保留进程和菜单，显式退出沿用现有退出行为，不额外调用断开 VPN。导航选择提升到 App 持有，菜单可重开原窗口或跳到设置、节点和订阅页面。VPN 状态对配置库的协调从窗口 onChange 移到 MenuBarExtra Scene，窗口关闭后仍保留。

验证：Debug、Release 构建通过；Mac 离线功能回归 45 组通过，新增覆盖未就绪／离线连接保护、真实共享配置库切换、过期菜单、无效节点、弹窗及证书确认保护。隔离 Debug 预览使用独立 bundle ID、移除测试副本的 VPN 扩展且显式 --offline，仅使用虚构订阅；关闭主窗口后进程仍在，测试后退出预览。自动化工具未能直接访问屏幕顶部状态栏项目，因此菜单展开、跳转及真实连接的最终操作体验待用户确认，没有以编译通过替代实际体验验收。未改动 TestFlight 安装或真实 VPN 连接；381 项移动源码／工程／产物指纹一致。当前生产 app 未自动替换运行。日志：build/mac-menu-bar-build.log、build/mac-menu-bar-debug-build.log、build/mac-menu-bar-tests.log。

回滚：build/rollback/mac-menu-bar-20261013/restore.py，默认核对，--apply 恢复本轮既有文件并移除新增文件；检测到后续改动时拒绝覆盖。菜单栏功能只加入原生 Mac 工程，不改变移动端、内核、减重或符号打包流程。

### 2026-10-13 · Configurations input ownership and connected switching

- Mac-only. Connected activation was explicitly blocked by the grid, context menu and store. Mac now follows the mobile interaction: idle activation is immediate; connected activation asks for confirmation, validates the target while the old tunnel remains intact, waits for disconnection, activates/loads the target, then reconnects through the existing certificate-consent path. Cancel does not change the selected subscription or tunnel. Menu-bar and detail entry points share the request/confirmation flow. Transitional VPN states remain unavailable.
- Removed the Configurations app-wide local event monitor. The overlay now receives its own native AppKit mouse-down/drag/up and responder-chain keyboard events, using superview-coordinate hit testing limited to its bounds and actual scroll viewport. Outgoing/hidden/disabled pages cannot become a selection target. Native refresh targets and context menus pass through; a context menu on an unselected card targets that card without changing the current multi-selection.
- Evidence boundary: the original persistent sidebar failure was not reproduced reliably. The removed monitor was capable of dropping application events before dispatch; this removes that failure path, but does not establish it as the only cause of every reported failure.
- Verification: Debug and Release builds passed; 48 offline library regression groups passed, including fail-fast activation stage ordering and cancellation guards. Hidden AppKit/SwiftUI fixtures passed 21 routing assertions plus 100 outgoing-page state cycles. Independent offline app mouse checks covered single-click activation, Command-click, marquee, batch context menu, and repeated Configurations → Home/Nodes/Groups/Settings navigation. No real VPN connection/disconnection, Keychain subscription mutation or cloud synchronization was performed. The independent preview was quit; installed TestFlight app was not replaced. Real reconnect and visual feel remain for user validation.
- Logs: `build/mac-selection-{build,debug-build,library,events}.log`. Rollback snapshot: `build/rollback/mac-selection-switch-20261013/` (guarded restore; preserves unrelated changes). Mobile files remain identical to the turn baseline.

### 2026-10-13 · Restore Mac sidebar page fades

- Reproduced in an independent offline Debug copy with animation instrumentation: the original root receives an animated selection transaction followed immediately by an unanimated navigation update. Its Home opacity jumps between 1 and 0 without any intermediate frames. This was an execution issue; the 0.2-second fade had not been removed for the earlier mouse fix.
- `MacRootView` now owns `presentedPage` separately from the app's selected `page`. A cancellable `.task(id: page)` yields out of the native sidebar selection transaction, checks that the destination is still current, and changes the presented page in an explicit animation transaction. The incoming/outgoing pages therefore animate independently of native selection follow-up updates. No timer or fixed navigation delay was added. Reduced motion still uses immediate transitions.
- Outgoing page input is disabled as soon as the selected destination changes. Home's Metal surface retains its lifetime and remains paused when hidden. Configurations keeps its live page-ownership gate and view-local mouse handling.
- Runtime evidence: five page destinations all produced intermediate opacity values after the change. Tested marquee → sidebar navigation, sequential and rapid page changes, Settings → About → Home → Settings (returns to root), and matching final sidebar/detail selection. The animation probe used an opacity-only animatable modifier equivalent to the production opacity transition; all probe code was removed before the final Release build. Visual feel remains for user validation.
- Final Release build passed. Existing selection checks passed (21 routing assertions plus 100 retained-view state cycles). Protected mobile/shared files matched the turn baseline. No VPN, real subscription, or cloud operation was performed. The independent offline copy was quit; installed TestFlight app was not replaced.
- Evidence/logs: `build/mac-page-baseline-trace.log`, `build/mac-page-fixed-trace.log`, `build/mac-page-all-trace.log`, `build/mac-page-animation-evidence.json`, `build/mac-page-fade-release-build.log`, `build/mac-page-fade-selection-check.log`. Rollback: `build/rollback/mac-page-fade-20261013/restore.py` (dry run by default, refuses later edits).

### 2026-10-13 · Five-second checks while Configurations is selected

- Mac root starts a cancellable destination clock while Configurations is selected, synchronization is enabled/allowed, and Intro is absent. Leaving the destination stops future checks immediately, including during page fade-out. Removed the old one-off destination task to avoid two independent entry owners.
- The store waits until five seconds after the latest completed remote check. Entry during that cooldown waits only its remaining interval, then retries instead of dropping the request. The clock waits for existing manual/poll operations and reuses the store-owned incremental page refresh. It does not perform a full inventory every five seconds. A slow request extends the interval; requests never accumulate or overlap. Away from Configurations, existing foreground/background scheduling stays intact.
- Cancelling the destination clock does not cancel an already started store-owned refresh. Subscription cards continue to use the same library busy/selection state; no preview is opened, no active runtime is replaced, and the existing review protections remain intact. No UI layout, mobile source, shared CloudKit engine, payload, schema, or permissions changed.
- Verification: Release build and 50 offline regression groups passed. Added deterministic clock tests for repeated five-second checks, remaining-deadline entry, no repeated inventory, enabled library controls, stopping on exit, and preservation of in-flight sync after exit. Protected mobile/shared file hashes match the turn baseline. Tests use fake clients and memory-only subscriptions; no real CloudKit, Keychain or VPN operation. Runtime CloudKit delivery latency remains outside the five-second scheduling interval.
- Logs: `build/mac-config-five-second-build.log`, `build/mac-config-five-second-tests.log`. Rollback: `build/rollback/mac-config-five-second-sync-20261013/restore.py` (dry run by default, refuses later edits).


### 2026-10-14 · Native section changes from secondary pages

- Mac-only follow-up after reverting the staged fade implementation. Native List selection, NavigationStack, view-based links, per-section identity and root-level 0.2-second page fades remain. When a pushed destination is visible, the sidebar binding captures that state before native navigation dismisses it and updates the presented section without custom animation. Menu-driven page changes use the same policy. Returning normally to a root page restores the existing page fade; reduced-motion handling and Home surface lifetime remain unchanged.
- A small MacSubpageTracking modifier reports visible destinations with independent tokens, covering About, iCloud Sync and cloud review pushes. The binding is captured explicitly at the NavigationLink site and passed into the destination because the native destination's separate environment did not inherit the custom optional binding in runtime checks. Tokens allow nested callback ordering without taking ownership of the navigation path. Standalone previews safely use a nil binding.
- Isolated offline UI checks and temporary logs confirmed Home → Settings uses the existing fade, About → Nodes and iCloud Sync → Home skip it, Nodes → Settings uses it again, and About → Back → Configurations also uses it. Native sidebar selection and Back controls remained functional. 121 selection-event checks passed. Debug diagnostic and final Release builds passed. Motion feel remains for user validation. Temporary diagnostics were removed; offline preview was quit. No real VPN/CloudKit operation or TestFlight replacement was performed, and the already running comparison app was not restarted.
- Logs: `build/mac-native-subpage-{trace,selection-check,release-build}.log`. Rollback: `build/rollback/mac-native-subpage-switch-20261014/restore.py` (dry run by default; refuses later edits). All unrelated source/project/resource hashes match the turn baseline, including iOS/iPadOS and shared code. Mac build number remains 1.5.3.


### 2026-10-14 · Match Mac automatic refresh to Sync now completeness

- User reports Configurations on TestFlight 1.5.4 stays stale while Settings → Sync now usually updates promptly. Code confirms a functional difference: only startup/retry/manual rounds requested `reconcileCloudLibrary`; the five-second page refresh, focus/edit trigger and 30/120-second remote fallback used CKSyncEngine incremental fetch alone. Recent local CloudSync logs contain a received batch and a later successful inventory (33 cloud heads, 4 local subscriptions, no pending/rejected items), but do not prove which phase caused the user's particular delay.
- All Mac explicit remote rounds now share `checkRemoteLibrary`: incremental fetch/send followed by the existing cloud metadata inventory when the returned state permits it. This deliberately supersedes the earlier incremental-only page refresh. Automatic refresh can perform the same completeness repair as manual Sync now without requiring a button tap. Metadata-only enumeration adds remote requests; cached configuration/dependency files are not unconditionally downloaded. Ordinary three-second local processing ticks do not enumerate the cloud library.
- Preserve libraryChanged before the inventory takes another consuming snapshot, so commits from either phase update cards. Keep five seconds after completion on Configurations, existing 30/120-second fallback elsewhere, local-change coalescing, serialized operations, opt-in/offline protections, selected-subscription review, and cancellation ownership. No UI, routing, VPN or shared/mobile engine source changed. No real CloudKit or VPN operation was initiated for validation.
- Regression evidence: a synthetic cloud version deliberately absent from a successful incremental result is only installed by metadata reconciliation. The pre-change store fails that new five-second automatic-refresh assertion; the updated store passes and publishes the subscription. A separate non-page fallback case also recovers and publishes missing data, while ordinary local ticks do not repeat inventory. Existing checks cover coalescing, controls remaining enabled, stop-on-page-exit, and preserving an already started import. All 51 offline library regression groups pass. Signed Release build and strict signature verification pass; all 294 protected source/project/resource hashes match the turn baseline. Build number remains 1.5.4. Actual TestFlight cross-device latency still requires a new build and user validation.
- Logs: `build/mac-cloud-auto-diagnostic.log`, `build/mac-auto-cloud-parity-before-tests.log`, `build/mac-auto-cloud-parity-tests.log`, `build/mac-auto-cloud-parity-build.log`. Rollback: `build/rollback/mac-auto-cloud-parity-20261014/restore.py` (dry run by default; refuses later edits). Installed/running app was not replaced or restarted.


### 2026-10-17 · Ping current node from the Mac menu bar

- Added “测试当前节点 / Ping current node” with a speedometer symbol to the system Horizon menu below the resolved node name. Displays queued/testing/latency/failure using the existing MacProbeStore label; DIRECT, REJECT or unresolved targets are unavailable. Nodes already has its separate Test all nodes window-toolbar action; this change targets the system menu.
- MacMenuBarActions resolves the same runtime-selected node as Home, captures its scope/index/name, validates that target again when clicked, and forwards to MacLibraryStore.test. Reuses five-slot queue, duplicate suppression, certificate-consent and error presentation. Does not select a node, connect/reconnect a tunnel, or create a second probe engine. Menu preparation reserves only the menu action coordinator; results remain shared with Home/Nodes.
- Signed Release build, strict signature verification, and 52 offline library regression groups passed. New coverage checks the selected proxy mapping, DIRECT exclusion, pre-readiness/offline protection and existing modal guards. No actual node latency request, VPN operation, cloud synchronization or installed-app replacement was performed. Native status-menu interaction and live latency results remain for user validation after installing/running the build. All 293 protected source/project/resource files match the turn baseline; mobile and shared source are unchanged. Mac build number remains 1.5.5.
- Logs: `build/mac-menu-ping-build.log`, `build/mac-menu-ping-tests.log`. Rollback: `build/rollback/mac-menu-ping-20261017/restore.py` (dry run by default, refuses subsequent edits).
