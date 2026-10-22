# 通用 YAML 兼容性增量（2026-10-04）

本轮以固定 Hako 内核的配置语义为依据，不按域名、供应商、文件名或真实节点做特判。沿用原始输入、派生运行配置、完整资源快照的分离方式。页面布局保持不变，适配说明进入既有 info。

## 2026-10-06：常用节点参数、复杂 DNS、大订阅和负载均衡

以下是当前增量；本文后面的旧日期记录保留当时状态。所有输入入口共用校验契约，不按供应商、URL、文件名做特判，页面布局不变。

| 范围 | 本轮支持与边界 |
| --- | --- |
| 节点连接选项 | TCP 协议的 `tfo`；`ip-version` 的 dual、ipv4、ipv6、ipv4-prefer、ipv6-prefer；SS 的 UDP-over-TCP 及 v1/v2；VMess global-padding / authenticated-length。MPTCP 仍只接受 false，QUIC 节点不接受 tfo:true。HY2 udp:true 明确适配为原生 UDP；不能用 udp:false 关闭。 |
| smux | SS、VMess、VLESS、Trojan 的 smux/yamux/h2mux，padding、only-tcp、statistic 与有界连接/流数量。服务器必须支持对应多路复用；Brutal 尚未接入。关闭的 smux 沿用旧适配。 |
| SS 插件 | obfs 的 http/tls；v2ray-plugin 的 WebSocket、可选 TLS、host/path/headers/mux/证书指纹/证书校验开关。TLS client-fingerprint 仅用于 v2ray-plugin TLS。对应 SIP002 plugin 参数可从 URI、二维码、链接列表、Base64 入口导入；未知/重复/错误参数明确拒绝。插件 skip-cert-verify:true 纳入现有配置版本授权，不自动降低证书校验。 |
| DNS | hosts 的 IPv4/IPv6 单值或列表；policy 的 GeoSite、domain 类型 rule-set、逗号分隔域名；fallback-filter.geosite；上游 `#节点/组/DIRECT` 路由引用。节点引导 DNS 禁止引用代理，防止递归。system/system:// 替换为连接前系统 DNS，切网后重连刷新。 |
| DNS 顺序与资源 | 保留原 YAML/JSON 中 DNS policy 的顺序。单独在 DNS 引用的 GeoSite 也进入完整快照、分类校验、离线内置资源和回滚；缺失资源不静默降级。 |
| load-balance | consistent-hashing、round-robin、sticky-sessions；沿用自动组的 iOS 健康检查频率限制，作为自动分配组显示，不伪装成手动选中某一个节点。 |
| provider override | 在原有字段外支持 tfo、ip-version。覆盖后所有节点重新验证，不适用组合明确拒绝。 |
| 容量 | 主输入 1 MiB；节点总计 512、组 64、主规则 8192、单组成员 576；主文件、URI 列表、provider 投影、include-all 和内核筛选边界同步。内部 Base64 快照外壳上限 2 MiB，原文仍限 1 MiB。每类 provider 32、远程依赖总计 35、classical provider 4096 条及依赖大小限制保持原值。 |

### 验证与性能边界

- `scripts/check-priority-compatibility.py`：虚构输入的正/反例，覆盖字段保留、非法组合、SIP002 转义、证书确认计数、DNS-only Geo 资源、原始策略顺序、边界和大型快照。
- `scripts/check-priority-core.py`：固定内核预检；验证负载均衡实际 Unwrap 选择、hosts 答案、规则集 DNS 命中及代理引用、重叠 DNS 策略优先级。只初始化合成内联规则 provider，不启动网络/健康检查。
- `HorizonTests/PriorityCompatibilityTests`：iOS 模拟器实际内核预检与大配置导入，和已有关闭项、provider 刷新/回滚/筛选测试一起回归。
- 大样例为 512 节点、64 个各含 512 成员的组、8192 条主规则，原文件 382783 字节。Mac 固定内核解析约 45 ms，过程累计分配约 44 MiB，解析后 Go 堆约 6–8 MiB；累计分配不是峰值驻留内存。
- iOS Debug 模拟器完整导入（诊断、选择恢复、原生预检）由约 9.9 秒降至约 7.1 秒：有效节点只做一次字段契约检查，并复用已经通过的准备结果；无效节点仍聚合独立错误。CPU 校验在导入 actor 执行，未移至主线程。
- 本轮结果：基础自检 146/146；新增导入/边界检查 92 项、固定内核 19 组用例、iOS 模拟器 10 项导入/维护测试通过。关闭项 343、原有 DNS 48、筛选 79 项回归通过；iOS 无签名构建与扩展包检查通过。
- 未测真机隧道峰值内存、长期吞吐或全部新协议组合的真实服务互通。因此不承诺与 Verge/Mihomo 全量等价，512 是输入支持上限，不是真机内存保证。

仍未开放：hosts 域名别名、系统 hosts、DoQ/H3 DNS、任意 DNS URL 参数/接口绑定、fake-ip-filter 规则模式、SS 其他插件、MPTCP、Brutal、XHTTP/H2、relay、嗅探和任意脚本。现有未知字段与无效引用继续明确拒绝。

## 已实现

- 策略组与 proxy-provider 健康检查接受整数 `expected-status: 204`，运行时规范为字符串；字符串状态码、范围和 `*` 保留。布尔值、小数部分非零的数值、越界状态码和错误范围仍拒绝。
- `dns.listen: ':1053'` 接受，并与 IP:端口、IPv6 监听一样明确适配：原文保留，iOS 不开放桌面监听端口。
- 节点列表可携带 IPv6、日志、统一延迟、连接参数、已支持桌面元数据以及显式 DNS。只在没有任何策略组和 rules、且字段属于明确的节点列表范围时补充 select + MATCH；显式 DNS 保留并走依赖下载、内置 Geo 和预检流程。错误类型、未知字段、global/direct 模式不被模板覆盖。
- 配置已有完整 rules 时，可省略 proxy-groups；规则可以直接指向有效节点／内置目标。已有组却缺少 rules 时仍拒绝，不能猜测用户原本的分流意图。
- `include-all`、`include-all-proxies`、`include-all-providers`：在完整订阅快照上展开，原始字段保留。显式 proxies 在前，自动 inline 节点及 provider 名称按 UTF-8 字节排序；不自动收集策略组；include-all-providers 替代 use。只避免自动收集重复加入已显式列出的节点，显式重复、循环、无效引用仍拒绝。
- 自动收集每次刷新重新计算；仍存在的选择可保留，回滚原文和资源会恢复成员。空组拒绝并解释，不默认为 COMPATIBLE / DIRECT。不同 providers 之间重名仍受现有全局唯一名称约束。
- 无效 include 字段不会挡住其他独立字段的诊断，info 可同时报告策略组和 DNS 错误。

## 验证方式

- `python3 scripts/check-configuration.py` 建立固定主机桥接，运行基础回归并导出脱敏样例。
- `python3 scripts/check-general-compatibility.py` 覆盖类型／边界、节点模板与 DNS 保留、自动收集顺序、inline 与模拟 HTTPS provider、选择、刷新、回滚、错误聚合。仅合成输入，不访问真实订阅和网络。
- 随后 `python3 scripts/check-general-core.py`：读取合成运行配置与保留原始 include 写法的对应配置，分别执行固定内核预检，比较实际组成员顺序，逐项测试 Selector.Set / Now。对原生 include-all 重复加入显式节点的情况，比较去重后的成员，App 的去重适配单独披露。不会启动内核服务或 provider 自动探测。
- `ClashTests/GeneralCompatibilityImportTests`：iOS 模拟器验证新的写法能通过真正的内核预检，以及节点列表中的 DNS Geo 依赖能够离线附加、原文保留。
- 格式识别、DNS 及订阅维护原有回归继续适用。

本轮不等于真机联网验收；未替换手机安装包或操作 VPN。

## 后续优先项

1. group/provider 筛选及限定范围 override 已接入，见 [筛选兼容性](selection-policy-compatibility.md)；其他覆盖参数继续逐项验证。
2. hosts、DNS policy 中 Geo / RULE-SET 与上游路由参数；分别验证解析结果和请求实际去向。
3. 大订阅边界：目前仍限制 128 节点、32 组、4096 主规则、512 KiB 主文件。扩大前测量预检与隧道内存峰值、取消和更新耗时。
4. 内核协议已支持不等于所有参数组合已接入；继续用受控服务验证新组合。

源码参照：[Verge 配置增强](https://github.com/clash-verge-rev/clash-verge-rev/blob/main/src-tauri/src/enhance/mod.rs)、[Mihomo 组字段文档](https://wiki.metacubex.one/config/proxy-groups/)。执行标准为 `Configuration/Core.lock.json` 固定内核；组排序、自动成员来源与覆盖规则对应 `config/config.go`、`adapter/outboundgroup/parser.go`。现阶段没有移植桌面 TUN、进程识别或脚本执行环境。

## 2026-10-05：关闭项与等价默认写法

本轮减少没有实际运行行为的字段导致的整份拒绝；不按供应商做特判。文件、链接下载、节点列表与 provider 快照使用同一校验及运行配置生成流程。

| 输入 | 处理 |
| --- | --- |
| `tun: {enable: false}` | 省略订阅的桌面 TUN 块；连接仍由 App 创建 iOS Packet Tunnel。 |
| `sniffer: {enable: false}` | 省略关闭的嗅探块，不启用嗅探。 |
| `hosts: {}`、`listeners: []`、`authentication: []` | 接受空容器并从运行配置省略；非空内容仍拒绝。 |
| 节点 `tfo: false`、`mptcp: false`、`smux: {enabled: false}` | 保持关闭，运行配置省略。 |
| VMess `global-padding: false`、`authenticated-length: false` | 保持关闭，运行配置省略。 |
| 已支持传输协议的 `network: ''` | 规范为 TCP；与 WS/gRPC 参数冲突时仍拒绝。 |
| VMess/VLESS `packet-encoding: ''` | 与省略相同，使用原始 UDP 编码。 |

关闭块必须有显式布尔 `false`，不接受字符串 `"false"`、数字 `0`、null、缺少开关或启用值。输入仍先经过内核 YAML 结构校验；关闭块的剩余字段不应用，也不做功能有效性承诺。原始输入完整保留，所有适配进入现有 Info，关闭项不代表其启用功能已支持。

核对固定内核还确认 VMess 的 `cipher` 和 `alterId` 均为必填（`adapter/outbound/vmess.go` 的非 omitempty 字段，`common/structure/structure.go` 的缺字段检查）；不能擅自补 `auto` 或 `0`。`alterId` 缺失现在在 App 校验阶段报告，避免到内核预检才失败。这与 [Mihomo VMess 文档](https://wiki.metacubex.one/config/proxies/vmess/) 一致。显式 ALPN 空数组等行为不等价于省略的输入未放宽。

验证入口：`scripts/check-inactive-compatibility.py` 覆盖关闭/启用/错误类型、原文与诊断脱敏、等价运行配置和全部既有协议组合；`HorizonTests/InactiveConfigurationImportTests` 覆盖真实内核预检、模拟 HTTPS provider 快照及再次校验。均使用虚构输入，不代表真实节点联网验收。
