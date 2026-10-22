# Clash iOS 功能完整性评估与实施计划

> 后续进度：构建 16 已接入真实速率曲线、可取消的三并发批测与三页 UI，并完成相应真机检查，见 [实现与验收记录](live-traffic-batch-ui.md)。下表保留本次 PDF 初始评估的基线；未列入构建 16 的功能并不因此完成。

2026 年 10 月 2 日，构建 15。御坂依据用户提供的 11 页《Clash iOS 功能需求与验收规格》，重新核对当前工作区源码、构建及已有测试证据。结论：**本地配置到真实代理联网的基础闭环已具备；完整产品目标仍处于阶段 1 收尾之前。下一步先补状态、取消、版本与诊断，再开发远程更新和新增 P0。**

本轮交付评估与计划，不执行 PDF 第 11 页实施模板中的业务代码修改。保留现有内核、签名、共享钥匙串、部署目标和编号节点模型；不操作手机或 VPN，不读取真实订阅。本文件不规定视觉风格或导航入口数量。

## 一页结论

| 分类 | 当前结论 |
| --- | --- |
| 已实现且有使用证据 | 本地 YAML 导入确认、保存不自动连接、配置列表/详情/命名、多份保存与切换；Hysteria2 连接/断开/重连、当前 MATCH 节点手动 Ping、后台网页；独立结束主 App 后扩展存活 |
| 已实现且有离线或隔离界面证据 | 去重、旧数据迁移、每配置独立选择、重命名、单项/多项删除及清理失败处理；有限协议/规则/DNS 校验；固定诊断与隐私错误分类。不能由此推导所有真实网络组合已通过 |
| 用户补充验收 | 两份真实配置切换、Wi-Fi/5G 切换正常；短时断网和锁屏恢复未见明显问题；内存与耗电观察正常。保留为用户反馈，不冒充受控工具测量 |
| 部分实现，下一阶段补齐 | 系统/引擎/可达性三类状态的新鲜度，连接 operationID 与取消闭环，运行配置版本确认，失败结果持久化，快照会话标识，导入错误定位、取消与主线程负载，辅助功能 |
| 尚未实现 | URL 下载与主动粘贴、远程更新与版本回滚；global/direct；节点热切、批测、自动策略；规则浏览/编辑/providers；实时速率；连接记录与关闭；完整日志、脱敏导出、完整设置和系统入口 |
| 当前已观察到的异常 | 双节点配置的真实上游 DNS 查询两次超时，网页同时可用；原因未定位，不将其记为 DNS 全部通过 |
| 本轮验证 | 无签名 iOS App + 扩展构建、嵌入包检查、主机虚构配置 61/61、双协议内核预检、诊断结果检查通过；没有本轮真机安装、签名复验或 XCTest 执行 |

不计算“完成百分比”：一个 F 编号包含多种成功、失败、取消和恢复路径，各项工作量也不同。以下按子能力记录，避免用入口数量代替完成度。

## 依据与构建基线

- 原规格：`Clash_iOS_功能需求与验收规格.pdf`，11 页，SHA-256 `03008ae01f2160e2d47e85745288ba48d8b83ad526e7d0448e38a9f88feae8b5`。F01–F17 在第 2–7 页，架构在第 8 页，阶段及 T01–T21 在第 9–10 页。
- 当前为 `main / 80efb6d` 加未提交工作区；提交号不包含大部分业务实现。核对 70 份实现、配置和脚本文件的哈希，留存于本地 `.build/research/requirements-pdf/source-manifest.json`。
- App 入口为 `ClashApp → DiagnosticsView`；后者拥有唯一的运行控制器并向功能页传递。尚未提升到 App 层，当前没有多个生产页面各建控制器。
- App、PacketTunnel、ClashTests、ClashUITests target 仍在；构建 15、最低 iOS 26.5、Swift 5.0；Xcode 26.5 (17F42)、iOS SDK 26.5。
- 固定 Hako `9437767346a63957c60bf027b6d9fb27e51d89c4`、Adapter `6a47cf91350ab80024e9bb4003264dd01100bdbd` 和既有隐私补丁。没有重新调查最新版或建议换内核。
- `.build/` 中已有 XCFramework 用于此次构建；这证明当前源码可构建，不等于本轮从零重建内核或字节级可复现。
- PDF 的历史基线应补入后续证据：真实配置切换、切网和锁屏反馈，以及本次重新运行的主机 61/61。仍没有本次手机 61/61、VLESS 真机请求或长期稳定性的新证据。

| 证据 | 当前源码或记录 |
| --- | --- |
| E1 入口与页面职责 | [ClashApp](../Clash/App/ClashApp.swift)、[DiagnosticsView](../Clash/Features/Diagnostics/DiagnosticsView.swift)、[协作约定](../AGENTS.md) |
| E2 连接、状态、导入与异步返回 | [TunnelController](../Clash/Services/TunnelController.swift)：`monitor`、`refresh`、`prepareImport`、`start/stop`、`refreshSnapshot`、`activateSubscription` |
| E3 配置存储与迁移 | [SubscriptionLibrary](../Shared/SubscriptionLibrary.swift)、[SubscriptionRepository](../Shared/SubscriptionRepository.swift)、[ConfigurationVault](../Shared/ConfigurationVault.swift) |
| E4 配置契约 | [PrototypeConfiguration](../Shared/PrototypeConfiguration.swift)、[ConfigurationValidation](../Shared/ConfigurationValidation.swift)、[ConfigurationDNS](../Shared/ConfigurationDNS.swift)、[ConfigurationRules](../Shared/ConfigurationRules.swift)、[兼容表](compatibility.md) |
| E5 节点与 Ping | [ConfigurationCatalog](../Shared/ConfigurationCatalog.swift)、[NodeSelectionView](../Clash/Features/Configuration/NodeSelectionView.swift)、[PingTestView](../Clash/Features/Ping/PingTestView.swift)、[PingReport](../Shared/PingReport.swift) |
| E6 扩展与数据契约 | [PacketTunnelProvider](../PacketTunnel/PacketTunnelProvider.swift)、[CorePlatform](../PacketTunnel/CorePlatform.swift)、[TunnelSnapshot](../Shared/TunnelSnapshot.swift)、[ConnectivityReport](../Shared/ConnectivityReport.swift) |
| E7 本地管理 UI | [SubscriptionListView](../Clash/Features/Subscriptions/SubscriptionListView.swift)、[SubscriptionDetailView](../Clash/Features/Subscriptions/SubscriptionDetailView.swift)、[SubscriptionRenameView](../Clash/Features/Subscriptions/SubscriptionRenameView.swift)、[ImportConfirmationView](../Clash/Features/Configuration/ImportConfirmationView.swift) |
| E8 验证证据 | [订阅记录](subscriptions.md)、[稳定性记录](stability-validation.md)、[设备记录](device-validation.md)、[PrototypeSelfCheck](../Clash/Support/PrototypeSelfCheck.swift)、[SubscriptionSelfCheck](../Clash/Support/SubscriptionSelfCheck.swift) |

## F01 至 F17 逐项差异

“部分”表示对应 F 项已有子能力，但尚未满足整项要求；“未实现”不因内核存在相似 API 而升级状态。

| 编号与 PDF 页 | 结论 | 已有实现与证据 | 缺口及完成条件 |
| --- | --- | --- | --- |
| F01 连接状态，p2 | 部分 | 六种真实 NE 状态、前台刷新；引擎快照和手动检测与系统状态分开；不会将 Ping 失败直接写成未连接。E1/E2/E6/E8 | 缺少明确的同步中/过期、等待授权与持久失败上下文、连接开始时间；引擎与可达性无统一带时间的状态。当前“准备 VPN 配置”独立触发授权，需整合为用户连接意图内的流程 |
| F02 取消与并发，p2 | 部分 | 扩展生命周期串行，启动检查取消；UI 在 connecting/reasserting 可请求停止；Ping/诊断 ticket 丢弃部分迟到结果。E2/E6 | 连接和配置命令没有统一 operationID/任务所有者；无即时锁定连接意图与完整取消阶段；快照无防旧会话机制。须用可控回调验证连点、取消、迟到与状态同步 |
| F03 运行中切换，p2 | 主路径已有，异常闭环不足 | 先确认、校验，再停止、选择、请求连接；15 秒上限、150 ms 检查，超时不执行后续切换。用户反馈两份切换正常。E2/E7/E8 | `activeID` 在新隧道启动前提交，缺少已保存/已选/实际运行版本的区分；重连失败只留通用会话消息。需保留对象级结果和明确恢复路径，注入超时/存储/启动失败验收 |
| F04 本地导入，p3 | 部分 | 安全作用域文件读取、512 KiB 限制、语法/字段/引用/差异检查、适配确认、稳定 UUID、来源文件名，保存不自动连接。E2/E3/E4/E7 | 尚无来源类型与配置修订号；无安全行号定位；校验失败没有可保留的候选任务。同步读取和解析在 MainActor；完整 `HakoCheckConfig` 在扩展启动时执行，导入阶段不是全部内核预检 |
| F05 管理与删除，p3 | 基础管理已有，详情契约不足 | 列表、详情、重命名、单删/多删、去重、迁移、独立节点选择；删除活动项先断开；索引提交和待清理记录有离线故障测试，隔离真机 UI 验证。E3/E7/E8 | 详情未展示稳定 ID、版本、来源类型和对象级最近应用/错误；重命名 sheet 无未保存修改离开提示；无撤销/备份。相同原文再导入会以文件名更新显示名，后续需区分用户自定义名称 |
| F06 远程更新回滚，p4 | 未实现 | 仅有可复用的本地导入校验和 Keychain 仓库。E3/E4 | URL/主动粘贴、可取消下载、来源脱敏、独立版本、并发校验、应用确认、失败保留、主动回滚、历史与真实元数据均待做；现有去重或切换旧配置不等于版本回滚 |
| F07 节点选择，p5 | 部分 | 编号/协议标识、嵌套 select、每配置持久选择、连接中禁改、明确下次生效。E3/E5 | 无编号/协议搜索；MATCH 标签由已保存配置推导，没有扩展确认的运行版本/选择摘要；热切、收藏和自动策略未做 |
| F08 Ping，p5 | 单点测试已有，完整任务状态不足 | 当前 MATCH 递归节点、HTTP 204、10 秒、统一延迟、测试时间与固定失败分类；与诊断互斥，失败不显示 0 ms；已有 HY2 请求证据。E2/E5/E6/E8 | 没有明确取消/过期状态和测试对象版本；底层失败部分合并为“请求失败或超时”；无批测、并发限额、批次取消和稳定排序 |
| F09 模式与自动策略，p5 | 仅 rule 已有 | 校验器明确拒绝 global/direct 和非 select；不存在伪可用模式入口。E4 | global/direct 的配置、运行确认、重连与恢复未接入；url-test/fallback/load-balance 等须逐种定义与验证 |
| F10 规则与资源，p5 | 浏览管理未实现 | 已校验有限 DOMAIN/IP-CIDR/MATCH 规则并保留顺序。E4 | 无规则浏览、搜索、来源、命中关联和高级编辑；proxy/rule providers 未接入。现有规则解析不等于本 F 项产品功能完成 |
| F11 流量采样，p6 | 手动累计快照已有 | 包数、丢包、可选代理字节、扩展内存、物理链路。E2/E6 | 无采样时间/会话 ID/有效性、速率、历史及采样所有权；部分缺失底层数值用 0 补齐。须先完善数据契约，再计算同会话差分 |
| F12 连接列表，p6 | 未实现 | IPC 未提供连接记录。E6 | 列表/详情、规则链关联、搜索过滤、单条/全部关闭与确认、隐私预览全部待做；不能假设可取得进程名 |
| F13 诊断事件，p6 | 基础已有 | 系统错误摘要、节点/DNS 诊断、离线自检、最多 100 条带时间的 App 会话事件；当前超时如实显示。E2/E6/E8 | 缺少分项检测时间、配置/运行关联、固定诊断 ID、下一步建议、复制与脱敏导出；事件只在内存，不是每份配置的持久历史 |
| F14 完整日志，p6 | 未实现 | core 固定 silent；原始回调丢弃，保留固定 OSLog 阶段与 App 事件。E4/E6 | 新增结构化日志、等级/模块/关联、边界脱敏、条数/字节限制、搜索/追尾/截断/导出。不能直接打开 raw core 日志替代实现 |
| F15 设置维护，p7 | 零散维护已有 | 准备/移除本 App VPN、错误查询、离线诊断、钥匙串删除清理；文档保存锁定内核与许可证信息。E1/E2/E3 | 无完整设置及关于/许可证页面；DNS/路由来源与未应用编辑、备份恢复、按需连接、App Intents/Widget/控制入口未做 |
| F16 隐私，p7 | 现有边界已落实，新增功能待沿用 | 编号节点；共享钥匙串 AfterFirstUnlockThisDeviceOnly、禁同步；错误固定分类、原文不进正常日志；未启用分析上传。源码与离线检查支持。E3/E5/E6/E8 | 尚无备份、连接数据或诊断导出，因此其预览和脱敏未验收；不据现有检查声称已完成全面安全审计或无泄漏证明 |
| F17 可达性，p7 | 部分、未专项验收 | 原生列表/按钮、明确保存/取消、文字错误和空列表；主要页面各自成文件。E1/E7 | 没有 VoiceOver/大字长文本验收；选中状态需可读语义、编辑离开处理、搜索上下文和空/未加载区分；对象详情缺少长期结果 |

## 优先处理的具体差异

以下是源码可见的缺口或可构造竞态，不冒充已经在手机复现的故障。

1. **连接意图没有统一生命周期。** `start()` 依赖 NE 状态更新来禁止下一次连接，调用当下没有设置独立的操作令牌。`isBusy` 和局部 ticket 不覆盖所有命令。先用 fake driver 控制回调顺序，验证取消后启动回调、反复点击、系统侧断开与切换冲突，再补实现。
2. **钥匙串错误可能阻止系统状态刷新。** `refresh()` 先 `reloadConfiguration()`，后读取系统 VPN；前者抛错会跳过系统同步。仓库失败只置 `libraryReady = false`，已有 `hasConfiguration/catalog` 可能保留，而 `canStart` 未检查 `libraryReady`。需分别保留“上次可信值”和“当前可执行性”，读取失败不能伪造系统状态或继续使用未核验配置。
3. **旧快照没有会话边界。** `refreshSnapshot()` 回来只判断当前 connected/reasserting；旧请求若在重连后返回，有写入新页面的可能。`TunnelSnapshot` 无 sessionID/时间，扩展桥接缺失时用 `?? 0`；不能直接在其上做速率。诊断在 reasserting 中也缺少过期标记。
4. **保存与真实应用尚未形成版本关系。** `sourceDigest` 是去重依据，`clash-vault-v2` 是存储格式号，都不是可回滚的配置版本。`SubscriptionSummary.updatedAt` 也不是远程成功更新时间。扩展当前只读活动记录，无法向 App 确认正在运行的具体修订。
5. **导入和错误体验还不足以支持更多输入来源。** `prepareImport()` 同步做读取与内核解析；语法错误只显示通用摘要，失败候选不保留。先把候选任务与后台校验解耦，保留隐私错误边界，再增加 URL。
6. **已有 DNS 超时不能靠换默认 DNS 隐去。** 先比较原配置真实上游、受控解析及代理网页这几条路径；区分本次检测失败与整体网络不可达。未经明确选择，不替换用户 DNS、修改 respect-rules 或降低 TLS 校验。

## 后续交付顺序

各阶段单独保持可构建；完成对应的失败/取消/恢复验收后才开放入口。PDF 的 P0 是完整目标优先级，不表示这些能力现已具备。

| 阶段 | 交付内容 | 依赖与退出门槛 |
| --- | --- | --- |
| 0 基线评估，本轮 | F/T 映射、当前构建与证据、复用点、文件计划 | 本文及本轮主机检查完成；没有新增真机验收 |
| 1A 连接和异步状态 | App 层同一控制器；系统/引擎/可达性分开；同步/过期上下文；operationID、串行意图、取消与失败恢复 | T04/T05/T06/T14；可控制迟到回调的自动化测试，真机取消授权与连接中停止再补专项证据 |
| 1B 配置和诊断收尾 | 来源/修订/应用结果模型与兼容迁移；后台导入、候选保留、错误字段定位；选中/运行分离；编号搜索；Ping 取消/过期、诊断时间；DNS 根因定位 | T01–T03/T07–T09/T17–T20 的已有范围；旧数据保留；15 秒超时不切换；无误导成功；不扩大协议白名单 |
| 2A 远程配置版本 | 用户主动 URL/粘贴、可取消下载、候选校验、独立版本、更新记录、确认应用、失败保留与主动回滚 | 依赖 1A/1B 的 operationID、修订号及扩展运行确认；T10/T11；先单份手动更新，再批量，默认不自动更新 |
| 2B 真实模式 | global/direct，保存值与运行值分开，首次按断开重连应用 | 依赖运行版本确认；T12/T17；验证 DNS/规则/IPv6 和失败恢复；模式改变真实流量去向，需明确应用确认 |
| 2C 真实流量采样 | sessionID、单调时间、计数有效性；统一 TelemetryStore；速率与有限历史；前台按需采样 | 依赖 1A 的会话识别；T13/T14/T21；计数回退、断开、重启和重复时间不产生伪零或尖峰 |
| 2D 代理增强 | 可取消批测、稳定结果/排序；收藏；逐种接入自动策略，随后评估节点热切 | 先能力协议与受控测试；T08/T09/T12/T21；批测不擅自改选，自动出口可解释，热切不得仅修改 UI |
| 3A 规则与资源 | 先当前支持规则的只读浏览/搜索与来源；再校验编辑、proxy/rule providers、资源更新；按实际配置扩大协议组合 | 复用 2A 更新事务；T03/T10–T12/T16/T17；逐种格式验收，不一次放开内核所有字段 |
| 3B 排查和维护 | 连接记录/详情/关闭；结构化日志；脱敏报告预览导出；高级设置与备份恢复；关于及许可证 | E6 能力桥接后做 T15/T16/T18/T19；缓存有界，元数据不默认上传；关于页可在阶段 1 后提前独立交付 |
| 4 系统入口 | 用户选定的 App Intents、快捷指令、Widget、控制入口；按需连接作为独立可选设置 | 复用统一命令与状态，单独验证权限、后台与多进程协调；不自动启用按需连接 |

辅助功能和隐私跟随每阶段验收，不能全部推迟到阶段 4。界面设计由用户另行提供；实现前只增加完成任务所需的清晰测试页面。

## 第一阶段文件级计划

以下是拟修改或新增的文件，尚未创建新抽象或空目录。保留已有 `SubscriptionRepository` 名称作为配置仓库，不仅为匹配 PDF 的概念名称而整体重命名。

| 顺序 | 文件与复用点 | 具体改动及验收 |
| --- | --- | --- |
| 1 | `Clash/App/ClashApp.swift`、`Clash/Features/Diagnostics/DiagnosticsView.swift` | 把同一个 TunnelController 的所有权提升到 App/根容器，依赖注入子页；诊断演示仍隔离；监听不随页面重复启动。验证前台/返回、演示与实际库边界 |
| 2 | `Clash/Services/TunnelController.swift`；拟增 `Clash/Services/ConnectionState.swift` | 系统原始状态、同步有效性、引擎与可达性、连接时间独立；操作 ID、阶段、取消与真实失败；拆开钥匙串加载与系统同步，保留原始状态语义 |
| 3 | 拟增 `Clash/Services/TunnelSystemClient.swift` | 用薄协议包装现有 NETunnelProviderManager 操作和状态来源，使单元测试能控制授权、迟到、断开超时和系统侧状态；不另造生产连接状态 |
| 4 | 拟增 `Clash/Services/EngineClient.swift`、`Shared/EngineMessage.swift`；复用 `PacketTunnel/PacketTunnelProvider.swift` | 从控制器抽出 IPC 编解码/超时，新增带版本的请求与能力信息；回传 sessionID、运行配置修订与安全结果；未识别版本明确失败，不开放外部控制端口 |
| 5 | `Shared/SubscriptionLibrary.swift`、`SubscriptionRepository.swift`、`ConfigurationVault.swift` | 在既有 Keychain 项上做兼容迁移，加入来源、修订、选中/运行关联、最近应用结果/错误；阶段 1 不等同完整历史回滚。扩展读取指定修订并核验，事务完成条件不能只看保存成功 |
| 6 | `Clash/Services/SubscriptionImportPreview.swift`；拟增 `Clash/Services/ConfigurationImportService.swift`；复用 `Shared/PrototypeConfiguration.swift` | 解析移到受控串行工作队列，候选只留内存/受保护存储；取消使迟到结果失效；固定字段/行列摘要不包含源值，完整核心预检与实际启动校验各标明边界 |
| 7 | `Shared/TunnelSnapshot.swift`、`PingReport.swift`、`ConnectivityReport.swift`；对应扩展与组件 | 增加会话/时间/有效性及测试对象修订，缺失计数用 Optional；明确 cancelled/stale；先保留手动快照，不在本步生成实时速率 |
| 8 | `Clash/Features/Subscriptions/`、`Features/Configuration/NodeSelectionView.swift`、`ImportConfirmationView.swift`、`Features/Ping/PingTestView.swift` | 详情显示来源与应用结果；选中/运行分开，编号搜索；编辑离开处理；可读选中状态、完整长错误。各主要 View 保持独立文件，业务逻辑仍在服务层 |
| 9 | `PacketTunnel/ConnectivityProbe.swift`、诊断组件及故障说明 | 对上游 DNS 超时做受控复现和分项解释；记录时间、查询路径和下一步；先找到证据再决定是否修改实现或建议配置，不静默更改用户 DNS |
| 10 | `ClashTests/`、`ClashUITests/`、已有虚构自检与 `docs/` | 针对操作竞态、版本冲突、边界及迁移写有意义的测试；UI 自动化补现有模板缺失的导入/取消/保存/选择/删除路径；逐步补对应真机授权与网络证据 |

建议分成四个可独立审查的小批次：状态与意图 → IPC 会话身份 → 仓库/导入与结果追溯 → 页面状态与验收。每批先保持当前配置可用，再推进下一批；不一次重写 View 与内核。

## T01 至 T21 验收矩阵

本表不是新的 21 项通过报告。“历史/用户”只覆盖明确记录的子场景；“本轮离线”指重新执行的虚构测试，未操作手机。

| 用例 | 当前证据 | 仍需补齐 | 对应阶段 |
| --- | --- | --- | --- |
| T01 无配置/导入取消 | 空状态 UI 历史验证；无活动配置不可连接；取消候选代码存在 | 取消不同阶段、读取失败后不残留候选；未知/未加载不假装空 | 1B |
| T02 导入/重复/迁移 | 本轮 61/61 中有去重、迁移、保留选择、保存不设为当前；历史导入与迁移联网 | 完整文件选择到取消/确认的 UI 回归，新增字段兼容迁移 | 1B |
| T03 语法/上限 | 校验器限制存在；本轮含超字节、重复键/引用等拒绝检查 | 恰好 512 KiB、128 节点、32 组、4096 规则及各自超一的系统边界用例，字段定位与响应性 | 1B |
| T04 权限/系统移除 | 有准备/移除及前台同步代码，早期真机授权成功 | 拒绝/取消、不循环、系统侧移除、再次恢复及未确认状态 | 1A |
| T05 系统连接/检测失败 | 历史手机已连接与 DNS 超时并存，未改写为断开 | 分项时间/过期、下一步和根因定位 | 1A/1B |
| T06 快速连点/取消迟到 | 局部 guard、ticket 和扩展取消检查 | 全流程操作 ID、可控竞态测试和手机连接中取消 | 1A |
| T07 运行中切换 | 用户两份配置反馈正常；代码有 15 秒等待上限 | 超时不提交、钥匙串失败、新版本启动失败与结果追溯 | 1A/1B |
| T08 节点/配置独立选择 | 本轮持久选择/解析自检；断开限定与每份选择已实现 | 运行时确认、热切限制说明、嵌套实际选择与出口对应 | 1B |
| T09 MATCH Ping/互斥 | 本轮延迟分类；历史 HY2 请求；两端互斥和 ticket 代码 | 测速中断开/取消/恢复、过期及迟到任务；批测另验 | 1B/2D |
| T10 更新下载/校验失败 | 无远程更新 | 各网络错误与候选校验失败保留旧版；来源编辑和重试 | 2A |
| T11 并发更新/回滚 | 无版本事务 | 晚到响应、编辑冲突、应用失败、回滚失败与持久恢复信息 | 2A |
| T12 模式/providers 边界 | 未支持项明确拒绝；本轮含 providers 拒绝检查 | 三种模式及各资源的能力协商/运行一致性 | 1B/2B/3A |
| T13 统计有效性 | 只有手动累计快照，无速率 | 缺值、负值、计数回退、重复时间、跨会话、扩展重启及过期 | 1A/2C |
| T14 切网/前后台 | 历史后台网页与主 App 单独退出通过；用户切网/锁屏反馈 | 同步时效、没有重复监听、扩展重启后不复用旧统计；不要求用户重复已反馈的正常切网 | 1A/2C |
| T15 连接查看/关闭 | 无实现 | 全部记录关联、缺值说明、关闭确认与失败恢复 | 3B |
| T16 规则/日志压力 | 有规则顺序校验和 100 条会话事件上限 | 规则/日志搜索、空/无结果、字节上限、截断、历史追尾与压力 | 3A/3B |
| T17 来源/未应用编辑 | 导入适配摘要、节点下次生效提示 | 完整设置/编辑来源、版本/运行差异、离开未保存任务 | 1B/2B/3B |
| T18 删除/备份 | 本轮删除、提交失败、清理重试、孤立项、索引损坏用例；隔离手机多删历史 | 活动删除断开超时；备份/恢复另做，不宣称已有撤销 | 1B/3B |
| T19 脱敏 | 本轮固定错误与虚构秘密检查；前轮 core 不落原文检查 | 报告预览、导出、连接元数据及备份的字段级测试；无全面安全通过结论 | 各阶段/3B |
| T20 辅助操作/长文本 | 原生控件，有文字状态 | VoiceOver 完整闭环、大字号/长名称/长错误、选中朗读、编辑取消 | 1B 并持续 |
| T21 真机/长期 | 短时启停、后台、用户无网/切网/锁屏及功耗观察 | 受控慢网、扩展重启、失败恢复、长期任务数/内存趋势；应用 UDP/IPv6 按实际需求验收 | 各阶段 |

## 需要在相应实现前定下的规则

阶段 1 可先按现有功能范围推进，不需要现在重问已确认的文件名或运行中切换方式。下面事项是后续实现决策，不算已获启用授权：

- **远程版本保留**：建议至少保留当前运行、最后成功和一个候选；数量/字节上限须结合 Keychain 实测确定，不先承诺每份无限历史。清理不得删除运行中或唯一可恢复版本。
- **应用成功定义**：建议以系统 connected、内核就绪且确认目标修订为“已应用”；网络可达性另记。这样 DNS 检测失败不会伪装成隧道未启动，同时“最近可用”的条件可再约定。
- **重连失败恢复**：默认保留旧版并提供明确手动恢复，避免悄悄改出口；如要自动回滚，需要单独说明和确认行为。
- **新增能力顺序**：按本文先远程更新回滚，再模式与采样；providers/更多协议用脱敏样本确认必要组合。自动策略、按需连接与后台更新默认不开启。
- **备份与导出**：诊断默认脱敏；含秘密的配置备份是另一项明确操作，需定义保护、预览与恢复流程。

## 本轮验证命令与限制

```sh
xcodebuild -project Clash.xcodeproj -scheme Clash -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/Clash-RequirementsAudit \
  CODE_SIGNING_ALLOWED=NO build
python3 scripts/check-bundle.py /private/tmp/Clash-RequirementsAudit/Build/Products/Debug-iphoneos/Clash.app
python3 scripts/check-configuration.py
xcrun swiftc -parse-as-library -module-cache-path .build/bridge-check-module-cache \
  scripts/check-diagnostics.swift Shared/TunnelDiagnostics.swift Shared/PrototypeError.swift \
  Shared/ConnectivityReport.swift Shared/PingReport.swift -o .build/check-diagnostics
.build/check-diagnostics
```

结果：App 和扩展构建成功；嵌入扩展 ID、入口、可执行文件及版本检查通过；主机离线自检 **61/61**；虚构双协议完整内核预检通过；诊断错误/非法延迟/敏感文本检查通过。最初受限执行因 Swift 宏插件无法运行失败，使用获准的本机构建环境后通过，没有为此修改代码。Go 链接出现重复 `-lresolv` 警告，不影响本轮通过结果。

没有运行 XCTest/Swift Testing runner；`ClashTests` 目前主要包装虚构自检，`ClashUITests` 仍是启动模板，不能把 61/61 当成 T01–T21 或 UI 自动化全部通过。本轮没有签名、安装、启动真机 App、重新联网测试、修改原始 YAML 或新建证书。

原始构建/检查日志、PDF 提取与渲染均在被 Git 忽略的 `.build/research/requirements-pdf/`。报告和 README 为本轮交付文件，其他已有改动保留。
