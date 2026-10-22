# 系统连接控件

主屏幕可添加 HORIZON VPN 小组件，控制中心可添加对应控制项。系统决定展示位置和刷新时机。

SetVPNConnectionIntent 接收明确的连接／断开目标，复用主 App 的校验、证书授权和恢复流程。需要设备认证；缺少配置或同意时转入 App，不自动批准权限。断开只处理本应用的 VPN。

App、Packet Tunnel 和 Widget 的签名需包含 App Group `group.Kenote.Clash.widgets`。共享展示数据仅含状态、订阅显示名与时间戳，不含来源和凭据。

显示可能因系统调度或扩展异常终止而过期；每次操作重新核对系统状态。成功连接协调 Live Activity，确认断开后结束活动，仍受系统授权和用户设置约束。

真机验收：后台／App 未运行时连接与断开、锁屏认证、缺少配置、未授权证书、另一 VPN 占用和状态延迟。代码入口为 ConnectionWidgetState、连接 Intent 及服务；自动化覆盖状态与配置激活边界。
