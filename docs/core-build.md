# 固定源码的 iOS 内核构建实验

状态：固定源码及记录在锁文件中的本地隐私补丁已构建为 XCFramework，并链接到主 App 与 Packet Tunnel。当前真机测试版已安装；离线检查与真实代理联网验收分别记录在 [原型说明](phase2-prototype.md)。已通过真机单节点网页访问和用户本地出口核对；引导 DNS 曾失败并已修复，详见原型验收记录。

构建 22 的本地补丁还包含 URLTest 实际连接字节计数，使首页 Ping 与批量测速计入统一流量统计。上游 revision 与工具版本未变；新补丁哈希、模块验证及产物校验值按原流程记录。计数的本机回环测试与真机验收状态见 [实时流量记录](live-traffic-batch-ui.md)。

## 首次未修改上游源码的构建结果（2026-10-01）

| 检查 | 结果 |
| --- | --- |
| Go 归档 | 官方文件 64,772,321 字节，SHA-256 与锁文件匹配 |
| SDK 构建 | Xcode 26.5 (17F42) 成功，无需升级 Xcode |
| 设备切片 | `ios-arm64`，静态归档 66,050,280 字节 |
| 模拟器切片 | `ios-arm64_x86_64-simulator`，静态归档 129,684,480 字节 |
| 来源记录 | 两个切片均报告 sourceRevision=`9437767346a63957c60bf027b6d9fb27e51d89c4`，sourceDirty=false，core=1.19.31，Go=go1.26.6 |
| 上游检查 | CPU overlay marker 和 mDNS client marker 检查通过 |
| 模块完整性 | 根模块与绑定模块 `go mod verify` 均通过，源码 `git diff --exit-code` 通过 |
| Swift 链接 | device arm64、simulator arm64、simulator x86_64 均通过；调用签名包括版本查询与脱敏配置结构校验 |
| 运行时 | 链接探针没有执行；尚未验证真机内核加载、内存、启动停止或联网 |

归档文件大小不是进程内存占用，不能用这两个数字判断是否满足扩展内存限制。两份切片打包在 `.build/artifacts/Hako.xcframework`，文件校验值记录在同目录 `core-build-manifest.json`。本次日志在 `.build/research/core-build.log` 和 `core-link.log`，均为公开依赖构建信息。

## 输入

精确版本记录在 `Configuration/Core.lock.json`：

- Go 1.26.6，官方 Apple Silicon macOS 归档；SHA-256 与 Go 官方发布元数据核对后再解压。
- sagernet gomobile / gobind v0.1.13。
- Hako `9437767346a63957c60bf027b6d9fb27e51d89c4`，基于 Mihomo 1.19.31。
- Hako-Adapter `6a47cf91350ab80024e9bb4003264dd01100bdbd`。
- 构建环境：Xcode 26.5 (17F42)，iOS SDK 26.5。上游 README 仅声明使用 Xcode 27.0 验证，故本次实测旧版本兼容性，不升级系统工具。
- 目标切片：iOS device arm64；iOS Simulator arm64 / x86_64。不开启 macOS、tvOS 构建。

锁文件状态为 experimental，不能把源码可构建等同于手机运行兼容。源树包含多个本地 replacement；只提取主 Go 模块而丢弃 `third_party` 会破坏构建。

## 重建命令

```sh
# 准备并校验工具链，检出固定源码；不会执行内核构建。
python3 scripts/build-core.py

# 安装固定 Go 工具到 .build/tools，并运行上游 iOS SDK builder。
python3 scripts/build-core.py --build

# 只编译链接探针，不运行内核或启动模拟器/设备。
python3 scripts/check-core-link.py
```

所有工具、模块缓存和产物在 `.build/` 内，不写入系统 Go/Homebrew，不修改 shell profile。`GOTOOLCHAIN=local` 阻止隐式 Go 升级，Go 环境文件关闭，模块校验使用 sum.golang.org。首次需要访问 Go 官方、GitHub 和 Go 公共模块服务，只下载公开依赖，不读取订阅。

脚本拒绝脏的源码检出或不匹配的 revision/origin，不自动丢弃本地补丁。成功后应生成 `.build/artifacts/Hako.xcframework` 和 `core-build-manifest.json`，后者记录实际 Xcode/Go 版本及每个文件的 checksum。这个 manifest 是构建输入与结果记录，不是已经证明字节级复现。

上游 builder 使用临时 Go CPU overlay，不修改系统 GOROOT；其产物检查包含 ARM64 iOS CPU overlay marker 和平台切片验证。脚本在构建后执行根模块及绑定模块的 `go mod verify`，本次均已通过。

## 接入前必须验证

1. 生成的 Objective-C 头文件能被 Swift 导入，iOS 二进制链接成功；真机内核版本查询和退出路径正常。
2. `NEPacketTunnelFlow` 经公开接口到 socketpair 的数据包边界、地址族前缀、背压和 FD 所有权；不能直接借用私有 utun FD。
3. 核对配置差异 API `ConfigDeviationsJSON` 的输出与实际执行路径。该 fork 会转换/移除部分 DNS、TUN 和平台字段，某些未编入的协议甚至保留拒绝占位节点。客户端必须在启动前明确阻止或披露这些情况。
4. 差异 JSON 的 `given`、配置哈希及原始错误也可能包含敏感数据；不能原样写普通日志、报告或分析服务。
5. 用户样本现已确定为 Hysteria2 + Salamander、单 select 与 MATCH；配置验证仍需与联网/自动资源下载隔离。
6. 原始许可保留在固定的检出源码中。核查发现 SDK 构建命令本身不附带完整许可证目录；分发前必须另行生成模块许可证清单、保留 Hako 的 LICENSE/NOTICE、Adapter 许可和生成绑定运行时的许可，不能只发一个 XCFramework。第二阶段现已使用固定源码构建产物，许可证材料更新见下节。

御坂将“源码构建、Swift 链接、真机加载、单节点转发”分别记录结果。

## 第二阶段集成与本地补丁

`build-core.py --build` 在独立 `.build/core-patched/<patch-id>` 本地副本应用 `Configuration/Patches/hako-private-diagnostics.patch`，原始固定源码检出保持干净。补丁哈希在锁文件中，脚本校验基准 revision、补丁及已有副本的 diff；不自动覆盖额外修改。当前 SDK 的 sourceDirty=true 是这份已记录补丁的结果，不能继续引用上表 sourceDirty=false 描述当前产物。

该补丁另包含显式 `EphemeralPacketTunnel` 选项，修复上游“关闭持久缓存 = 仅 App 预检”限制与扩展服务创建的冲突。它仅允许隐私诊断已开启、缓存已关闭的 iOS NE 服务；其他组合继续拒绝。数据库仍不开启，NE 内存压力监控保持启用。`scripts/check-core-privacy.py` 分别在独立进程验证日志保护、默认预检限制、非法组合拒绝、三轮服务创建/幂等关闭，以及没有持久数据库或临时文件写入；测试不调用 `Start`。

补丁新增 `SetupOptions.PrivateDiagnostics`，扩展显式开启，以抑制原始 core 日志、启动失败 breadcrumb、阶段文件和 Go 独立崩溃文件；测试脚本为 `scripts/check-core-privacy.py`。主 App 的常规导入只调用结构与差异校验 API；调试启动参数可额外执行初始化、创建服务和关闭检查，但不会调用 service 的 `Start`。

构建脚本现在还生成 `.build/artifacts/CoreLicenses` 并将目录放入主 App 包；包含上游模块清单、Hako LICENSE/NOTICE、Adapter、Go 与 gomobile 许可、锁文件和补丁。上游清单基于 host production tags，可能包含 iOS 未链接模块，不能据此宣称已完成对外分发的精确许可证审计。

重建需要同时保留仓库脚本、锁文件、补丁与上游完整源码（含 third_party）。构建产物和用户原始配置均不进入 Git。

构建 3 的 iPhone App 内 26/26 虚构配置用例通过，之后用户实际连接暴露了上述服务创建限制。构建 4 重建的 SDK 三个 iOS 架构均通过 Swift 导入与链接；真机运行记录见第二阶段验收表。没有启动模拟器或执行 XCTest，实际隧道与出口仍须单独验收。

构建 6 起显式关闭内部 Clash Unix HTTP socket（`DisableClashAPISocket`），使用原生桥接与 NE 消息。构建 9 增加只返回固定分类的 `PrivateNodeProbeJSON`，区分节点引导解析和 HTTPS 链路；原始错误与 IP 不跨过诊断边界。该 API 仅由用户手动触发，不用于自动测速。新增分类器以虚构敏感文本验证不泄漏输入，补丁哈希与 SDK 已重新记录。

系统 DNS 引导快照使用固定源码的 `SystemResolverLines`（libresolv / res_ninit，发生在 NE 网络设置安装前）；不把 DNS IP 写日志。另在源码核查中发现此 fork 还包含基于私有 `dns_configuration_copy` 的按接口 DNS 查询实现，存在未来 iOS 兼容风险；上游源码中的个人授权注释不代表本项目用户授权。本项目不能据公开 PacketFlow 桥接声称整个 fork 都只使用公开 API，后续分发/升级前需单独审计该路径。

## 构建 13：单文档解析与兼容性回归

本地补丁在 YAML 第一份文档解析后检查 EOF，接受合法起始/结束标记，明确拒绝第二份文档。补丁哈希已更新到锁文件，并重新生成 SDK、manifest 与许可证目录；上游 revision、Go 和绑定工具版本保持固定。

设备 arm64、模拟器 arm64/x86_64 三个链接探针通过；隐私诊断与临时服务生命周期回归通过。新增 `scripts/check-configuration.py`：用同一份 Swift 配置校验代码调用固定 Go 解析桥接，41 个虚构用例通过，再对虚构双协议运行配置执行内核 CheckConfig。整个检查不启动代理服务、不安装路由、不写钥匙串。可选本地 profile 仅做内存中的导入契约检查，不参与导出文件或完整服务创建。

手机构建 13 的离线自检同样为 41/41。解析测试、内核预检和 iPhone 节点实际联网属于不同层次，后二者不能从前者推定；实际结果继续写入设备/阶段二文档。

## 构建 14：可配置测速截止时间

本地补丁新增 URLTestWithTimeout，允许原生端传入有界截止时间（1–60000 ms），本应用使用 10000 ms，与当前 Mac Verge 默认值一致。仍只返回整数和固定失败标记，保留非 2xx 拒绝，不输出原始错误或节点信息。原 URLTest API 保持原行为。

已重建 SDK/许可证及 manifest，依赖版本不变、补丁哈希更新。三个 iOS 架构的新符号链接通过。`python3 scripts/check-ping-core.py` 在与 iOS SDK 相同的绑定模块依赖下验证计时区间、同连接第二次 HEAD、超时传递和错误状态；仅回环测试服务器有流量。主机诊断检查同时覆盖 10000 ms 边界，过期结果不能成为成功。新配置自检为 44/44。

## 2026-10-06：兼容性容量与 DNS policy 顺序

- `hako-selection-policy.patch` 将受限节点投影上限同步为 512、组成员上限 576，原有正则限时与输入边界保留。
- 新增 `hako-dns-policy-order.patch`：只读取已验证原文件的有序 DNS policy 键，将规范化后的值按原顺序写回 JSON；支持 YAML 与 JSON，拒绝键集合不一致。无联网、文件读取或服务启动。
- 所有补丁 SHA-256 更新至 `Core.lock.json`，重新构建 iOS arm64 与模拟器双架构框架及许可证包；仍使用同一固定 Hako revision。
