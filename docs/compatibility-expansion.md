# 协议与导入格式扩展（2026-10-03）

> 2026-10-06 当前增量：复杂 DNS、SS 插件、节点参数、load-balance 与大订阅边界见 [通用兼容性记录](general-yaml-compatibility.md)。下文历史记录中的旧限制以该增量为准。

本轮实现截图中的四项范围，沿用 `Core.lock.json` 固定的 Hako 与现有桥接补丁，没有升级内核。支持声明按以下字段组合限定；离线校验不等同真机联网可用。

## 协议契约

| 协议 | 本轮接入 | 明确限制 |
| --- | --- | --- |
| Shadowsocks | AES-128/192/256-GCM、chacha20-ietf-poly1305、xchacha20-ietf-poly1305；保留 UDP 开关 | 不接受旧式 stream cipher 或 plugin/plugin-opts |
| SS2022 | 2022-blake3-aes-128-gcm、2022-blake3-aes-256-gcm、2022-blake3-chacha20-poly1305；严格检查 Base64 密钥长度；AES 接受最多 8 段身份密钥链 | ChaCha 本版只接受单密钥，不推断错误长度或替换密钥 |
| Trojan | 密码、SNI、ALPN、证书 SHA-256 指纹、客户端指纹；TCP/WS/gRPC | 使用协议固有 TLS；不接受关闭证书校验 |
| VMess | UUID、alterId（0–65535，省略为内核默认 0）、cipher（auto/aes-128-gcm/chacha20-poly1305/none/zero）、UDP、TLS、servername、指纹、ALPN、packet-encoding | YAML 必须指定 cipher；不接受未知字段、旧式 TCP HTTP 伪装、H2/XHTTP 或其他扩展传输 |
| VLESS | 保留已有 UUID/TLS/Reality/Vision；新增普通 TCP/WS/gRPC、可显式不使用 TLS、packet-encoding | Reality/Vision 本版仍限定 TCP + TLS；不支持 XHTTP、非 none 的 URI encryption |
| Hysteria2/hy2 | 原有 YAML 范围不变，增加节点 URI 入口 | 保留原有 Salamander 与 TLS 校验约束 |

WS：`path`、字符串 `headers`、`max-early-data`（0–65536）、`early-data-header-name`。拒绝控制字符、错误类型、未知 WS 选项和错误传输搭配。
gRPC：`grpc-service-name`、`grpc-user-agent`。扩展连接池参数和 multi 模式尚未接入，明确拒绝。

输入明确使用无 TLS 的 VLESS，或无 TLS 且 cipher 为 none/zero 的 VMess 时，Info 标明不加密的情况；不会擅自添加 TLS、更换 SNI 或跳过证书检查。

## 输入格式与入口

- 文件：UTF-8 单文档 Clash YAML、只有 `proxies` 的 YAML、节点 URI 文本列表、Base64 节点列表；JSON 映射作为 YAML 输入处理。文件名去掉 `.yaml` / `.yml` / `.txt` 作为名称。
- “通过链接导入”：安全输入框接受 HTTPS 来源地址或节点内容；系统 PasteButton 可一次粘贴多行列表、Base64 或 YAML。不会自动读取剪贴板。直接输入内容在本机解析，只有 HTTPS/Clash 安装链接执行下载。
- 下载：原下载器的 HTTPS、同源重定向、体积与超时策略保持；响应可以是以上配置/节点列表格式。保存 HTTPS 来源供手动刷新。单节点 URI 是节点凭据，不作为可刷新的来源 URL。
- 二维码/图片：HTTPS、Clash 安装包装链接、SS/VMess/VLESS/Trojan/Hysteria2/hy2 单节点 URI；只回填，经“导入并校验”再确认保存。二维码本身不接受任意 Base64 列表。
- SS URI：SIP002 Base64 userinfo、百分号编码的 cipher:password、旧式整个 authority 的 Base64。插件 URI 明确拒绝。
- VMess URI：Base64 JSON v2（v 省略或字符串 `2`）、TCP/WS/gRPC；不解析任意 VMess URL 方言，未知键/重复 JSON 键/多文档拒绝。
- VLESS/Trojan URI：严格处理 type/security/sni/peer/fp/alpn、WS path/host/ed/eh、gRPC serviceName/gun，VLESS Reality/flow/packetEncoding。未支持参数不丢弃后继续导入。
- Base64：标准或 URL-safe，允许省略填充及编码文本中的空白；解码后必须是节点链接列表。每份总输入最多 512 KiB、1–128 个节点、单 URI 最多 16 KiB；扫码入口另限 8 KiB。

## 桌面控制接口字段适配（2026-10-04）

完整配置现在接受顶层字符串 `external-controller` 与 `secret`（允许空字符串，每项最多 8192 字节且无 NUL）。这两项归类为“需要适配”：iOS 不启用该外部控制接口，生成运行配置时移除两项；App 继续使用隧道 IPC。顶层 `secret` 是管理接口密钥，不是节点密码，节点凭据保持原样。原文只有在用户确认保存后才按原有流程进入本机钥匙串，诊断仅显示固定字段名称和适配说明，不显示地址或密钥值。

适配说明同时出现在导入确认与 Info 兼容性报告中；即使另一个节点或规则仍不兼容，也会报告这两项的适配情况。错误类型仍拒绝；`external-ui`、`external-controller-tls/unix/pipe` 等本轮未接入。没有静默丢弃未知控制接口字段，也不因适配这两项就承诺整份订阅可用。

新增虚构用例 `Examples/compatibility/desktop-controller.yaml`，同时可在 App 样例库中查看。130/130 离线配置、诊断及存储检查通过：适配前后运行 JSON 完全一致、原文保留、报告脱敏、空字符串可接受、错误类型拒绝、其他不兼容项继续阻止导入。模拟器构建与主 App／Packet Tunnel 的 iOS 签名构建、包检查通过。本轮未下载真实订阅、未安装手机或进行联网验收。

## 节点列表模板与原文保留

只有顶层 `proxies` 的 YAML 和 URI 列表补充一个手动 select 组（默认首节点）及 MATCH 规则，沿用系统引导 + Cloudflare DoH。Info 明确说明这不是供应商的原分流配置，普通流量统一交给选中的节点；保存不连接。

2026-10-04 起，节点列表可携带明确支持的元数据与 DNS；已有部分路由配置时不猜测补齐。规则和显式 DNS 不替换，详见 [通用 YAML 增量](general-yaml-compatibility.md)。

原始 YAML/URI/Base64 字节保留在设备钥匙串，派生运行配置仅在内存中生成；节点链接同名时确定性加序号保留全部节点，并给出适配说明。YAML 内重名仍拒绝，避免破坏引用。刷新差异比较规范化结构，回滚恢复原文与选择，沿用现有版本存储机制。

## 验证与复现

```sh
python3 scripts/check-configuration.py
python3 scripts/check-import-qr.py
```

后者使用前者生成的本机 Go 桥接测试模块，Core Image/Vision 需要系统图像服务访问权限。测试仅生成虚构 QR，不读取真实相册、订阅或钥匙串，不连接服务器。

- 123/123 Swift 配置/兼容性/存储检查通过。新增字段保留、17 节点协议/传输矩阵、URI 特殊字符、Base64 两种编码、模板及重名、非法组合、重复参数/键、超量列表、错误脱敏、Base64 版本回滚与选择保留。
- 固定 Go 内核对既有双协议样例与新增 17 节点矩阵的完整 CheckConfig 均通过；只做预检，不启动隧道。
- 虚构 HTTPS 与 VLESS WS 二维码图片实际生成/解码通过；离线导入不请求网络、混合二维码歧义拒绝通过。
- 模拟器（隔离内存库）完成 VLESS WS URI 输入 → 校验 → Info 查看模板 → 确认保存 → 当前订阅更新。VPN 保持未连接。
- 模拟器构建、真机主 App + Packet Tunnel 签名构建、包检查及深度签名验证通过。未安装手机；新增协议的 TLS 握手、TCP/UDP 转发、WS/gRPC、切网、内存与耗电仍需真实节点验收。没有把源码/编译/预检通过当作联网验收。

代码职责：`ConfigurationInput` 识别输入与模板；`NodeURI` 转换链接；`ConfigurationNodeOptions` 定义字段与传输契约；`ConfigurationValidation` 执行节点检查；`PrototypeConfiguration` 生成运行配置；`SubscriptionImportLoader` 区分本地内容与 HTTPS 下载。均在服务/共享层，不放入 View。

## 前三批兼容性扩展（2026-10-04）

本节覆盖前文的旧限制。首页、Horizon、Intro、三 Tab 和现有页面布局不变；仅更新 Info 诊断内容、自动策略组类型与真实选择状态。当前仍是有明确范围的 Clash 配置客户端，并非所有 Mihomo 字段都可用。

### 第一批：识别、诊断及基础语法

- YAML/Clash JSON、节点 URI、带注释的 URI 列表和 Base64 列表继续共用导入管线。HY2 未写端口时补 443，`user:pass` 认证保持完整；支持 DNS 的 IPv4:端口与 `[IPv6]:端口`。
- 识别 sing-box/Xray JSON、Shadowsocks JSON/SIP008、WireGuard INI、其他客户端 INI、OpenVPN 与 HTML 错误页；给出格式层面的明确原因，不伪装成通用 YAML 字段错误，不做猜测转换。
- 已知标准字段使用统一安全名单显示名称；未知名称可能含凭据，仍只显示数量/序号。Info 继续区分直接支持、需要适配、无法使用，尽量同时收集各部分错误。
- 接受并明确适配 `external-ui` / `external-ui-url` / `external-ui-name`、redir/tproxy 等桌面监听端口、profile 持久化提示、组 icon/hidden。原文保留，桌面管理资源不下载，监听端口不启用；profile 选择由 App 钥匙串管理。保留约定范围的 tcp-concurrent、全局客户端指纹、keep-alive 设置。find-process-mode 仅接受 off。

### 第二批：自动策略组

- 支持 `select`、`url-test`、`fallback`，支持内联成员与 `use` provider 成员、嵌套组、tolerance、lazy、timeout、expected-status、max-failed-times、disable-udp。
- 自动组运行时由内核健康检查选择；界面勾选来自实际 `now`，经序号 IPC 回传，离线不把第一个节点冒充自动结果。自动组不作为手动 selector，普通 select 的热切/选择持久化保持。
- 自动组未指定地址时使用 `https://cp.cloudflare.com/generate_204`；默认 interval=300 秒、lazy=true、timeout=5000 ms。自动组 interval=0 采用 300 秒；正数健康检查间隔最低 60 秒（含显式 select 健康检查），Info 明确说明。用户提供的合法健康检查地址仍保留。停止隧道即停止内核健康检查。
- 首页 Ping 以当前 MATCH 策略组为目标；分项连接/DNS 诊断解析真实当前叶节点。自动组切换时可能存在采样间隔内的短暂状态滞后。

### 第三批：providers、规则集与 Geo 快照

- `proxy-providers`：HTTPS `type: http`、`type: inline`；内容为 Clash `proxies` 列表。支持受限 header 与 health-check；所有节点仍逐个通过协议/传输契约。节点总数上限 128，名称全局唯一，组不超过 32。
- `rule-providers`：HTTPS/inline，domain/ipcidr/classical；远程支持 YAML/text，domain/ipcidr 另支持 MRS。classical 仅接受已支持的独立匹配条件，Geo、嵌套 RULE-SET、MATCH 放在主配置。domain/ipcidr 最多 20000 条，classical 最多 4096 条。规则集 YAML 统一生成块列表，解决固定内核漏读行内列表的问题；原始字节仍保留。
- 新增 `SRC-IP-CIDR`、`SRC-PORT`、`DST-PORT`、`NETWORK`、`RULE-SET`、`GEOIP`、`GEOSITE`。GeoIP 支持 DAT/MMDB，GeoSite 支持 DAT；验证格式及分类，DAT 编译命名分类，MMDB 在更新和回滚时明确替换运行时 reader，不沿用旧缓存。
- App 在导入或手动刷新时下载所有依赖，全部验证后才形成候选版本。来源 URL/header 与原文继续受保护；依赖按 SHA-256 标识、256 KiB 分片存入钥匙串，记录只持有清单。索引提交仍是唯一生效点。原文不变但 provider 改变也会显示更新差异；历史/上一份可用版本/手动回滚/启动失败恢复都引用完整资源快照。
- 扩展只读取既有快照：proxy provider 转为内联节点，rule provider 使用 App 生成的受保护临时路径，Geo 仅使用已校验文件。忽略桌面 path 有明确适配提示；不读取用户配置指定的任意本地文件。扩展结束后删除其临时资源目录；异常退出残留仍位于受保护私有容器，下次准备重新覆盖。原文和依赖不会写入普通日志。
- 资源 provider 的 interval 与 geo-auto-update 统一适配为完整订阅手动刷新；不让主配置与资源各自更新。取消/失败不替换当前版本，未引用资源在索引提交后清理；候选未确认前仅留在进程内存。
- 限制：主订阅 512 KiB；最多 35 个远程依赖；节点 provider 2 MiB、规则 provider 8 MiB、单 Geo 32 MiB、依赖合计 64 MiB。每类 provider 最多 32 项。资源仍受 20 秒请求/30 秒总时限限制。
- HTTPS 来源与自定义资源保持同源重定向，最多 5 次。Geo 未提供来源时使用固定内核的 MetaCubeX 公共发布地址；只有三个精确、无查询凭据的公开 Geo URL，才允许到 `release-assets.githubusercontent.com` 的 HTTPS 跳转，不携带用户自定义 header。自定义 Geo/provider/订阅地址不获得此跨源例外。离线回滚不访问这些来源。

### 仍明确不支持

`load-balance` / `relay`、未列入支持范围的 provider override 参数（filter/exclude 与限定 override 已接入，见 selection-policy-compatibility.md）、文件 provider、provider 经指定代理下载、任意跨源订阅跳转、TUN 桌面配置/sniffer/进程规则、复杂逻辑规则、DNS 的 Geo/RULE-SET 选择器与 GeoSite fallback（GeoIP 国家 fallback 已于 2026-10-04 接入，见 dns-compatibility.md）、未列入契约的新协议/传输/SS 插件。仍只支持 rule 模式。未支持项保留阻止导入与脱敏诊断，不会静默丢弃后声称完全兼容。

默认 Geo 数据源属于公共可变发布资源；本地快照固定下载后的字节供回滚，未将其视为固定内核依赖或承诺供应商可达性。大型 Geo 的真机峰值内存、资源下载时长及健康检查耗电仍需实际配置验收。包含资源清单的新记录不应交给不支持快照的旧客户端；退回旧 App 前先保留当前可重装构建，并在新版本中回滚配置，不能依赖旧版本解析新格式。

### 验证与复现

保持原锁定 Hako/Adapter/Go/gomobile 版本；可审计补丁新增 provider 节点批测/诊断查找与 MMDB 显式重载。框架已从源码重建全部三个架构。

```sh
python3 scripts/build-core.py --build
python3 scripts/check-configuration.py
python3 scripts/check-compatibility-batches.py
python3 scripts/check-compatibility-core.py
# native 检查生成虚构 MRS；再跑一次覆盖 App MRS 导入/损坏拒绝。
python3 scripts/check-compatibility-batches.py
python3 scripts/check-import-qr.py
python3 scripts/check-selection-core.py
python3 scripts/check-core-privacy.py
```

- 配置、诊断、存储回归 133/133；新增管线回归 39/39（虚构下载、内存存储、失败注入，不访问真实钥匙串）。覆盖 provider-only、同名不同命名空间、资源完整性、分片写入、更新差异、失败提交不替换、完整版本回滚、规则集 YAML/text/MRS、Geo 分类及资源回收。
- 原生 Go 检查真实配置预检、domain 规则集实际匹配、GeoSite/GeoIP 正反命中、MMDB a→b→a 更新回滚及损坏拒绝；模拟延迟/存活状态验证自动组与 fallback 行为，provider 批测/Ping 查找。未启动真实服务、监听器或拨号。
- 既有 QR 图片生成识别、下载大小/重定向/取消、手动节点选择、诊断脱敏、内核隐私/临时生命周期回归通过。下载器新增公共 Geo CDN 严格白名单与反例检查，无实际网络下载。
- 模拟器隔离内存库通过自动组配置输入 → 完整预检 → 确认保存 → 策略组页；离线显示“由策略组自动选择”，不勾选猜测节点、不允许手动改自动组。VPN 保持未连接。
- 模拟器及 iOS 主 App/Packet Tunnel 签名构建、嵌入包检查和深度签名验证通过。尚未安装手机，未实测新增 providers/Geo/自动组的真实联网、后台健康检查、故障恢复、资源峰值或耗电；构建与离线规则验证不等于真机验收。

## 2026-10-04：非 Clash 输入识别与下一步范围

统一导入入口在常规字段诊断前识别非 Clash 内容，错误码为 2020；文件导入、链接下载内容、二维码中的订阅 URL 下载内容以及刷新均经过该入口。二维码自身仍只接受既有 URL／节点链接，不新增任意二维码文本执行或下载行为。

- 结构识别：sing-box、Xray/V2Ray（无法区分时使用合并名称）、Shadowsocks JSON/SIP008。
- 文本签名：WireGuard INI、Surge/Shadowrocket/Surfboard 一类 INI、Quantumult X INI、OpenVPN、HTML 网页、Apple XML 配置描述文件。
- Clash `payload` 规则片段提示需要主配置。未知映射提示无法识别，不猜测具体客户端。
- 基于内容而非扩展名；允许开头注释、BOM 与常见换行。JSON 注释仅用于识别其他格式，不意味着接受 Clash JSONC。损坏语法仍走语法错误；不承诺识别任意编码、二进制描述文件或所有客户端变体。
- Clash JSON、YAML、仅 proxies、已支持 URI/Base64 路径继续保留。存在 Clash 主结构但夹杂未知字段时仍走兼容性诊断，避免把“不支持某字段”错误描述成“不是 Clash”。字符串内容中的 `[Peer]`、`<ca>` 不作为格式依据。
- 格式提示提供中英文固定文案，不输出输入值、未知字段名或下载 URL；现有提示区和 Info 展示，不改变布局。失败不会进入保存步骤。

验证命令（仅虚构数据；依赖之前构建的固定 host parser）：

```sh
python3 scripts/check-import-formats.py
python3 scripts/check-compatibility-batches.py
# 已运行 scripts/check-configuration.py，具备本地 host parser 后：
python3 scripts/check-diagnostic-text.py
```

广泛兼容的后续实施顺序：

1. 以真实需求的脱敏输入固定用例，按“可解析、可运行、行为等价、真机验证”分别记录结果，保持一次列出所有阻断项。
2. 优先补齐现有 Clash 数据流：更多 provider override 参数（filter、exclude-filter 与基础覆盖的引用／选择语义已接入，见 selection-policy-compatibility.md），再逐项补 DNS policy、fallback、规则组合。不能只扩大白名单；每项须同步适配、诊断与行为测试。
3. 保留原文，生成可审查的运行配置；依赖完整下载并预检通过才替换当前版本。大订阅先测主 App 和 Packet Tunnel 的内存峰值，再有依据地调整 128 节点等上限。
4. 用本地可控服务验证 TCP/UDP、TLS/传输参数、规则实际命中、DNS 走向、切换及更新失败恢复，再由用户进行目标订阅真机验收。
5. 其他客户端整份配置转换另行评估。节点分享链接可单独接入；不能因节点转换成功就声称路由、DNS 或脚本行为等价。Verge 覆写／脚本与原订阅应分别收集，先实现有边界的声明式覆盖。

格式依据参考官方资料：[sing-box outbounds](https://sing-box.sagernet.org/configuration/outbound/)、[Surfboard 配置结构](https://getsurfboard.com/docs/profile-format/overview/)、[WireGuard 配置说明](https://www.wireguard.com/quickstart/)。检测是保守签名识别，不是这些客户端的完整解析器。

### 实际来源只读检查与统一失败提示（同日）

使用 App 的 SubscriptionDownloader（相同请求头、512 KiB 上限与同源重定向规则）检查本轮用户指定的两个来源。URL、令牌和响应原文不写入本仓库或报告，响应只在内存及解析器管道中处理；未启动 VPN 或连接节点。

- 来源 A：成功下载，识别为 Clash 配置；100 个内联节点，65 个指定 skip-cert-verify=true，触及当前拒绝关闭证书校验的策略。还有 48 条未接入类型的规则，以及部分未通过当前 CIDR／域名匹配校验的规则。计划中有 1 个远程依赖，本次没有下载或预检该依赖；诊断中的“依赖尚未下载”不等于 App 下载失败。已有独立阻断项足以判断当前无法完整导入。
- 来源 B：成功下载，为 Base64 节点 URI 列表，共 58 条：34 条 VLESS/Reality + gRPC、10 条 TUIC、14 条 Hysteria2。当前前两类组合／协议未接入，因此整份列表拒绝导入，不静默丢弃不支持的节点。未测试节点可达性。
- 上述是当次响应和当前校验器的结论，供应商可能按时间、User-Agent 或来源网络返回不同内容；不能当作手机实时请求成功的保证。

文件导入、URL／二维码链接导入后的下载与校验、确认保存失败，统一弹出简短提示：“请尝试导入标准 Clash / Mihomo 格式的订阅。”提供“查看原因”展开已脱敏诊断；原有 Info 仍保留。用户主动取消下载不触发失败提示。通用建议不将所有失败重新分类为格式错误：标准 Clash 也可能因字段支持范围、下载或存储失败而拒绝导入。

验证：模拟器构建通过；用虚构 sing-box 内容完成导入失败弹窗、英文提示与详细原因页的运行检查。仅离线演示内存订阅，未操作真机或真实 VPN。

### 两份目标订阅适配与复查（2026-10-04）

本节替代上节关于这两份响应“当前不能导入”的结论；不扩大为所有同类订阅均兼容。

- TUIC v5：接入 YAML 与 `tuic://` URI（UUID/密码），保留 SNI、ALPN、拥塞控制和 UDP relay mode 等已验证字段。未知参数仍拒绝；未接入 TUIC v4 token。
- VLESS Reality + gRPC：与 Vision flow 分开校验。Reality 支持 TCP/gRPC + TLS；Vision flow 仍限制 TCP，不能混搭 gRPC。沿用固定内核的实现。
- 证书校验：允许保存 `skip-cert-verify: true`，导入不等于授权。连接前以原生弹窗明确风险、涉及节点数及授权范围；授权覆盖当前内容版本中的连接、自动选择与测速。拒绝时不启动；Packet Tunnel 独立复核，不能绕过主 App 直接启用。确认摘要与原文/依赖快照绑定并存入原保护记录；内容变化清除许可，选择节点不清除。更新等待确认不算内核启动失败，不触发错误回滚。回滚到不同内容如包含该选项，也须重新确认。
- 进程规则：经用户确认，主配置中的 `PROCESS-NAME` 在运行配置中停用，Info 列出数量与后续匹配行为；原文不改。规则诊断使用实际运行规则及索引。其他进程规则及 classical provider 内需此适配的规则仍不默许通过。
- IP-CIDR / IP-CIDR6 依负载判断地址族；DOMAIN/DOMAIN-SUFFIX 国际化域名转换为 ASCII/Punycode，运行时命中已验证；原文保留。

两份私有来源使用正式下载器、资源准备与 Swift 校验器重新读取，并经固定 Go 内核 `CheckConfig` 完整预检：

| 来源 | 格式/节点 | 规则及依赖 | 结果 |
| --- | --- | --- | --- |
| A | Clash YAML；100 节点、6 组 | 原始 867 条 → 运行 819 条；1 项 Geo 依赖下载并校验 | 预检通过；65 节点跳过证书校验，未授权使用 |
| B | Base64 URI；58 节点、1 个补充 select 组 | 34 VLESS Reality/gRPC、10 TUIC v5、14 Hysteria2；补充 MATCH | 预检通过；未发现跳过证书校验节点 |

响应及运行配置只在内存/管道中处理，临时落盘仅为 Geo 依赖并在检查后删除；未把真实 URL、节点凭据写入源码、示例或报告。未连接真实节点、未启动 VPN、未安装真机，因此不能把预检通过当作节点可达性或 iOS 联网验收。

可重复验证（全部虚构输入；先构建固定 host parser）：

```sh
python3 scripts/check-target-compatibility.py
python3 scripts/check-target-core.py
python3 scripts/check-import-formats.py
python3 scripts/check-compatibility-batches.py
python3 scripts/check-import-qr.py
```

本轮已通过：26 项目标适配检查；135 项基础离线自检；84 项格式检查；39 项既有扩展回归；iOS Simulator 的证书确认/旧回调拒绝与断网保护共 3 项测试。固定内核本地 loopback 的 Reality/gRPC、TUIC v5 native/bbr 互通，以及 TUIC 无效认证/证书反例通过；IPv6 和 Punycode 实际规则匹配通过。测试不依赖真实节点，真实手机网络、供应商端兼容性及大配置性能仍需后续验收。

补充验证：二维码图片识别、TUIC 分享链接入口及离线导入回归通过；沙盒内 Core Image 测试图片生成失败，在可访问系统图形服务的本地环境中重跑通过。主 App 与 Packet Tunnel 的 iPhone 目标未签名构建通过（`CODE_SIGNING_ALLOWED=NO`）；仍有原先 SubscriptionQRCode 调用 NodeURI 的两个 actor 隔离警告，本轮没有把它们当作已解决。未签名产物未安装至设备。
