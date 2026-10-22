# 节点选择与网络诊断（2026-10-03）

## 使用入口

- 节点 Tab 右上角眼睛图标切换原名／隐私显示；设置页也有同一偏好。默认隐私，偏好保存在本地 UserDefaults，名称本身仍只在现有内存／钥匙串。策略组、首页 Ping 目标和有效批测结果跟随显示方式；过期批测结果继续使用编号。
- 原名模式搜索名称、协议与编号；隐私模式只按协议与编号。切换显示方式清空搜索词。策略组页可搜索当前显示名称。
- 节点 → 策略组与选择：未连接时只保存；连接中允许手动更改 select 组。测速／DNS 检查／其他配置变更期间暂不可用。
- 设置 → 诊断与维护 → 规则命中／DNS 分项诊断。长说明在各页面 Info 中，未连接不自动启动 VPN。

## 热切换语义和失败处理

沿用固定 Hako 的 `SelectProxy`，无需替换内核或开启控制器端口。扩展按自身当前配置验证策略组／成员序号，检查隧道会话和原配置指纹；先完整校验选择，成功后才改变内核选择和返回新指纹。消息不包含节点名或凭据。

主 App 收到匹配请求／会话／配置的确认后才保存到钥匙串、更新勾选状态。丢失确认时再查询真实内核指纹：已生效则提交，仍是旧值则保留；不明确时请求停止 VPN，保留旧持久化选择。写入钥匙串失败则请求恢复旧内核选择，恢复不能确认时停止隧道。用户主动断开不会触发重新连接。过期页面选择、跨会话响应和错误配置响应不能更改当前选择。

热切只影响新建连接；已有 TCP 连接及已建立的 UDP 会话保留其原路径，不主动关闭连接。Ping 目标更新为当前 MATCH 解析节点；新连接仍受各条规则控制，并非所有流量都走刚选中的节点。真实跨节点转发及旧连接保持需要真机验收。

同一内核会话下，配置指纹因热切改变时，流量窗口继续使用累计字节差计算，不清空曲线；新会话、计数回退、超时或异常数据仍走原有重置／归零处理。

## 规则命中观测

手动开启后，每两秒读取 `ConnectionsJSON` 当前连接快照。扩展就地转换成固定规则类型、可唯一对应的原文件规则序号、节点／策略组编号和 TCP／UDP；目的地址、域名、端口、规则内容、进程与任意自定义字符串不会跨进程返回，也不写日志。主 App 最多留 60 条内存记录，支持停止和清空；退出页面、切配置或后台清空且不自动恢复。

这是实际连接观测，不是静态模拟，也不是完整访问日志：短连接、被拒绝或建连失败的请求可能没有活动 tracker，无法保证捕获。内核不暴露唯一规则 ID，重复规则不标原文件序号；iOS 插入的 IPv6 拒绝规则也不冒认为原文件规则。内核链按经过的策略组／节点展示，原名仅由 App 使用本地目录映射。

## DNS 分项诊断

输入普通域名（默认 ping0.cc；国际域名使用 Punycode），手动开始后运行：

1. 内核 `DNSQueryJSON` A 和 AAAA 查询，分别显示整体耗时、对应地址记录数与 RCODE，CNAME 不冒认为地址记录。
2. 通过已有私有诊断接口检查 MATCH 节点的引导解析。
3. 同一接口通过该节点请求固定 Cloudflare HTTPS 地址，显示固定错误类别或成功耗时。它不访问用户输入的网站，不能代表该网站连通性。DIRECT／拒绝模式仅执行 DNS 查询。

查询域名只在当前操作内存中使用，正常发往配置的 DNS 解析器，不保存到历史或日志；返回地址与任意错误文本在扩展内消化，只向 App 返回固定类别和数字。DNS 上游证书失败、超时、网络错误、无记录和 DNS RCODE 与节点 HTTPS 结果分开呈现。

**当前真实限制**：固定内核桥接不提供实际命中的 DNS 策略、选中的上游或缓存来源。配置模式、上游数量、策略数量与 DNS IPv6 开关是“配置摘要”，不是路径实测。查询耗时可能包含缓存或解析策略处理，不是单台上游纯延迟。此功能不能证明无 DNS 泄漏，也未单独测量每台配置上游的连通性。fake-ip 模式下，通过内核解析器的直接查询也不等同通过系统 TUN DNS 入口的端到端测试。

停止等待／离开／后台清空 App 结果并忽略迟到响应；现有桥接无法取消已发出的单条 DNS 查询，它们受内核超时限制继续结束。此期间内核会拒绝重叠的测速或热切请求；UI 最多等待 60 秒，不伪装查询已被撤回。

## 开发验证

- 固定内核 Go 测试通过：虚构 select 组 DIRECT → REJECT → 无效成员拒绝且保持 REJECT → DIRECT；未开启持久缓存，没有监听器或外网请求。
- Swift 离线诊断测试通过：规则与链来自输入观测、重复规则不冒认序号、60 条上限、节点名／域名／进程字段脱敏、A／AAAA 分类、RCODE、错误分类、域名边界及消息类型隔离。
- 流量回归通过：同会话热切不清空曲线；新会话、旧包、计数回退及窗口边界保持原有保护。
- 模拟器使用隔离虚构库验证：原名开关、原名匹配／无结果搜索、隐私恢复、设置共享偏好、新 DNS 页面及未连接禁用。未借模拟器进行代理联网。
- iOS 模拟器及 App／Packet Tunnel 真机签名构建通过；尚未安装手机。本轮不把构建或固定内核 selector 单测当作真机热切验收。仍需验证真实热切、已有连接保持、钥匙串失败后的恢复、真实规则记录、DNS 超时及网络切换。

重复验证：

```sh
python3 scripts/check-selection-core.py
xcrun swiftc -parse-as-library -module-cache-path .build/bridge-check-module-cache \
  Shared/ConfigurationCatalog.swift Shared/SubscriptionRevision.swift \
  Shared/PrototypeError.swift Shared/TunnelDiagnostics.swift Shared/ConnectivityReport.swift \
  Shared/NetworkInspection.swift scripts/check-network-inspection.swift \
  -o .build/check-network-inspection
.build/check-network-inspection
xcrun swiftc -parse-as-library -module-cache-path .build/bridge-check-module-cache \
  Shared/LiveTelemetry.swift scripts/check-traffic.swift -o .build/check-traffic
.build/check-traffic
```

所有用例均使用虚构数据，未扩充协议、providers 或规则支持范围。

## 节点页直接点击（2026-10-03）

节点列表每一整行现在是选择按钮。点击已选节点不重复提交；其他节点复用 `selectMember` 的持久化/热切与失败恢复。等待期间禁用重复操作，右侧固定 24 pt 空间展示进度；成功后再更新勾选，使用局部动画并响应减少动态效果。失败在本页弹出已有脱敏原因。

快捷选择仅修改当前 MATCH 选中路径上的一个 select 组，优先最深层且直接包含目标节点的组，不改动无关分流组。若需要修改多个嵌套选择、节点不在当前路径可选范围内或 MATCH 指向固定节点，则进入原有“策略组与选择”页，不改写规则。

已验证：独立路由选择回归（单组、当前节点不操作、嵌套最深组、外层选择、无关组不变、固定 MATCH、循环防护）；模拟器隔离库中从节点 1 点击节点 2，勾选、策略组页及默认 Ping 目标同步更新；模拟器与真机签名构建、嵌入包检查通过。未安装手机，未在真实 VPN 上复测此新入口；动效真机观感待用户确认。

```sh
xcrun swiftc -parse-as-library -module-cache-path .build/bridge-check-module-cache \
  Shared/ConfigurationCatalog.swift Shared/SubscriptionRevision.swift \
  Shared/PrototypeError.swift Shared/TunnelDiagnostics.swift \
  scripts/check-node-shortcut.swift -o .build/check-node-shortcut
.build/check-node-shortcut
```

### 节点切换闪烁修复

`Nodes/Components/NodeSelectionRowView.swift` 单独管理行内反馈：自定义 ButtonStyle 保留 disabled 的交互/辅助功能语义，但不随控制器短暂忙碌状态把所有行自动调暗。普通点击开始切换时，目标行仅文字与编号高亮渐变，不缩放、不位移、不绘制选中背景；使用 SwiftUI 原生 smooth 动画，选中后保持强调，旧选项平滑恢复。强调由“切换中或已选中”统一驱动，成功后不会先灭再亮；失败恢复原状，勾选仅反映确认结果。行布局保持固定，减少动态效果开启时使用简短颜色淡变。移除了依赖按住状态的缩放与高亮。加载超过 150 ms 才显示 ProgressView，快速完成不闪现加载圈；勾选与加载在固定 24 pt 区域中以 250 ms 淡入淡出，响应减少动态效果。延迟只影响反馈显示，不延迟切换请求或虚报成功。业务选择及错误恢复不变。

已通过模拟器及真机签名构建和嵌入包检查。未安装手机；真机闪烁是否消除与过渡观感由用户更新后验收，不能用构建通过代替视觉验收。
