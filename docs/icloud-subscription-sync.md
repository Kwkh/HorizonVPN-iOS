# iCloud 个人订阅同步

实施日期：2026-10-09。入口为设置 → 工具 → iCloud 订阅同步。默认关闭，首次开启明确说明会上传来源链接、节点凭据与配置依赖。没有 Horizon 账号或自建服务器依赖。

最近同步时间按分钟显示：不足一分钟为「刚刚 / Just now」，之后为「N 分钟前 / N minutes ago」，不展示秒数。时间标签按分钟局部更新，数字变化使用原生过渡并响应减少动态效果。

「立即同步」右侧显示 `arrow.trianglehead.2.clockwise.rotate.90.icloud`；同步进行时图标保持静止，按钮保持原有颜色并阻止重复提交，点按时仅做轻微透明度过渡。成功且没有阻塞项后，使用原生按层 Down-Up Magic Replace 切换为 `checkmark.icloud`，一秒后换回。失败或请求未启动时不显示成功勾号。图标占位保持稳定，离开页面或关闭同步会取消待恢复反馈；减少动态效果时采用简化过渡。

## 同步范围

| 同步 | 各设备独立 |
| --- | --- |
| 显示名称、文件名 | 当前订阅、节点选择 |
| HTTPS 来源 URL（含订阅 Token） | 智能分流偏好 |
| 原始配置字节，保留原始语义 | VPN 配置、连接状态与系统权限 |
| 原配置需要的 provider / Geo 依赖原始字节 | 证书风险确认、已验证标记、启动成功标记 |
| 版本身份与删除标记 | 历史版本、回滚点、测速与流量历史 |

原始订阅中的规则、DNS 与分组仍属于原始配置。只排除 Horizon 本机后来叠加的智能分流选项及其额外 Geo 依赖。云端恢复不请求订阅站或 provider URL。

新订阅通过本机兼容校验与内核离线预检后加入列表，不自动选中。非当前订阅可自动更新／删除；当前订阅的更新／删除需要在同步页处理。应用当前版本前要求 VPN 未运行，不会为同步自动断开或重连。更新保留本机上一版本与可用回退点。若新版无法恢复或预检失败，原版本继续保留。

## 存储及安全

- 容器：`iCloud.Kenote.Clash`，只使用 `privateCloudDatabase`，自定义 zone `PersonalSubscriptionsV1`。
- `HorizonSubscriptionV1.payload` 使用 `encryptedValues` 保存版本化元数据；原配置和依赖采用按 SHA-256 寻址的 `HorizonAssetV1.file`。`digest`、`bytes` 也使用加密字段。CKAsset 由 CloudKit 加密。
- 不使用公共数据库、公开转换服务、共享链接或第三方账号。不会把敏感原文／URL 写入诊断日志。
- 本机订阅仍在 `AfterFirstUnlockThisDeviceOnly`、`synchronizable=false` 的 Keychain 中。同步账本独立保存到同一受保护存储，不改变原订阅存储方式。
- 云端暂存文件采用系统文件保护，目录排除系统备份；路径仅由验证过的摘要生成。恢复逐项检查大小、摘要、资源键集合、配置结构与原生内核结果。
- 原配置 ≤1 MiB；依赖最多 35 项、单项 ≤32 MiB、总计 ≤64 MiB，沿用导入限制。云端元数据 ≤64 KiB，同步账本 ≤16 MiB。
- Debug 使用 Development，Release 使用 Production。账户绑定、同步游标与暂存目录也按环境隔离，不能混用调试与 TestFlight 的同步状态。

CloudKit 加密说明依据 [Apple 文档](https://developer.apple.com/documentation/cloudkit/encrypting-user-data)。不宣称所有 iCloud 账户均具有高级数据保护的端到端加密保障。

## 一致性与失败处理

1. 本机增删改与随机 UUID 变更代次一起提交到订阅索引，离线或同步关闭时同样记录。索引提交是本机生效点。
2. `CKSyncEngine` 的游标、服务器 change tag、待发版本、待处理版本与删除标记持久保存。依赖先确认上传，再发布引用它们的订阅记录。
3. 通过上次共同版本进行三方合并。名称与内容等不重叠改动可合并；相同字段冲突等待用户选择，不以设备时间决定赢家。
4. 收到服务器新版后，旧待发内容被阻止上传，直到完成合并。重复投递同一冲突不会自动解除冲突。
5. 冲突页提供应用云端、保留本机、保留两份。保留被远端删除的本机内容时创建新云端身份，原 tombstone 继续存在，避免离线设备使旧身份复活。
6. 本机应用前重新核对变更代次、当前订阅身份和本地版本／节点选择。提交直接返回所提交的代次，避免把提交后的其他本机编辑误认为已同步。
7. 同步关闭不删除本机或云端内容。账户变化暂停同步；必须明确确认，才将本机保留的内容合并到新账户。旧账户账本不能复用到新账户。
8. 未知 schema 的记录被隔离、保留并阻止同 ID 上传；单份损坏或暂不支持的订阅不应阻塞其余正常订阅。网络失败保留队列并退避，支持手动重试。
9. 服务器物理删除记录／zone 与普通用户 tombstone 不等价。前者暂停并报告配置问题，不擅自重建旧 zone 或清空本机资料。

网络工作在 actor 中，校验、资源复制和 Keychain 读写通过已有配置 worker 执行。前台每三秒只检查本机索引代次；没有变更时不重新解析所有订阅或收集资源。首次介绍未完成、离线或同步关闭时不建立新的 CloudKit 会话。

## CloudKit schema

可审阅定义：[`Configuration/CloudKit-schema.ckdb`](../Configuration/CloudKit-schema.ckdb)。只包含结构，没有个人订阅、测试记录或凭据。

| Record Type | 字段 | CloudKit 类型 |
| --- | --- | --- |
| HorizonSubscriptionV1 | payload | Encrypted Bytes |
| HorizonAssetV1 | digest | Encrypted String |
| HorizonAssetV1 | bytes | Encrypted Int64 |
| HorizonAssetV1 | file | Asset（系统加密） |

加密字段不能建索引；客户端使用 zone 增量同步及精确 record ID，未使用明文名称查询。两个 Horizon 类型不给 `_world` 读取权限；内置 `Users` 类型保持从该容器导出的原始定义。

2026-10-09 已确认该容器存在、开发者 Console 可登录；但 Console 的 New Record Type 与 Import Schema 校验均返回 `Internal error`。换用 Safari 并重新登录后，新建类型仍失败，容器权限和数据库列表也无法读取。Safari Web Inspector 中数据库请求返回 `503`，响应为 `message: retry-needed`、`reason: Internal error`，请求 ID 为 `f144374f-fcfb-4c46-a511-76dab7e9d714`。这定位到 CloudKit 服务端请求处理失败，但不足以判断是平台整体故障还是该账户／容器的后端状态问题；不能仅凭这些现象推断 schema 定义错误。

上述错误为当日早先的历史记录，截图保存在本机 `build/icloud-console-schema-error.jpg` 和 `build/icloud-safari-503.jpg`（不纳入 Git）。23:03 后 Safari 中服务恢复，重新读取现有类型、导出并保留 `Users` 定义后，合并 schema 通过 Validation Passed，Development 导入成功。再次从服务器导出的结构与本地定义一致，两个 Horizon 类型的加密字段及权限正确，`Users` 未变更。备份为 `build/icloud-development-before-fields.ckdb`、`build/icloud-development-verified.ckdb`；界面记录为 `build/icloud-development-schema-ready.jpg`。

**Development 结构已建立，开发侧上传／恢复检查与用户两端实机订阅同步验证均通过；Production schema 已部署，尚待发布版实际同步验收。** Console 导入会替换整个开发环境结构，后续导入前必须重新导出现状并合并全部已有类型，不能盲目用本文件覆盖新增的其他类型。

2026-10-10，经用户明确确认「部署到 Production」后，审阅并提交 Deploy Schema Changes。差异仅新增 `HorizonAssetV1`、`HorizonSubscriptionV1`，`_icloud` 获得这两个类型的创建权限，`_creator` 获得自己的记录读写权限；没有新增索引或公开读取权限，`Users` 未变。Console 显示 Changes Deployed / The schema is deployed to Production。随后从 Production 重新导出并比较，三个类型的字段与权限均与本地及已验证 Development 定义一致，`payload` 为 Encrypted Bytes。正式库导出备份为 `build/icloud-production-verified.ckdb`，截图为 `build/icloud-production-deployed.jpg`、`build/icloud-production-schema-verified.jpg`。本次没有迁移开发记录、修改设备网络或上传 App。

下一步通过 TestFlight／正式签名验证 Production 实际同步。不能把 Debug 的成功或 schema 部署成功当作正式环境客户端读写成功。开发记录不会随 schema 自动迁移；正式版需从设备本机订阅重新同步。安装或更改 VPN 前仍须用户确认；开启实际订阅同步前明确说明上传范围。不要 Reset Environment，不改其他容器权限。

也可以在本机设置 CloudKit 管理凭据后使用 Apple `cktool validate-schema` / `import-schema`。Token 只留在本机 Keychain，不放到源码、命令行参数、日志或聊天。当前本机未配置 cktool 管理 Token。参考 [Apple cktool 文档](https://developer.apple.com/icloud/ck-tool/)。

## 验证记录

- 16 项自动化测试通过：离线队列重载、三方合并、重复冲突保护、服务器变更与未知 schema 的上传阻断、同名区别与完整重复识别、原子增删改、并发写入、当前订阅保护、完整 provider 离线恢复、分片完整性、本机分流／节点选择保留、失效选择提交拒绝、默认关闭，以及既有版本维护／证书确认／导入呈现回归。
- iOS Release 真机签名构建与现有包检查通过；成品包含正确的容器、CloudKit 权限和 Production 环境。使用现有开发签名，未生成 App Store 分发包或上传。
- iOS Debug 真机签名构建与现有包检查通过，签名权限确认使用 Development 环境，对应本轮已建立的开发 schema。
- 用户明确授权后，Debug 版已安装至同一 iCloud 的 iPhone 16 Pro 与 iPad Pro（2021），允许实际同步个人订阅及来源／凭据／依赖。按授权断开 Horizon VPN，测试未连接 VPN。
- 真实 Development 上传与恢复各 1 项检查通过：iPhone 发布虚构订阅，iPad 恢复同一云端身份；原配置、虚构来源 URL、provider 依赖字节一致，`payload` 使用加密字段，当前订阅／内容／节点选择／证书同意未改变，两次报告均 `ready`、0 阻塞项、0 待处理项。记录见 `build/icloud-device-publish-report.json`、`build/icloud-device-receive-report.json` 及对应 xcresult。
- 用户接手后续交互验证，因此开发侧未继续自动改名、删除或冲突步骤。交接时测试订阅 `HORIZON Sync Check B6CCF9BC` 保留在两端，正常同步开关仍关闭，供用户从设置入口开启。
- 2026-10-10 用户明确反馈「实机验证通过，两边确实能正确同步订阅」，确认两端正常订阅同步可用。没有逐项报告离线冲突、配额不足、换账户等异常场景，不将这次反馈扩大为所有边界场景均经真机验证。
- 2026-10-10 Production schema 部署及导出比对通过。尚未生成／上传本轮 App Store 分发包，也未使用发布构建完成正式环境客户端读写验收。

自动化测试使用内存存储、虚构域名与本机暂存，不访问订阅 URL。构建／日志保留在 `build/icloud-sync-tests.log`、`build/icloud-sync-release.log`、`build/icloud-sync-debug-device.log`。

`CloudSubscriptionDeviceTests` 是另外的手动真机集成检查，默认跳过；只有显式传入 `HORIZON_CLOUD_DEVICE_CHECK=AUTHORIZED`、运行 UUID 与阶段参数才使用实际 Keychain 和 Development CloudKit，需要先取得上传本机订阅的授权。它不访问订阅来源站，测试变更只针对带本轮唯一标识的虚构条目。正常 UI 同步必须关闭以避免两个引擎并发运行；各阶段分别启动进程以覆盖账本恢复。已执行 `publish`、`receive`，未执行 `rename`、`receive-rename`、`delete`、`receive-delete`。

## 两设备验收清单

### 2026-10-10 iPad TestFlight 33 启动崩溃修复

iPad 的多份 TestFlight 33 崩溃报告和原包独立启动日志一致：CloudKit 在 `cancelOperations()` 中触发 `BUG IN CLIENT OF CLOUDKIT` 断言。delegate 内创建的普通 `Task` 继承了回调的 TaskLocal 上下文，不能在这个上下文中调用可能再次触发 delegate 的引擎操作。两处回调取消路径改为通过独立任务调用，`stop()` 等普通入口不变；测试验证上下文隔离和父任务取消情况下仍能停止引擎。

首次修复版在 iPad 不再崩溃，但日志显示已有资源上传冲突导致同步暂停。CloudKit 的 `serverRecordChanged` 响应不下载附件，`CKAsset.fileURL` 为 nil（[Apple 文档](https://developer.apple.com/documentation/cloudkit/ckasset/fileurl)）。已有不可变资源的冲突现在校验 record type、zone、摘要身份、合法大小及本机缓存的实际摘要后确认，不再尝试从冲突响应导入附件；普通接收仍要求下载附件并验证大小和摘要。新增测试覆盖无附件响应、缓存缺失／损坏、身份和大小异常。未重置云库、删除本机订阅或修改 Production schema。

完整修复通过 Release 签名构建和 25 项测试（4 个 suite）。经授权保留数据安装至 iPad，第一次启动正常处理原有资源冲突，没有再次暂停或崩溃；再次独立冷启动未出现这些错误。用户随后在实机确认可以正常同步、状态显示正常，结束时未启动 Horizon VPN。该包为使用 Production CloudKit 权限的开发签名 Release，尚未重新上传 TestFlight；不能将此次结果表述为新的 TestFlight 分发包已验收。原版日志、修复版两次启动日志、构建与测试记录在 `build/cloud-crash-*`，含系统产生的记录标识，不纳入 Git 或公开报告。

- 开启前无 CloudKit 同步；intro 结束后仍需用户主动开启。
- A 导入、B 恢复：字节和全部依赖相同，B 不自动选择或连接；来源 URL 可用于随后手动刷新。
- A 改名／更新：B 非当前订阅自动接收；B 当前订阅保持原版，待处理入口出现。
- A／B 离线同时改内容、同时改名、删除与编辑相撞：恢复网络后两份内容均可选择，重启和重复投递不丢失冲突。
- A 删除：B 非当前副本删除、当前副本等待确认；B 离线回来不复活旧身份。
- 中途退出 App、下载缺片、摘要不符、预检失败、Keychain 写入失败：本机原版可读，队列可恢复。
- 同步关闭／退出 iCloud：本机继续使用；换账户不自动上传，明确合并后才开始。
- iCloud 空间满、未登录、网络超时：状态准确、可重试，不破坏本机记录。
- 确认节点选择、智能分流、证书同意、历史、Ping 和流量没有跨设备跟随。

## 当前限制与回滚

### Configurations 中的待处理提醒

订阅列表（iPhone）和订阅矩阵（iPad）可见且没有导入、详情、批量选择、切换／删除确认、错误提示或兼容性说明弹窗时，发现未提示过的待处理版本后展示原生简短 Alert。初次入场、VPN 设置、证书确认以及 iPad 拖入文件过程中不展示；等当前操作及页面切换稳定约 0.65 秒后再提示，不插入列表行、不改变工具栏尺寸。

「稍后」保留原来的 Needs review 入口；「去查看」先等待原生 Alert 收起，再通过原有 NavigationStack 导航。单一且仍有效的版本直达 Review，多项或版本已经改变时进入实时待处理列表；全部已处理则不跳转。本机 UserDefaults 仅保存订阅 UUID／版本 UUID 的提示历史，按 Development／Production 隔离，同一仍待处理版本在页面切换或进程重启后不重复主动提示。提示确认不应用订阅、不解决冲突、不启动或断开 VPN，也不改变 CloudKit 同步逻辑。

2026-10-10：Release 构建和 42 项测试（8 个 suite）通过，包含提示历史持久化、原因变化不重复提醒、新版本再次提醒、批次确认不误标记新版本、单项／多项导航和失效版本保护。尚未安装本轮改动到真机；原生弹窗与导航的视觉连续性待用户实机确认。

本机新增、改名、更新／回滚和删除订阅在成功提交后触发主动同步，连续修改合并约 0.5 秒；正在同步时的新修改保留为后续一次请求。云端恢复和设备本地节点选择不触发这类通知。回到前台并满足原有联网条件后，主动拉取并发送一次；首次介绍和同步关闭期间不启动。同步页面的布局、状态种类与图标反馈不变。

同步时机由系统、网络和 iCloud 条件决定，不保证秒级／后台持续同步。应用被系统挂起后，接收内容可能要等下次前台恢复才进入本机列表。

第一版保留删除 tombstone 和不可变云端资源，**尚未自动清理不再引用的云端资源**。这避免过早回收影响离线冲突恢复，但长期频繁更新会增加 iCloud 占用；后续需要单独设计安全的资源回收与云端清除入口。当前没有“清空整个 iCloud”按钮。

改动前基线：`3ec31a5b6eb56671b75940b238315500dbca4444`（TestFlight 32），本机记录 `build/rollback/before-icloud-sync/commit.txt`。回滚前先关闭同步，再只回退本轮代码／权限改动；不要卸载 App、删除 Keychain 或重置 CloudKit zone。本机新增索引字段为可选，旧版仍能读取订阅；旧版运行期间不会记录本轮新增代次，重新启用新版后应人工复核离线编辑，不能把回滚当作持续同步路径。
