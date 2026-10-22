# 灵动岛 / Live Activity

当前版本显示连接时的节点名称，并提供用户手动发起的 Ping；不再展示或持续采样上下行速率。

- compact / minimal 仅显示 `globe.europe.africa`；展开与锁屏卡片显示 HORIZON、连接状态、节点名与 Ping 按钮，保留原安全留白。
- 名称跟随 App 的原名／隐私设置，最长 160 字符，单行截断。活动载荷仅包含显示名、会话 UUID、不可逆目标摘要、状态、测试结果及时间；不包含来源 URL、密码或完整配置。
- 前台协调器查询真实隧道状态和选中节点，仅在显示内容变化时更新；节点或订阅切换会清空旧 Ping 结果。隐私设置变化同步更新名称。后台不运行持续刷新计时器。
- `PingCurrentNodeIntent` 同时编入主 App 与 Widget，采用 `LiveActivityIntent`，`openAppWhenRun=false`。系统触发 App 进程中的 `LiveActivityPingService`；不依赖页面实例、不创建 VPN、不自动重连、不加载订阅或请求新的权限。
- 服务检查已有隧道，测试前后读取 telemetry 校验会话和目标摘要。新增 `activity-node-ping.v1` IPC 在扩展生命周期队列再次验证目标，沿用 App 的核心 URL 测试目标和超时。与 App / 批测共用扩展的互斥状态。
- 连续点击由服务合并；成功显示 ms，失败、超时、忙碌、不可用有独立文字。测试开始后 15 秒 staleDate 允许重试，避免活动被系统挂起后一直显示加载。显示的 ms 是上次手动测试值，不承诺持续更新。
- 若后台自动策略变化导致目标与卡片不一致，拒绝测试旧目标并提示打开 App 更新。主 App 挂起期间系统外部断开／自动策略变化仍可能使连接状态和名称暂时滞后，不能将活动当作后台实时连接监测器。
- 原失败的 Network Extension ActivityKit 活动枚举、速率采样与后台接力代码已移除。

## 构建与测试

主 scheme `Clash` 嵌入 `HorizonLiveActivity` WidgetKit 扩展。主 App 与 Widget 均有 `PingCurrentNodeIntent` 元数据；Widget 使用 `HORIZON_WIDGET` 条件编译，只保留系统入口声明，真正操作在主 App 进程执行。

2026-10-04：签名 iPhone 与模拟器构建通过，包结构检查通过，10 项 LiveActivityTests / ProbeExperienceTests 通过。覆盖目标摘要稳定性／切换隔离、IPC 载荷、旧活动兼容解码、加载超时重试、速率字段移除以及原节点测试回归。

DEBUG 模拟器可通过 `CLASH_ACTIVITY_PREVIEW=1` 展示离线活动；按钮走同一个系统 Intent 入口，使用本地计数代替网络请求。此入口在真机不生效，不能作为真机网络验收证据。

已安装至 iPhone 16 Pro 并恢复原订阅连接；手机主屏确认 compact 只显示地球图标。真机验收待补充：展开岛内点击 Ping，App 不切至前台并显示真实结果；订阅／节点切换后名称更新与结果清空；后台长时间后点击仍能执行。视觉过渡由用户体验确认。

参考：[Apple Live Activity 交互](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)、[ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)。

## 点击与导入过渡修正（2026-10-04）

compact 地球显式采用 20 pt 字体与 24 pt 容器。Ping 文字保留最小内容宽度，加载时不切换 disabled 外观（重复任务由服务合并），仅为结果行添加响应减少动态效果的局部动画。导入确认保存时保留预览直至 sheet 关闭；业务忙碌不再被页面视为 VPN 连接状态变化。确认页图标和工具栏显式使用主题色，Toggle 仍使用系统绿色。签名构建、包检查与 6 项相关测试通过；已安装至用户 iPhone，Ping 与保存页面的实际视觉过渡待用户确认。

后续按用户反馈：Ping 使用独立 `VPNActivityPingButton`，112×44 pt 固定占位，静态胶囊背景位于 Button 外部，自定义 ButtonStyle 不读取 isPressed；只有文字内容做过渡。移除结果行的整体动画，避免牵动节点名。签名构建与包检查通过，已安装至用户 iPhone；静态背景的实际点击观感待用户确认。

导入确认补充修复：原 URL 的 isPresented 变为 false、预览尚未清理时，第二个基于预览的 sheet 可能重新弹出。现以单一 ImportSheet 路由区分 link / file；文件预览只由文件读取成功事件触发，取消和成功都等外层 onDismiss 清理数据。签名构建、包检查及导入保存回归测试通过，真机关闭过程待用户确认。

用户已反馈导入弹窗修复测试正常。后续 Ping 反馈调整为仅文字按压淡化（0.18 秒），结果保留 NumericText；只有文字标记 invalidatableContent，静态背景显式关闭更新动画与等待反馈，继续维持 112×44 pt 占位。minimal 与 compact 共用 20 pt regular、24×24 pt 的白色 monochrome globe.europe.africa；compact 单独保留外侧留白。签名构建与包检查通过，本轮尚未安装，真实系统按压观感待用户确认。

最新交互调整：用户希望背景恢复适度颜色反馈。Ping 样式现仅将胶囊白色透明度从 0.12 过渡至按压时的 0.22，采用 0.22 秒 easeInOut，松开恢复；文字反馈与 NumericText 保留。112×44 pt 占位不变，无缩放、位移或尺寸动画，响应减少动态效果。已通过签名构建及包检查，尚未安装，点击观感待真机确认。

用户随后反馈点击 Ping 文字中央会打开 App。核对修改前构建产物：主 App / Widget 的 openAppWhenRun 均为 false，supportedModes 均为 1；通过当前 SDK 确认 1 是 background，故没有证据将其归因于前台 Intent 配置。为排除自定义按钮渲染影响，改为原生 plain Intent Button，将 112×44 pt 尺寸、胶囊背景与点击形状全部放入 label；背景在测试中轻微提亮、结束恢复，保留 NumericText。显式声明 supportedModes.background，并添加不含会话、节点或凭据的 Intent 入口日志，供后续区分命中按钮与默认打开 App 行为。包检查新增主 App 和 Widget 的后台执行元数据断言。签名构建及四项包检查通过；尚未安装，不能据此认定跳转问题已解决，需重新创建活动后真机复测。

## 点击路由定位（2026-10-05）

用户确认重新安装并新建活动后仍会打开 App。在 iOS 26.5 模拟器锁屏 Live Activity 上做 A/B：同一活动中裸系统 Intent Button 能进入后台处理，原 Ping 点击打开 App。去掉辅助标签、contentShape 或仅改 bordered 样式均未解决。移除背景的 `invalidatableContent(false)` 后，恢复 plain 样式、文字 invalidatableContent、NumericText、原尺寸、contentShape 和辅助标签，按钮中央及背景边缘都进入主 App 的 Intent 日志且保持锁屏。最终保留该最小删除；背景仍由真实 testing 状态驱动 0.12 → 0.22 明暗过渡，不缩放或移动。临时 A/B 按钮和签名设置实验已移除。

模拟器测试使用现有开发签名的本地副本：默认 adhoc 构建曾被 linkd 以缺少 Team ID 拒绝注册，不能拿该环境的失败推断真机问题。没有创建证书或修改手机网络。最终 iPhone 签名构建、四项包检查和 diff 检查通过。

验证边界：已确认后台入口收到有效会话并找到演示活动；模拟器卡片未观察到离线计数刷新，因此不宣称结果展示链路或真实测速通过。本轮没有安装到手机。展开灵动岛的真机点击、不切到前台并完成实际 Ping，以及文字／背景过渡仍由用户复测。

## 背景点击反馈（2026-10-05）

用户反馈背景没有可见过渡。检查发现上一版 plain 按钮只按远端 `probe == running` 改变填充色，没有读取按下状态，点击本身无法触发自定义背景反馈。改为局部 `PingFeedbackStyle`：`isPressed || testing` 控制恒定白色胶囊视图的 opacity（0.12 / 0.22），采用 0.3 秒 easeInOut。反馈只作用于背景，不缩放、位移或改变文字占位；NumericText 保留。减少动态效果或低亮常亮显示关闭背景动画。不重新加入造成点击异常的 invalidatableContent(false)。

iPhone 签名构建、模拟器构建及四项包检查通过。签名模拟器锁屏卡片点击后保持锁屏，日志确认进入 host Intent 并匹配演示会话；后台路由未回归。未安装真机，视觉渐变与真实测速仍待用户确认，未宣称已从截图验证完整动画。参考 Apple [Live Activity 动画文档](https://developer.apple.com/documentation/widgetkit/animating-data-updates-in-widgets-and-live-activities)。
