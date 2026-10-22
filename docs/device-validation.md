# 签名与安装

打开 `Horizon.xcodeproj`，选择 `Horizon` scheme。使用有权访问相应 App ID 的开发团队；主 App、Packet Tunnel 与 Widget 的签名、版本和能力必须匹配。

## 必需配置

- 当前主 App Bundle ID 为 `Kenote.Clash`。延续已有安装时需保留 Bundle ID、钥匙串访问组和存储身份；不要仅为产品改名卸载 App。
- Packet Tunnel 需要 Network Extension entitlement 和覆盖目标设备的签名。
- 系统控件使用 App Group `group.Kenote.Clash.widgets`；同步使用 iCloud 容器 `iCloud.Kenote.Clash`。自行更换身份时需配置对应能力，不能直接复用他人容器。
- SDK 按[构建说明](core-build.md)生成，签名材料不纳入仓库。

## 安装与验收

1. 手机解锁、信任电脑并开启 Developer Mode，在 Xcode 选择目标设备。
2. 构建并安装 App，先确认正常启动和离线配置校验。
3. 由使用者明确允许添加 VPN 配置，再执行连接测试。
4. 运行包结构检查，并核对实际签名 entitlement、profile 有效性和设备覆盖范围。
5. 按[稳定性清单](stability-validation.md)验证出口、DNS、断开恢复及后台行为。

编译、签名、安装、扩展启动和代理联网分别验证。证书或 profile 过期后需重新签名；分发构建使用其对应的账号权限和签名方式。

回退前保留源码标签、可重装归档和原始配置。新版索引或资源快照不保证旧 App 可读；降级前先在新版中处理配置，不能以卸载 App 作为清理或恢复方案。
