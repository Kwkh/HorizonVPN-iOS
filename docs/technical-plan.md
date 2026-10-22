# 环境与技术方案

检查日期：2026-10-01（Asia/Shanghai）。结论以本地输出和锁定提交为依据，尚无真实代理流量验证。

## 环境证据

| 项目 | 检查结果 |
| --- | --- |
| 仓库 | `main`，初始提交 `80efb6d`；开始时工作区干净，无 remote |
| 已有工程 | SwiftUI / SwiftData 初始模板，App + 单元测试 + UI 测试，未见既有代理逻辑或配置 |
| 工具 | Apple Silicon、macOS 26.5、Xcode 26.5 (17F42)、iOS / Simulator SDK 26.5，Git 和 xcrun 可用 |
| Go 工具 | 初检 PATH 中无 Go、gomobile/gobind；入口验收后已在 `.build/` 隔离准备 Go 1.26.6 和固定移动工具，详见内核构建实验 |
| 最低系统 | 原工程 26.5，本次保留；不擅自扩大支持范围 |
| 设备 | 已配对 iPhone 16 Pro，iOS 26.6.2，Developer Mode enabled，通过局域网可见 |
| 设备调试 | 初次因手机锁定而无法挂载 DDI；用户连接并解锁后服务恢复，已成功安装、启动诊断 App，无需升级 Xcode |
| 团队 | 工程既有 Team ID 保留；检查到有效 Apple Development 身份。团队会员类别尚待用户确认 |
| 签名 | 初检未找到项目专用描述文件；检查期间出现对应本地文件。后续构建未使用 `-allowProvisioningUpdates`，主 App 和扩展均成功签名；两份内嵌 profile 都覆盖目标设备和 Network Extension 权限 |
| 有效期 | 本次内嵌 profile 到期时间约 2027-10-01 21:40（北京时间）；还应检查证书、账户与撤销状态，不能只凭 profile 保证可用到该日 |
| 用户配置 | 尚未收到脱敏订阅、Verge 覆写／脚本／DNS／TUN 信息；未访问真实订阅 |

签名文件的生成来源不能仅凭本次命令记录确定。未执行登录、购买、证书创建、系统代理修改、VPN 授权或按需连接启用。

## 架构决定

1. SwiftUI App 管理订阅版本、可见配置诊断、策略组、连接控制和状态。连接状态来自 `NETunnelProviderManager.connection.status`，流量可用性另行验证。
2. `NEPacketTunnelProvider` 持有内核与数据包桥接，串行管理启动、停止、路径改变与资源释放。先完成内核初始化再安装匹配的路由/DNS；失败必须撤销设置和关闭资源。当前诊断版在安装网络设置之前直接失败。
3. 内核接口将包含 validate、start/stop、selectGroup、snapshot、事件回调。配置验证结果包含“不支持／需适配”的字段路径。桥接错误经过固定错误码映射，不能直接写出 Go 错误文本。
4. 控制消息优先使用 `sendProviderMessage`，关闭外部 HTTP 控制器和 dashboard。较大的配置文件通过 App Group 原子交付，只传版本 ID；后续配置与密钥加密存储，解密密钥和订阅 URL 放共享 Keychain、使用适合锁屏运行的 ThisDeviceOnly 可访问级别；不放普通 defaults、providerConfiguration 或日志。
5. 订阅更新顺序：下载到候选版本 → 限制大小和跳转 → YAML/内核语义校验 → iOS 适配报告 → 原子切换；失败保留最后可用版本。更新与凭据存储属于第三阶段，本次尚未实现。

## 内核和桥接候选

完整提交 ID 见 [研究记录](core-candidates.json)。以下是读取源码后的判断，不是本机重建或真机兼容性证明。

| 路线 | 维护与许可证证据 | iOS / 重建判断 |
| --- | --- | --- |
| 上游 Mihomo + 自有小型桥接 | `Meta` 提交 `88dcbf7`，2026-09-30；GPL-3.0，README 另有下游命名条件。API 查询的最新 release 为 v1.19.32 | Clash YAML 语义最接近；上游库 API、Go 构建标签、TUN 设备实现仍需包装；没有验证可直接获得可用的官方 iOS SDK |
| Hako + Hako-Adapter（Mihomo 衍生） | Hako `9437767`，2026-09-24，基于 Mihomo v1.19.31；Adapter `6a47cf9`；均 GPL-3.0，未归档，集成代码标注 pre-release | 专用 Apple SDK 与公开 packetFlow 到 socketpair 的桥接、有队列边界与生命周期实现；有 fork 差异及同步上游成本，不能把它当成原版 Mihomo |
| ProxyCat 的 libmihomo 包装方式 | `fd302ed`，2026-05-17；外层 MIT，内核仍 GPL-3.0 | Swift/Go 源码有参考价值，但通过 KVC 与 FD 枚举查找私有 utun，存在升级失效风险；脚本说明含 `@latest`，不能原样作为本项目重建流程 |
| sing-box / libbox + Apple 客户端 | core `927770c`，2026-09-30；Apple 客户端 `e1bc362`，2026-09-29；GPL-3.0-or-later | 有专门 Apple 集成与构建路径；原生 JSON 配置，Clash 的 provider、规则与 DNS 需要逐项转换，不能等同兼容 |

**建议的实验顺序**：第一阶段保持独立于内核；第二阶段优先做 Hako + Adapter 的源码重建和一个节点实验，同时以锁定的上游 Mihomo 配置语义作为对照。原因是已看到公开 `NEPacketTunnelFlow.readPackets/writePackets` → socketpair 的实现，可避开把私有 utun FD 当作稳定接口。若其构建或必要协议不通过，再评估上游 Mihomo 自有桥接；若成本明显过高，才转向 sing-box 并重新约定兼容范围。实际配置尚缺失，最终内核采纳仍以实验结果为门槛。

Hako 声明的工具链是 Go 1.26.6、sagernet gomobile/gobind v0.1.13；绑定模块最低 Go 1.25.0。其 README 只报告在 Xcode 27.0 验证过；本次已在 Xcode 26.5 成功构建 iOS XCFramework 并通过三个架构的 Swift 链接检查，无需升级 Xcode。Adapter 类型是 internal，当前需要按固定提交将源码编入扩展，不能只添加 Swift package 后假设有稳定 public API。

源码构建使用精确版本的隔离工具链；固定内核、Adapter、Go、gomobile、go.mod/go.sum、构建标签和补丁。使用 `GOTOOLCHAIN=local` 防止隐式升级；记录 SDK/Xcode 版本、许可证、产物 checksum 和输入源码 manifest。分别构建 iOS arm64 与 simulator slice，不复用 macOS 二进制。入口验收后已开始 [固定源码构建实验](core-build.md)，尚未宣称字节级可复现。

## 第一、二阶段门槛

| 阶段 | 要完成的验证 | 通过条件 |
| --- | --- | --- |
| 1A 工程和签名 | App 嵌入扩展、ID/版本匹配、entitlement、签名与设备覆盖 | 已完成编译和本地产物验证；见设备验收记录 |
| 1B 真机入口 | 安装、打开 App、用户允许 VPN 配置、触发入口并看到固定日志 | 已由 21:58 截图与两次对应设备日志证实；当前 stub 预期失败，尚不证明成功建立隧道 |
| 2A 内核实验 | 固定源码工具链 → XCFramework → Swift 调用 → 公开数据包桥接 | 源码构建、三个架构 Swift 链接已通过；真机加载、释放及内存/FD 趋势仍待验证 |
| 2B 单节点联网 | 本机安全输入一个测试节点；连接/断开/重连 | HTTPS 出口与预期节点一致；DNS 正常；断开恢复；TCP/必要 UDP 和基础后台行为实测 |
| 2C 失败路径 | 无效配置、错误节点、路由/DNS安装失败、启动中停止 | 明确失败、无假连接、无残留路由或失控重启；失败后可再次连接 |

最小联网实验首先禁用 providers、GeoIP/GeoSite 自动下载、sniffer 和复杂规则，使用单节点 + select + MATCH。是否选择 Trojan、Shadowsocks 或其他协议由用户现有测试节点决定，示例中的 Trojan 不是用户协议已确认。

## 主要风险

- 扩展内存限制随系统与设备环境变化，不硬编码“50 MB 可用”。记录真实 footprint、峰值和系统终止日志；Go 软内存限制不覆盖所有进程开销。
- 自动路由、auto-detect-interface、Linux TPROXY/redir、桌面进程规则不能照搬；避免内核出站重新进入自身 TUN 的回环。
- fake-ip、DoH/DoT 引导解析、nameserver-policy、IPv6、DNS 泄漏和断开后的恢复均需实测。IPv6 开关必须同时约束 DNS 与路由。
- socketpair 桥接仍有拷贝、缓冲、背压和 FD 所有权成本；必须测试重复启停、分片/MTU、TCP/UDP 和大流量。
- GPL 及附加声明按固定提交保留，外层 MIT 不会改变所链接内核的许可证。后续如分发再核对完整依赖及对应源码义务；本次未复制候选实现到产品源码。

## 一手资料

- [Apple NEPacketTunnelProvider](https://developer.apple.com/documentation/networkextension/nepackettunnelprovider)、[NEPacketTunnelFlow](https://developer.apple.com/documentation/networkextension/nepackettunnelflow)、[iOS capability 表](https://developer.apple.com/help/account/reference/supported-capabilities-ios)
- [Mihomo 固定源码](https://github.com/MetaCubeX/mihomo/tree/88dcbf7f1614a67c3b36b848ee3592dfa92ada36)、[对应许可证](https://github.com/MetaCubeX/mihomo/blob/88dcbf7f1614a67c3b36b848ee3592dfa92ada36/LICENSE)
- [Hako 固定源码与构建说明](https://github.com/TokenPLS/Hako/tree/9437767346a63957c60bf027b6d9fb27e51d89c4)、[Adapter 固定源码](https://github.com/TokenPLS/Hako-Adapter/tree/6a47cf91350ab80024e9bb4003264dd01100bdbd)
- [ProxyCat FD 实现](https://github.com/MMitsuha/proxycat/blob/fd302ed10a76c4f81a5fcddf91a00200eaf6623e/PcatExtension/PacketTunnelProvider.swift)
- [sing-box 配置格式](https://sing-box.sagernet.org/configuration/)、[Apple 客户端](https://github.com/SagerNet/sing-box-for-apple/tree/e1bc3629ee78fa824176c6be157ee2be7795c5c0)

## 第二阶段进度更新（2026-10-01）

用户已提供本地单节点 Hysteria2 + Salamander 配置，确认无后续修改。已实现公开 PacketFlow bridge、core 生命周期、严格输入范围、手机本地导入/钥匙串确认和固定日志；使用固定 Hako 源码加显式隐私补丁。构建、签名与安装通过，联网阶段仍需真机手动操作，详细证据及未验证项见 [phase2-prototype.md](phase2-prototype.md)。未投入完整视觉设计。
