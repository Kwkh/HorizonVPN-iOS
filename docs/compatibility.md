# 兼容清单

最新：[筛选与 provider 覆盖](selection-policy-compatibility.md)——filter／exclude、限定 override、刷新与回滚成员一致性。

[通用 YAML 增量](general-yaml-compatibility.md)——合法数值写法、节点列表元数据、include-all 自动成员与原生内核对照测试。

## DNS 兼容性增量（2026-10-04）

已适配 `dns.listen`，支持 `dns.prefer-h3: false`，以及基于 GeoIP 国家代码的 DNS fallback（MMDB / DAT）。这取代下文历史表中的对应限制；详细语义、测试与剩余边界见 [DNS 适配说明](dns-compatibility.md)。

## 当前增量（2026-10-03）

协议已扩展 SS/SS2022、Trojan、VMess，以及 VLESS/VMess/Trojan 的约定 TCP/WS/gRPC 组合；新增仅节点 YAML、URI/链接列表、Base64 与节点二维码入口。精确参数、限制和验收证据见 [本轮兼容性扩展](compatibility-expansion.md)。订阅来源/刷新/回滚和 select 热切也已接入。下文构建 13–15 是历史记录，其中“尚未支持订阅 URL／热切”等状态已被新实现取代，不能作为当前范围。

已对用户提供的本地 YAML 做受限结构检查：只输出已知字段、协议枚举与数量，未将节点原文或凭据读入对话，也未复制原文件到项目。本表是调查和验收清单，**不是完整兼容声明**。构建 13 已扩展约定字段的双协议、多节点、select、规则和 DNS，当前代码范围见下表。旧单节点网页、DNS 功能、断开恢复和重连已真机验证；新增组合只有离线检查证据，需单独联网验收。

用户已确认第一份文件没有后续操作、覆写或脚本；第一份文件缺少 DNS/TUN 字段，早期原型新增的网络行为见 [第二阶段说明](phase2-prototype.md)。第二份文件有显式 DNS，构建 13 保留其支持范围内的设置，不套用第一份文件的默认 DNS。真实链接、令牌、账号、密码或私钥只在本机／手机处理；开发讨论使用脱敏结构。

## 构建 15 订阅管理

支持最多 128 份已通过现有契约校验的本地 YAML，按文件名去掉扩展名显示，可重命名。相同原文去重并保留节点选择；同名不同内容另存，名称加序号。每份订阅独立保留节点选择，连接中切换需确认断开与重连，未连接时仅修改当前选择。支持详情删除、侧滑删除和多选删除；原始文件不变。此变化不扩展协议或 YAML 字段范围，订阅 URL/provider 更新仍未接入。具体流程见 [订阅说明](subscriptions.md)。

## 构建 13 实现范围（2026-10-02）

| 项目 | 当前契约与限制 |
| --- | --- |
| YAML | 单份 UTF-8 文档，最多 512 KiB；接受合法 `---` / `...`，拒绝第二份文档、重复键与错误类型 |
| 节点 | 1–128 个；Hysteria2/hy2，可带 Salamander、ALPN、SHA-256 证书指纹；VLESS TCP + TLS，可带 Reality、Vision、客户端指纹。其他协议与传输明确拒绝 |
| TLS | 保留证书指纹和 Reality 参数；不接受关闭证书校验；字段格式通过不代表服务器证书或密钥已实际匹配 |
| 策略组 | 最多 32 个 select；支持组嵌套、DIRECT/REJECT/REJECT-DROP；校验重名、缺失引用和循环。断开后保存选择，下次启动生效；暂不热切换 |
| 规则 | 1–4096 条，保留顺序；DOMAIN、DOMAIN-SUFFIX、DOMAIN-KEYWORD、IP-CIDR、IP-CIDR6、最后一条 MATCH；CIDR 可带 no-resolve。暂不支持 RULE-SET、Geo、进程或逻辑规则 |
| DNS | 支持 normal/redir-host/fake-ip、显式上游与引导解析器、普通域名 policy/filter、有限 fallback-filter；保留显式 DNS IPv6。fallback 需要显式 geoip:false。上游支持 IP 或 udp/tcp/tls/https URL，暂不支持裸 IP:port、DoQ、URL 附加参数、系统解析标记或 Geo/provider 选择器 |
| 缺省 DNS | 未定义 DNS 时沿用已验证的系统引导 + Cloudflare DoH；自定义 DNS 缺少引导器时显式告知补充规则。拒绝 dns.enable:false 和 use-system-hosts:true |
| IPv6 | 保留 ipv6:false 与 DNS 设置；为防止原生 IPv6 绕过仍安装 IPv6 默认路由，并显式添加最高优先级 IPv6 REJECT 规则。导入时说明；尚未证明无泄漏 |
| 桌面字段 | mixed-port、port、socks-port、allow-lan、bind-address 不启用，导入时列出；日志固定 silent，缓存不落盘。其他未适配顶层字段阻止导入 |
| 存储与 Ping | 原 YAML 与选择共同原子写入本机钥匙串，保留旧格式读取；失败不覆盖。Ping 递归解析 MATCH 的实际节点；DIRECT/REJECT 不可测速 |
| 未接入 | 订阅 URL 更新、providers、自动策略组、桌面 TUN/sniffer、其他协议与复杂 DNS；不静默删字段后宣称兼容 |

验证：主机和 iPhone 离线自检均为 **41/41**；实际第二份文件只在内存完成导入契约检查（2 节点、1 组、5 规则，原文与显式引导 DNS 保留）。虚构同结构双协议样本通过固定内核完整 CheckConfig；本机检查未启动服务或连接真实节点。真实文件的证书指纹、Reality/Vision、fake-ip 转发和规则效果仍需逐项真机测试。

复测：`python3 scripts/check-configuration.py`。样本为 [dual-protocol.redacted.yaml](../Examples/dual-protocol.redacted.yaml)，不含真实配置内容。

构建 14 更新：支持顶层布尔 unified-delay，保留显式值，缺省为 true（对齐当前 Mac Verge）。手动测速使用相同默认 Cloudflare HTTP 204 与 10 秒超时。主机/iPhone 自检增至 44/44；已导入双节点配置的 Hysteria2 手动测试两次成功，VLESS 及新配置完整 DNS/规则效果仍待验收。Mac 的全局 IPv6/DNS 覆写不据测速请求自动迁移，继续以已确认的手机导入语义为准。

## 本地样本结构检查（2026-10-01）

| 项目 | 确认结果 | 验收状态 |
| --- | --- | --- |
| 输入 | YAML 映射；顶层仅 `mode`、`proxies`、`proxy-groups`、`rules` | 结构已检查；不是内核校验或联网证据 |
| 模式 | `rule` | 当前单 MATCH 配置已真机运行；其他规则组合未验收 |
| 节点 | 1 个 `hysteria2`；`obfs: salamander` | 真机网页转发通过，用户确认出口匹配；应用 UDP/IPv6 与长期稳定性待测 |
| 节点参数 | 含 `server`、`port`、`password`、`sni`、`obfs-password`、`up`、`down` | 真实值未输出；开发样本全部使用虚构值 |
| 端口类型 | 本地输入使用带引号的数字字符串 | 修复仅接受数值类型造成的误拒绝；接受整数和无歧义的十进制数字字符串，保留原始类型；固定内核虚构样本预检通过 |
| TLS | 未显式提供 `skip-cert-verify`、ALPN 或客户端证书字段 | 保持内核证书校验并保留 SNI，当前节点可联网；无效证书拒绝场景待测 |
| 策略组 | 1 个 `select`，含 1 个成员 | 引用校验和单成员实际转发通过；多节点切换尚未实现 |
| 规则 | 1 条 `MATCH` | 引用校验通过，测试网页出口与该目标节点一致；其他流量覆盖待测 |
| providers | 无 `proxy-providers` 或 `rule-providers` | 此样本不要求；不能据此判断其他订阅需求 |
| DNS / TUN / IPv6 | 原文件未显式设置 | 已明确添加系统 DNS 引导、经代理 DoH、gvisor 与双栈默认路由；网页与解析通过，IPv6 和 DNS 路径/泄漏仍待验收；不推断 Verge 设置 |
| Verge 覆写／脚本 | 用户确认未对文件做后续操作 | 本原型不执行覆写或脚本 |

结构对应的虚构开发样本为 [`../Examples/hysteria2-salamander.redacted.yaml`](../Examples/hysteria2-salamander.redacted.yaml)。其地址、端口、名称、带宽值和密码均为测试占位，不可用于联网。虚构配置用于内核离线预检；真实联网使用用户在手机安全导入的配置，证据见 [第二阶段验收记录](phase2-prototype.md)。

| 范围 | 需要确认的字段／行为 | 预定处理与验收 |
| --- | --- | --- |
| 订阅类型 | 完整 Clash YAML、仅 `proxies`、`proxy-providers`、或非 YAML/base64 节点列表 | 首版只按约定格式导入；其他格式明确拒绝，不送公共转换服务 |
| 协议 | SS 及 cipher/plugin、VMess、VLESS/Reality、Trojan、Hysteria2、TUIC、其他；TCP/UDP、TLS/ALPN、传输层参数 | 先选一个实际测试节点；其他协议按字段与传输组合逐项验收，不能只看协议名称 |
| 策略组 | select、url-test、fallback、load-balance、组嵌套、`use`、filter、健康检查 | 手动 select 优先；后续测试选项持久化、更新后重命名/删除、定时测速的耗电与后台行为 |
| proxy-providers | http/file/inline、path、interval、header、override、filter、health-check | 路径限制在沙盒，header/URL 作为敏感数据；远程更新、引导下载、失败回滚与大小限制单独验证 |
| rule-providers | behavior=domain/ipcidr/classical，format=yaml/text/mrs，interval、url/path | 先固定一份本地样本，再扩展下载；格式及内存按实际需要确认 |
| 规则 | DOMAIN、DOMAIN-SUFFIX、DOMAIN-KEYWORD、IP-CIDR/IP-CIDR6、RULE-SET、MATCH、逻辑规则 | 保留顺序与命名引用；用可控请求验证命中策略，不以“YAML可解析”代替路由正确 |
| GeoIP/GeoSite | 数据源、geodata-mode、geo-auto-update、自定义下载地址 | 初版不自动下载；确有需求才引入固定校验值数据及内存预算 |
| DNS 模式 | fake-ip / redir-host、fake-ip-filter、缓存、hosts、use-system-hosts | 对照 Verge 行为；iOS hosts 与桌面系统 hosts 不等价，fake-ip 池与路由必须配套 |
| DNS 上游 | nameserver、fallback/filter、default-nameserver、proxy-server-nameserver、nameserver-policy、respect-rules、DoH/DoT/DoQ | 明确引导解析与代理路径，检查 TCP/UDP DNS、失败回退及泄漏；不静默替换用户上游 |
| IPv6 | 顶层 ipv6、DNS AAAA、节点可达性、IPv6 规则 | DNS 和路由一起设计；不支持的组合应阻止启用并说明，避免 IPv6 绕过 |
| TUN | stack、auto-route、auto-detect-interface、dns-hijack、MTU、route-address/exclude、strict-route | 路由/DNS由 NE 管理，字段分为保留/转换/拒绝；出具适配报告，用户确认后启用 |
| 桌面入站 | mixed-port/socks-port/port、redir-port、tproxy-port、allow-lan、iptables/nftables | 本机代理服务非首版目标；Linux重定向和桌面系统代理设置不迁移，检测到要明确提示 |
| 进程与设备规则 | PROCESS-NAME/PATH、UID、包名、接口、routing-mark | 普通 iOS packet tunnel 不具备桌面进程识别能力，初版拒绝此类规则或要求用户明确改写 |
| sniffer / TLS特性 | HTTP/TLS/QUIC sniff、override-destination、SNI、指纹、skip-cert-verify | 初版关闭 sniff；按实际需要和内存成本扩展；不擅自降低 TLS 校验 |
| Verge 覆写与脚本 | 合并顺序、全局/订阅覆写、JS 脚本、额外规则与 DNS、实际内核版本 | 不直接执行任意脚本；优先把最终有效配置作为输入。迁移合并行为必须用脱敏用例验证 |
| controller / UI | external-controller、secret、external-ui、LAN绑定 | iOS本项目用受控 IPC；禁止静默开放管理端口；显式报告这些桌面配置未采用 |

## 第二份双协议样本排查（2026-10-02，构建 12）

本次仅在本机读取并解析结构，没有复制原文件、输出凭据或启动节点连接。文件为 1345 字节、单份 UTF-8 YAML；固定内核的 `ValidateConfigShape` 和 `YamlToJSON` 均通过。这些只是结构检查，不是完整配置校验或联网验证。

实际拒绝顺序：

1. 第一行有一个合法的 `---` 文档起始标记。构建 12 对所有以 `---` 开头的行直接拒绝，因此首先返回 `invalidFile (2001)`。这属于导入器误判。构建 13 已修复：由解析器检查文档结束，接受单文档标记并拒绝第二份文档。
2. 即使移除该标记或修复识别，顶层 `mixed-port`、`allow-lan`、`log-level`、`ipv6`、`dns` 仍会触发 `unsupportedFields (2003)`。
3. 文件有两个节点、单个双成员 select 组及五条规则，超出当前一个节点、单成员组、一条 MATCH 的数量和引用约束。

| 实际结构 | 当前缺口／需要保留的语义 |
| --- | --- |
| Hysteria2 + Salamander，另有 `alpn` 和 `fingerprint` | App 的节点字段白名单拒绝这两项。ALPN 为 h3；fingerprint 的结构符合 SHA-256 证书固定校验格式，不能为导入而静默删除。固定内核源码有相应处理，实际证书匹配仍待联网验证 |
| VLESS + TCP + TLS + Reality + Vision | 固定内核存在对应实现，但本 App 尚未接入此配置契约或做真机验证。不能把内核有实现等同于本 App 已支持 |
| 一个 select 组包含两个节点 | 需要接入实际节点选择、保存与 Ping 目标联动；当前 activeNode 只取单节点 |
| 四条 IP-CIDR 直连规则及一条 MATCH | 需要保留顺序及 DIRECT 目标；当前原型只允许一条 MATCH |
| 自定义 DNS：fake-ip、DoH、显式引导解析器，顶层和 DNS 均关闭 IPv6 | 与当前派生配置的 redir-host、固定网站 DoH、系统引导 DNS 和开启 IPv6 不同；不能用原型默认值静默覆盖 |
| mixed-port / allow-lan / log-level | 需要明确桌面监听字段的 iOS 处理方式；继续保持隐私日志策略并在适配说明中可见 |

以上为构建 12 的历史缺口，不是节点不可用的证据。构建 13 已接入这些字段及适配说明，范围和验证边界见本页首表；未修改用户原始文件或降低证书校验。

## 配置管线的约束

保留原始版本与派生的 iOS 配置，输出每个适配字段的原因。不支持项作为阻断性错误；有意忽略的非运行字段也必须可见。禁止解析后丢掉未知字段再声称兼容。

更新候选必须同时通过：结构合法、引用存在、内核校验、平台适配校验。活动配置和最后可用版本采用原子替换，失败不覆盖；控制器 UI 必须区分下载失败、校验失败与运行失败。

Hako 固定源码调查补充：该 fork 提供 `ConfigDeviationsJSON`，同时确实存在配置转换/移除与不可用协议占位行为。必须把差异检查放在启动前；不能将 `CheckConfig` 成功直接视作原始语义已保留。差异值和原始错误文本也需脱敏，完整配置不可写入普通日志。

## 脱敏方式

- 域名改成 `node.example.invalid` 等保留域名；IP 用文档地址。不要保留订阅 URL 中的 query、路径 token、header 或账号。
- 密码、UUID、私钥、证书内容、Reality 密钥等替换为明确的测试占位。供解析测试使用时，再生成协议要求格式的假值。
- 节点名、组名、provider 名可以替换，但同一引用应使用同一假名，保留嵌套、顺序、规则类型、选项键和协议组合。
- 保留端口、协议类型和必要布尔设置来讨论兼容性；任何仍能定位个人服务的值继续替换。
- 说明 Verge 版本、内核版本、TUN/系统代理开关及覆写执行顺序；无需发送真实配置文件本体。

御坂将收到的结构补到此表，并为每个约定项记录“需要／不需要、已实现／待适配／不支持、真机证据”。
