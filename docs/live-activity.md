# 灵动岛与 Live Activity

设置中控制启用。compact／minimal 显示地球图标；展开和锁屏卡片显示连接状态、节点名称及手动 Ping。名称遵循隐私显示设置。

Ping 使用后台 LiveActivityIntent，不自动连接 VPN；服务与扩展共同验证会话和目标，切换后清空旧结果。重复点击合并，运行超时后可重试。结果是上次手动测试值，不持续更新速率。

活动只携带显示名、会话、目标摘要、状态和测试时间等必要字段，不包含配置或来源凭据。系统挂起、外部断开或自动组选路可能造成显示滞后，操作前重新核对实际状态。

## 实现约束

布局位于 `LiveActivityExtension/`，生命周期协调与测试服务位于 `Horizon/Services/`。主 App 与 Widget 均需正确的后台 Intent 元数据。

按钮使用固定点击区域和局部反馈，数字使用 NumericText。减少动态效果及低亮常亮显示时简化动画；不要给背景重新加入曾导致点击路由异常的 invalidatableContent(false)。

## 验证

LiveActivityTests 和 ProbeExperienceTests 覆盖数据、会话、超时与请求隔离；`scripts/check-bundle.py` 检查嵌入关系及 Intent 元数据。真机需检查展开点击不意外切前台、实际 Ping、节点切换、长时间后台和按钮观感。
