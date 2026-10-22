# iCloud 订阅同步

设置中可选开启，默认关闭。使用个人 CloudKit 私有库，不依赖 Horizon 账号。开启前会说明上传范围，包括来源链接、订阅令牌、节点凭据、原始配置和所需依赖。

## 同步范围

同步名称、文件名、原始配置、来源、provider／Geo 依赖、版本身份和删除标记。当前订阅、节点选择、智能分流、VPN 状态、证书授权、历史回滚点和测速／流量记录各设备独立。

收到的新订阅先做本机校验和内核预检，不自动选中。非当前订阅可更新或删除；当前订阅的变更进入待处理列表，应用前要求 VPN 停止，不为同步自动重连。云端恢复不请求订阅来源站。

## 一致性与安全

- 容器 `iCloud.Kenote.Clash`，privateCloudDatabase，zone 为 `PersonalSubscriptionsV1`。
- schema 见 [`CloudKit-schema.ckdb`](../Configuration/CloudKit-schema.ckdb)：订阅 payload、资源 digest／bytes 使用加密字段，附件为 CKAsset。不设置公开读取权限。
- 本机提交记录变更代次，依赖先上传；CKSyncEngine 保存游标、change tag、队列和删除标记。
- 基于共同版本做三方合并；冲突可选云端、本机或两份，不按设备时间决定赢家。
- 账户改变时暂停，明确确认后才合并到新账户。未知 schema、zone 被物理删除或记录不完整时保留本机内容并报告，不盲目覆盖服务器。
- 关闭同步不删除数据；未引用云端资源和 tombstone 暂不自动回收，没有清空整个 iCloud 的入口。

本机修改合并触发同步，恢复前台时主动拉取；后台时机由系统、网络和 iCloud 决定。离线、失败或挂起时保留队列，不保证秒级同步。

## Schema 与验证

Development 和 Production 结构已部署，开发环境的两端实机订阅同步已有用户确认。发布构建的 Production 同步、离线冲突、换账户和配额边界仍需分别验收。

更改 schema 前导出现有结构并合并全部类型；部署结构不会迁移 Development 记录，不能 Reset Environment 代替修复。管理令牌只在本机保存。

自动化入口为 HorizonTests 中的 CloudSubscriptionSyncTests、提示导航及相关存储测试。CloudSubscriptionDeviceTests 默认跳过；它会访问实际 Keychain 和 Development CloudKit，需显式授权和专用运行参数，正常 UI 同步应先关闭。
