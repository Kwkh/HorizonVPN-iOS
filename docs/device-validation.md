# 构建与真机验收

当前测试版及第二阶段操作见 [phase2-prototype.md](phase2-prototype.md)。下表和入口诊断步骤是阶段一历史证据，已安装的版本现在显示“Clash 测试”。

2026-10-02 构建 15：03:09 安装，签名与包检查通过；主机和 iPhone 离线自检 **61/61**。真机隔离示例验证列表、切换、重命名、多选删除与空状态；正常启动后真实旧配置迁移保留，03:12:36 Ping **302 ms**。用户随后反馈两份真实订阅间切换正常；详细边界见 [订阅管理](subscriptions.md)。新的启停、后台和网络变化检查见 [稳定性记录](stability-validation.md)。

2026-10-02 构建 14：02:39 安装，签名、包检查及三个 iOS 架构链接通过，手机离线自检 44/44。已保存的双节点配置无需重导入。统一延迟、HTTP 204 网址与 10 秒超时对齐本机 Verge 的当前默认测速设置；Hysteria2 手机实测 217 ms、233 ms。未取得 Mac 严格同节点对照，亦未验证 VLESS、新配置完整 DNS/规则、无泄漏或长时稳定性。测试后手动断开，02:45 界面确认“未连接”；未改动 Mac 设置。

2026-10-02 更新：构建 13 已于 02:10 安装，签名、包检查通过；02:11 iPhone 离线自检 **41/41**，旧单节点配置可读取，正常启动时保持未连接。新增独立节点/策略组页与双协议兼容范围，真实新文件由本人在手机确认导入后再测试。构建 12 的真机 HTTPS Ping 曾返回 502 ms、485 ms，断开清除结果并禁用测试；构建 10/11 的 Safari 预期出口、DNS 功能、断开恢复、再次连接及主 App 后台转发已验证。Console 保持暂停。锁屏、受控网络切换、应用 UDP/IPv6、内存峰值与长时稳定性仍待测。

## 阶段一结果（2026-10-01）

| 检查 | 结果与边界 |
| --- | --- |
| 工程 plist / entitlements 语法 | 通过 |
| Simulator build-for-testing | 通过，App、扩展和测试产物可编译；未启动模拟器、未执行 XCTest |
| iPhone arm64 无签名构建 | 通过 |
| 使用本地资料签名构建 | 通过，未启用 `-allowProvisioningUpdates` |
| 内嵌扩展、入口、ID、版本检查 | `scripts/check-bundle.py` 通过 |
| 签名完整性 | 系统信任服务可用时 `codesign --verify --deep --strict` 通过；沙盒内曾因信任服务受限返回错误，不能把该结果当作产物损坏 |
| profile 权限和设备 | 主 App 和扩展均含 packet-tunnel-provider，覆盖本次 iPhone；保留原团队 |
| 错误码与脱敏检查 | Mac 本地编译并运行 `scripts/check-diagnostics.swift` 通过；不涉及 iOS 网络 |
| 真机安装前检查 | 初次因 DeviceLocked `0xe80000e2` 失败；用户连接并解锁后，21:53 设备服务与 DDI 就绪，同标识应用安装前未检出 |
| 真机安装、App启动 | 21:54 安装并启动 `Kenote.Clash` 成功；用户提供的 21:58 截图确认诊断界面实际显示 |
| VPN配置与错误返回 | 截图显示“已有系统配置”、“未连接”和扩展错误 1001，与预期一致 |
| 扩展入口和设备日志 | Console 在 21:58:16.986 和 21:58:24.105 两次记录 `phase1.provider.entered`，紧接着均为 `phase1.provider.core-unavailable code=1001`；证实本次真机扩展入口被调用两次并返回预期错误 |
| 代理出口、DNS、断开恢复、后台、内存与耗电 | 尚未实现／验证；不能据编译或签名结果判定可用 |

本次遇到 `xcodebuild -dry-run` 已不受支持，改用正常构建检查现有签名。所有验证产物在临时目录，没有提交证书或真实凭据。

21:58 验收证据来自用户截图和对应设备 Console 日志，不复制截图到 Git。完成核对后已暂停 Console 日志流。安装、系统配置、扩展入口和受控失败路径已验证；成功建立代理隧道仍待第二阶段内核接入。

## 构建与签名

1. 使用 Xcode 打开 `Clash.xcodeproj`，选择 `Clash` scheme。
2. 主 App 标识为 `Kenote.Clash`，扩展为 `Kenote.Clash.PacketTunnel`，两者使用同一开发团队。若未来换标识，必须保持“App ID + .PacketTunnel”的关系，日志 subsystem 也需同步调整。
3. 两个 target 都需要 Network Extensions / Packet Tunnel 权限；普通 Personal VPN entitlement 不能代替这个权限。免费 Personal Team 的普通 App 安装能力也不等于具备 Network Extension 签名资格，最终以 portal/profile 验证为准。
4. 当前没有 App Groups。第二阶段使用两个 target 的 `$(AppIdentifierPrefix)Kenote.Clash` 共享钥匙串组，现有签名资料已接受；真正保存凭据由用户在手机导入页确认。
5. 本地已有匹配签名资料时可执行：

```sh
xcodebuild -project Clash.xcodeproj -scheme Clash -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/Clash-SigningCheck build
codesign --verify --deep --strict /private/tmp/Clash-SigningCheck/Build/Products/Debug-iphoneos/Clash.app
python3 scripts/check-bundle.py /private/tmp/Clash-SigningCheck/Build/Products/Debug-iphoneos/Clash.app
```

如缺少签名资料，先确认团队、两个 App ID 和权限，再由用户同意创建/更新 profile；需要新证书、账户登录或接受协议时单独确认。不要未经确认追加 `-allowProvisioningUpdates`，它可能创建或更新 profile、App ID 和证书。

## 解锁与安装步骤

1. 解锁 iPhone 16 Pro，暂时保持亮屏，建议用数据线连接 Mac。出现“信任此电脑”时由本人确认。
2. 本次检测到 Developer Mode 已开启。如果之后关闭，可到“设置 → 隐私与安全性 → 开发者模式”自行启用，按系统提示重启并确认。
3. Xcode → Window → Devices and Simulators，选择 iPhone，等待设备准备完成。若解锁后仍报 DDI 错误，先记录内层错误，再判断设备支持组件；不要直接升级 Xcode或手机。
4. 再检查是否已安装同标识应用，避免覆盖不相关工作。选择此 iPhone 运行 `Clash`，或在设备窗口的 Installed Apps 添加已签名的 `.app`。
5. 仅在系统确实要求信任开发者时，按“设置 → 通用 → VPN 与设备管理”中的具体提示处理。不要下载陌生签名或配置描述文件。

本次锁屏问题在用户连接并解锁后已解除，无需升级 Xcode；诊断 App 已安装并启动。以后再次遇到同一错误时，先解锁再检查，不尝试绕过锁屏。

## 阶段一扩展入口验收（历史版本）

1. 打开 App，确认标题为“Clash 诊断”，页面明确写着“代理内核尚未接入”。首次打开只读取系统配置。
2. 点击“添加诊断 VPN 配置”，阅读说明后确认，并在 iOS 弹窗中由本人允许。拒绝时应保持失败/未配置状态，不能显示已连接。
3. 先结束其他 VPN 会话，再点击“验证扩展入口（预期报错）”并确认。这一步会请求系统启动 VPN 扩展，可能影响其他 VPN。
4. 通过 Xcode 附加 PacketTunnel 进程，或 macOS Console 选中已连接 iPhone，筛选 subsystem `Kenote.Clash.PacketTunnel`。需要同一次测试的 `phase1.provider.entered` 和 `phase1.provider.core-unavailable code=1001`。
5. 系统应回到未连接。点击“读取上次断开原因”，系统若保留错误应显示内核缺失提示；错误可能被系统包装或不保留，必须结合当次设备日志，不能只凭历史错误证明本次执行。
6. 重复入口请求一次，确认无假连接和卡在启动中。测试完成后可手动移除本应用的 VPN 配置。

**诊断 stub 的预期失败只能验收入口与错误路径。** 真正隧道成功启动、停止、恢复及日志持续可读，要在接入内核后重新验收；第一阶段不能因此直接标成全部通过。

## 单节点联网验收表（第二阶段）

先记录未连接时的网络可用性。经用户确认后才添加实际路由/DNS；节点参数通过本机或手机安全输入，不写到命令行参数、Git、报告或普通日志。

| 场景 | 记录要求 |
| --- | --- |
| 首次连接 | 系统状态 + 扩展事件 + HTTPS 请求出口，出口与测试节点一致；不是仅有 VPN 图标 |
| DNS | 指定测试域名可解析；说明期望 DNS 路径，验证 fake-ip 或真实 IP 模式；不把成功解析当作无泄漏证明 |
| 停止／重连 | 停止后请求恢复基线，再连接走测试节点；连续多次无残余路由和 FD 增长 |
| 失败节点／断网 | 明确失败或等待恢复，不误报成功；恢复网络后按明确手动策略重连 |
| 后台／锁屏 | 主 App 退出前台、锁屏后流量与内存状态；不依赖 App 后台运行维持内核 |
| 网络切换 | Wi-Fi / 蜂窝切换、IPv4/IPv6、必要 UDP 场景按实际网络测试 |
| 资源 | footprint 峰值、持续连接趋势、系统终止日志与耗电；保存脱敏结果，不记录访问内容 |

## 已知限制、排查和回退

- “内核未接入 1001”是阶段一诊断版本的预期结果。第二阶段改为真实核心启动，失败码见原型文档。
- 配置保存失败：核对用户授权、两个 profile 和 entitlement；UI 不擅自把所有错误归因为权限拒绝。
- 扩展不出现：检查 App 的 `PlugIns/PacketTunnel.appex`、principal class、签名和设备 Console 日志。主 App 可打开不代表扩展签名可用。
- 系统显示连接中：读取实时状态，必要时点“断开”。不要通过改本地布尔变量隐藏系统状态；本版不启用自动重连。
- 本次只有 AppIntents 元数据提取被跳过的构建提示，本项目未实现 App Intents，不影响当前编译结果。
- 重新签名：保留源码提交、Xcode版本和依赖锁定记录；在有效开发团队下重新构建两个 target。App Group/Keychain 绑定更换团队可能导致旧凭据不可读，迁移时需重新安全输入。
- 回退：保留上一份已验收的源码提交与签名归档到仓库外；先停止隧道，必要时在系统“VPN 与设备管理”移除本应用配置，再用相同身份重装已知可用版本。构建 17 源码现已纳入 Git，可按对应提交重新构建；先前联网测试版产物在临时目录，不是稳定发行归档。构建 15 降级至构建 14 或更早时，旧版不认识多订阅索引，需重新导入该版本支持的配置。
- 未创建自动连接、定时任务或远程后端；用户已授权通过手机镜像操作连接、断开和公开网页测试；真实节点仅在手机中由已导入配置访问，没有把原始配置写入源码或报告。核心联网验收通过后再进入订阅与视觉设计阶段。
