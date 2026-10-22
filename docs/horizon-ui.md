# 构建 23：越界界面

2026-10-02。此记录区分模拟器视觉预览、签名构建和真机验收；构建 23 已通过签名构建及主 App/扩展包检查，地理资源、许可声明和 Metal 库均已核验打包；尚未安装真机。

## 风格与布局

默认「越界」：纯黑背景、白色线条、独立 Metal 3D 场景。设置 → 界面风格 →「经典」可恢复原首页、原有配色与保存的深浅色偏好。切换只写 UI 偏好，不切换订阅、不操作 VPN，不创建新的采样任务。

首页保留三个 Tab，场景占主要空间，下方渐变衔接当前订阅、Ping、实时双线曲线和累计流量。信息区可滚动查看，也可点击场景底部箭头展开。小型 Liquid Glass 连接按钮与顶部下拉共用确认流程；没有配置或控制器尚未就绪时不能连接。顶部下拉由 ScrollView 的手指交互进度驱动同一条运镜路径，墙面固定在视口；有效下拉距离达到场景高度的 18% 时，镜头进度到达越墙点（0.54），在松手前触发连接流程。未越墙松手则平滑退回；惯性滚动、普通上滑或从信息区开始的滚动不触发连接。

设置 → 外观 →「砖块大小」提供 1×–3× 滑杆（0.1× 步进），默认 1.5×，1× 为最小砖，3× 恢复最初大砖尺寸。偏好持久保存；只重新生成墙体网格，不重启场景动效或采样任务，墙体高度、减薄后的厚度及镜头保持固定。

「地球大小」范围 1×–2×，默认 1.2×；1× 保留最初球体大小。放大时球心轻微下降；实际投影超出视口宽度后，按溢出量逐渐增加下沉，镜头不后退、不自动缩放，左右自然裁切，下部由前景墙遮挡。1.5× 以上平滑加强下沉，到 2× 时球体投影轮廓的中线基本与墙沿对齐，主要露出上半球；默认 1.2× 构图保持不变。砖缝后补不透明遮挡面，避免被挡的粒子漏光。触摸射线与渲染共用考虑视口比例的球心/半径，墙面不接收地球旋转手势。新默认值只用于未保存或无效偏好，已有手动尺寸继续保留。

标题独立在 `Components/HorizonTitleView.swift`：地球投影超出屏幕后，CLASH 与状态文字按下沉幅度向下移动；字号最多分别增加 8% / 14%，状态约从 28 pt 增至 32 pt。按真实球体投影上缘和固定字体行高留出 24 pt 间距。状态文字由独立的 `HorizonStatusText` 使用原生 `.numericText(value: transitionIndex)`；状态变化时在同一个显式 `withAnimation` 事务更新显示文字和单调递增的过渡序号，序号只决定原生过渡方向、不显示在界面。内容动画为 0.65 秒，不再只把 contentTransition 修饰器放入动画闭包。原生 NumericText 主要针对数字，英文/中文词的具体字形过渡由 SwiftUI 决定，不承诺每个字符都滚动；模拟器录像逐帧已观察到英文状态字形的中间过渡。；标题位移与缩放跟随 Metal 渲染器发布的实际 formation 进度，标题先将进度映射为 p^1.4，再应用五次缓动，让入场初段位移更小、起步更缓，起步和收尾速度、加速度趋于零；不再单独用 0.65 秒提前到位。只改变文字的进度映射，地球汇聚、下沉和相机曲线保持原样。进度只由标题订阅，不刷新整个首页，也不在自转稳定阶段持续发布。保留同一个标题容器和固定行高，状态 Text 的 identity 保持不变，让 SwiftUI 比较新旧内容，不在动画中测量高度或重新设定位置目标；中途断开/恢复时跟随当前场景进度。响应动态字体和减少动态效果（后者直接采用场景最终姿态，状态词仅短暂淡化）。未连接或未溢出时保留原位置。

## 状态与画面

- 未连接：保留原近景构图、墙体高度和摄像机距离，单砖宽高缩至原来的约三分之一，采用 18 行错缝砖。移除白色实心点缀，砖体厚度由 0.7 减至 0.5 场景单位（约减薄 29%）。黑色砖面和白色边线仍参与深度遮挡。
- 连接中：同一摄像机约 3.6 秒连续后撤、抬升；镜头与注视点的横向坐标始终为 0，取消中途侧移和随之产生的转向；墙沿仍留在画面下方。
- 等待连接：外部粒子保持漂浮；只有真实 NEVPNStatus.connected 才允许聚合。
- 已连接：镜头露出墙外空间时（视觉进度约 28%），同一批粒子便开始汇聚，不再等待镜头完全到位及额外停顿；连接尚未成功时仍保持漂浮。成形后缓慢自转，少量外围粒子持续漂浮。
- 稳定连接且地球成形后，可从地球表面开始任意方向拖动旋转；松手或手势取消后约 0.9 秒平滑回到未操作时的自转轨迹，重新抓取不会跳变。地球外保持页面滚动；后台、断开或恢复连接会清除临时偏移。减少动态效果时仍可手动旋转，松手直接归位。
- 恢复连接：粒子散开，保留墙外视角；失败或断开连续退回砖墙。
- 切 Tab、后台、场景离屏暂停渲染；返回时按真实状态展示。减少动态效果或关闭粒子动效时静态展示当前状态。

状态文字直接反映系统隧道状态，因此快速连接时可能先显示「已连接」，随后镜头才完成；不会为等待动画而延迟系统状态。

## 地理数据与重建

使用 Natural Earth 1:50m Land 数据，固定 ZIP 内版本 4.1.0，公共领域。来源、许可、ZIP SHA-256 和采样参数见 `Configuration/Geography/source.json`；声明随 App 打包。网站页面与实际 ZIP 的版本标识存在差异，以锁定 ZIP 内容为准。

执行 `python3 scripts/build-globe-points.py` 可完全离线重建球面目标。脚本核验源文件哈希、控制点海陆分类与单位球长度；输出 22,442 个陆地粒子，SHA-256 为 `d6c0ca8bab4011452efdda84db821dbaf2a4d96d84eba4c10dcc08cc5545da99`。另有 1,200 个稀疏球面点及 1,200 个外围点，合计 24,842。不是随机点球或联网地图；50m 数据经过采样，小岛与海岸细节有所取舍，不用于导航。

GPU 以缓冲区批量绘制，CPU 不为每个粒子建立 View。正常目标 60 fps；低电量或高温时降低目标帧率与粒子密度。当前数量是初始预算，尚无真机帧时间和功耗结论。

## 代码边界

- `Features/Horizon/HorizonHomeView.swift`：页面、滚动、确认与操作协调。
- `Components/HorizonInformationView.swift`：信息区。
- `Components/HorizonSceneView.swift`：MTKView 生命周期桥接。
- `Rendering/HorizonRenderer.swift`：Metal 管线、缓冲与帧调度。
- `Rendering/HorizonMotion.swift`：连续视觉状态。
- `Rendering/HorizonGlobeInteraction.swift`：用户旋转偏移与归位插值。
- `Components/HorizonMetalView.swift`：只允许地球区域接收触摸。
- `Rendering/HorizonGeometry.swift`：实体砖墙和摄像机。
- `Rendering/HorizonShaders.metal`：白色线条、漂浮和球面聚合。
- `Settings/InterfaceStyleSettingsView.swift`：独立风格设置页。

场景没有凭据、网络或内核逻辑。经典首页保留独立实现，共用原 TunnelController 和 RootTabView 持有的 TelemetryStore。

## 已验证与待验证

已通过：模拟器编译和 Metal 渲染；DEBUG 无网络的虚构状态预览（砖墙、漂浮、地球、失败回退）；真实地理控制点和重复生成哈希；延迟聚合、镜头中断连续性、恢复/失败、重入静态状态、封闭砖面与墙沿可见位置的自动检查；设置切回经典后的原布局及原深浅色偏好；箭头展开信息区。

提前汇聚、地球旋转偏移归一化、松手连续归位、归位中再次抓取和减少动态效果归位均通过数学/状态回归；新版 Metal 着色器通过模拟器和签名构建，预览可正常汇聚成形。模拟器自动化拖动未产生 UIPan 有效事件，因此不宣称实际触摸旋转已验收。触摸滑动、下拉连接和地球旋转与页面滚动的互斥仍需真机验收。还需真机验证实际连接成功后的场景、粒子密度与帧时间、连续启停、滚动手感、减少动态效果、后台返回及内存/耗电。用户负责主观运镜与动效观感反馈。没有改变内核和订阅兼容范围。

检查命令：

```sh
python3 scripts/build-globe-points.py
xcrun swiftc -parse-as-library -module-cache-path .build/bridge-check-module-cache \
  scripts/check-horizon-motion.swift \
  Clash/Features/Horizon/Rendering/HorizonMotion.swift \
  Clash/Features/Horizon/Rendering/HorizonGeometry.swift \
  Clash/Features/Horizon/Rendering/HorizonGlobeInteraction.swift \
  Clash/Features/Horizon/Rendering/HorizonPullState.swift -o .build/check-horizon-motion
.build/check-horizon-motion
```

标题动画诊断：仅 DEBUG 离线预览同时启用 `CLASH_HORIZON_PREVIEW=1` 和 `CLASH_HORIZON_SLOW_TEXT=1` 时，文字动画放慢到 3.25 秒并显示数字对照；普通启动保持 0.65 秒，不显示对照。

## 冷启动检查（2026-10-03）

使用 iPhone 17 Pro / iOS 26.5 模拟器 Debug 包，离线内存配置库，录制冷启动并逐帧对照；没有安装手机或改变真实 VPN。

- 修复前，系统浅色外观下启动页为白色，进入 Horizon 黑底时产生闪白。现通过 `UILaunchScreen.UIColorName=LaunchBackground` 使用黑色启动背景；App 内 Classic 浅色设置仍然有效，启动背景不随 App 内主题改变。
- 修复前，异步读取已有连接会先显示“正在同步”与砖墙，再播放整个连接运镜。`didFinishInitialRefresh` 现在区分首次读取和后续状态变化，首页只在首次读取结束后创建；读取失败也会结束等待并显示“无法读取状态”，诊断与设置仍可访问。等待超过 800 ms 才显示读取提示，没有人为最短等待。
- Horizon 标题的初始 formation 与初始 VPN 状态一致，避免首个 Metal 帧发布进度时标题从顶部跳到下沉位置。Classic 粒子的初始颜色也直接采用已读取状态，不再从未连接颜色过渡一次。
- 录像验证：Horizon 已连接、未连接、空配置；Classic 深色已连接；模拟读取失败。所测画面没有再次出现闪白、标题初始跳位或连接动画重播；底部 Tab 与按钮布局保持稳定。正常连接时的 NumericText、运镜和标题下沉逻辑仍保留。
- 限制：这些是离线状态注入，不是真机恢复 VPN 的测试；本轮没有验证真实扩展首批流量样本的数字变化，也没有覆盖 Classic 浅色冷启动及全部辅助功能字体尺寸。慢速读取提示已录到，但 Mac 随后锁定，未确认该次恢复后的最后一帧；不将此用例标为完整通过。

离线回归入口（仅 DEBUG 且使用内存 demo）：`CLASH_SUBSCRIPTIONS_DEMO=1` 加 `CLASH_STARTUP_AUDIT=connected|disconnected|empty|failure|slow`。其中 `slow` 延迟 1.2 秒，其他用例延迟 350 ms 以显露初始化过程；可选 `CLASH_STARTUP_STYLE=classic|horizon` 使用独立测试偏好域，不改日常 UI 偏好。生产构建不会读取这些诊断开关。

冷启动录像与逐帧拼图保存在 `.build/research/ui23/startup-audit/`（本地忽略目录）。启动背景使用 Apple 的 [UILaunchScreen.UIColorName](https://developer.apple.com/documentation/bundleresources/information-property-list/uilaunchscreen/uicolorname) 配置。

## 连接确认与交互运镜（2026-10-03）

- 两种首页共用独立的 `ConnectionConfirmationView`。默认保留确认；只有勾选“不再提示”并点“连接”后才保存偏好，取消或滑动关闭面板不保存。设置 → 连接 → 连接前确认可恢复，系统 VPN 权限提示不受影响。不会启用自动连接。
- 越墙后如仍需确认，镜头停在当前位置；确认后接续余下路径，取消则从当前姿态退回。每次下拉只提交一次；等待许可或连接失败不会伪造“已连接”地球。粒子成形仍由真实隧道状态驱动。
- 减少动态效果或关闭粒子动效时保持静态表现，下拉连接入口仍可用。切离首页或未提交的手势进入后台会取消进度。
- 已验证：模拟器确认面板、取消不保存、确认保存后跳过提示、设置重新开启；自动检查覆盖半程松手回退、越墙立即提交、重复提交抑制、确认期间停留、取消回退、连续接续、再次抓取及连接前不成形。
- 自动化拖动未观察到有效下拉结果，因此触摸跟手、越墙触发距离和滚动/地球旋转互斥仍待真机验证；未安装手机、未改变真实 VPN。

## 墙体边线深度冲突修复（2026-10-03）

- 原来在 `.line` 绘制前设置负深度偏移，但 Metal 的 `setDepthBias` 只对三角形有效，砖面与边线仍处于相同深度。
- 改为在绘制不透明砖面时使用正深度偏移（bias 1、slopeScale 1、clamp 0.00001），随后立即恢复零偏移，再绘制原有边线和粒子。保留深度测试与砖面深度写入；偏移设上限以限制掠射角下的遮挡误差。墙体几何、线宽、4× MSAA 和运镜不变。
- 模拟器构建通过；现有运镜、地球遮挡命中与手势状态检查通过。这些检查不证明 GPU 边线闪烁已消除，真机需对比连接/断开运镜及墙顶附近背面线条、粒子的遮挡。未安装真机或改变 VPN。
- 参考：[Apple setDepthBias](https://developer.apple.com/documentation/metal/mtlrendercommandencoder/setdepthbias(_:slopescale:clamp:))。若仍有细线明暗抖动，再评估三角形边线和解析抗锯齿。

## 移动时砖缝亮度闪烁：第二轮（2026-10-03）

用户确认现象为白色砖缝/边线忽明忽暗。第一轮深度偏移未解决，现已替换该方案：

- 墙体只绘制不透明三角形，不再叠加独立 `.line`，也不再偏移砖面深度。白边由每个四边形面的 UV 距离生成，黑面/白边共用同一个 fragment 和真实深度；不绘制三角形对角线，砂浆背板不带轮廓。
- 使用屏幕像素导数控制边线宽度，并在 MSAA 样本位置计算。亮度从几何边界向内平滑升高，再平滑衰减，避免“亮线在面边界突然截断”仍造成覆盖样本跳变。线条比原来柔和，墙体、厚度、相机路径、粒子和 4× MSAA 不变。
- 排查中确实发现：最初只将线搬进面着色器、单侧柔化仍会出现采样相位波动，因此最终采用两侧柔化，并保留可重复离屏回归。

验证使用本机 Mac Metal GPU、600×1000/4× MSAA、当前实际墙体几何和生产 shader；旧版基线为上一轮带砖面深度偏移的独立线段实现。砖块比例 1/1.5/3 各渲染 121 个运镜位置；另在固定 journey=0.6 时，以 1/32 像素步长平移一个像素，跟踪墙顶线段的峰值亮度。波动指标为 `(最大值−最小值)/平均值`：

| 砖块比例 | 旧版峰值波动 | 新版峰值波动 |
| --- | --- | --- |
| 1 | 66.4% | 30.4% |
| 1.5 | 65.5% | 28.2% |
| 3 | 65.9% | 29.9% |

这只说明受控亚像素位移下峰值波动减小，不代表整段运镜或所有像素的闪烁均消失。完整运镜中固定宽度的采样带还会纳入/移出墙顶另一条边，因此不能将该带的总能量相邻帧差当作纯闪烁指标；默认比例的亚像素总能量波动也并非全面优于旧版（约 7.7% vs 0.5%）。最终仍需真机观感确认。

遮挡回归在开始/中段/结束镜头后向墙内插入测试面，图像与未插入时逐字节一致；移除墙体后该测试面可见。模拟器、iOS 真机目标签名构建与原有运镜/手势/几何检查通过；真机构建仅有未使用 AppIntents 的元数据提取提示。未安装手机、未操作 VPN，未测量此版真机 GPU 耗时。

```sh
xcrun swiftc -parse-as-library -module-cache-path .build/bridge-check-module-cache \
  scripts/check-horizon-rendering.swift Clash/Features/Horizon/Rendering/HorizonGeometry.swift \
  -o .build/check-horizon-rendering
.build/check-horizon-rendering
```

需本机 Metal 访问权限，不联网。连续帧采样数据和对比图片输出至 `.build/research/wall-flicker/`。

## 重连时地球散开的过渡（2026-10-04）

重连时原有指数插值虽然位置连续，但起步速度最大，60 fps 下首帧就会散开约 4.1%；前后台恢复的 immediate 分支还会直接把 formation 设为当前状态终点。本轮仅给 recovering 及其恢复到 connected 的粒子形态采用临界阻尼插值（频率 2.8），由当前形态和速度连续推进。完整地球开始散开时缓慢起步；短时间反复断网／恢复保留已有速度，不重新生成粒子或替换模型。镜头保持墙外，原有普通连接／断开镜头与粒子插值保留。

同一渲染器从后台／其他 Tab 恢复时，重连及重连后的汇聚延续最后已绘制形态；真正冷启动或减少动态效果仍直接初始化到真实状态，避免虚构曾经连接。重连打断手动地球旋转时走已有 0.9 秒归位，不直接 reset 朝向。标题 NumericText 和按钮图标动画不变。

验证：check-horizon-motion 通过，新增覆盖 30／60／120 fps 的首帧位移、途中恢复、反复反转、前台恢复连续性、最终收敛、相机不回墙内、真正冷启动与减少动态效果；既有连接、断开、手势和墙体回归同时通过。模拟器构建通过，离线预览 Connected → Reconnecting → Connected 状态可切换。未更改真机网络、未启停真实 VPN；最终散开／汇聚节奏由用户真机体验确认。


## 移动端文案精简（2026-10-18）

本轮只调整 iPhone／iPad 页面文案和两处文本展示：去掉流量图的「实时流量」标题（保留量程菜单、曲线、上下行速率与累计值），将批量测速主界面的测试地址移入测速说明。缩短导入确认标题、设为当前订阅开关、识别成功提示、维护状态与 iCloud 等待／失败状态；精简链接导入和单节点测速说明，将策略组选择说明拆成短段落。订阅入口的英文统一使用 Subscription(s)，节点入口的「策略组与选择」缩为「策略组」。界面风格说明按用户要求保持原样。

保存不会连接 VPN 的提示移入导入说明；保留断开／重连确认、删除影响范围、证书与隐私提示。未改动任何服务、网络、存储、iCloud 调度、图表绘制或动画逻辑，也未改动 Mac 视图、Mac 工程或共享代码。

iOS Simulator Debug 构建通过，改动的中英文字面对照检查通过；所有本轮范围外源码、资源、工程文件指纹与基线一致。没有安装设备、启动真实 VPN 或执行云端操作。未进行小屏／大字体的实机排版验收。日志：build/mobile-copy-build.log；回滚快照：build/rollback/mobile-copy-20261018/restore.py（默认只核对，检测后续修改时拒绝覆盖）。


## 移除重复状态行（2026-10-18）

移除手机订阅列表的 VPN 状态行、iPad 订阅网格对应的状态文字、订阅详情的 Status 行，以及诊断页的 System status 行。列表仍显示当前订阅，卡片选择标识、切换进度、错误提示、连接操作与首页连接状态保留。清理仅供已移除 VPN 状态行使用的 showProgress 状态及 150 ms 展示任务；没有改动网络状态协调或操作流程。

iOS Simulator Debug 构建通过（build/mobile-subscription-status-build.log）；291 项本轮范围外源码／资源／工程指纹保持一致，Mac 和服务代码未改动。未安装设备或改变网络连接。回滚：build/rollback/mobile-subscription-status-20261018/restore.py，默认核对，检测后续修改时拒绝覆盖。


## 订阅详情去除无关提示（2026-10-18）

Rename 下方原先无条件显示全局 tunnel.message，可能呈现其他操作的系统／运行消息；已移除该常驻区块。文件来源不存在时不再显示「No local source filename is stored…」，仅在确有非空文件名时展示 Source file 行。链接／iCloud 导入没有本地文件名不作为错误提示。

进度移到订阅名称旁的固定 18×18 槽，局部淡入淡出并响应减少动态效果，不额外插入进度行。切换订阅或删除未成功时按需显示已清理并翻译的操作消息；重命名、刷新等独立页面仍使用各自的反馈。原有确认与服务调用保持不变。iOS Simulator Debug 构建通过；294 项范围外源码／资源／工程指纹保持一致。未执行实际订阅变更、VPN 或云端操作，未安装实机。日志：build/mobile-subscription-detail-copy-build.log；回滚：build/rollback/mobile-subscription-detail-copy-20261018/restore.py（默认核对，拒绝覆盖后续改动）。


## 移动端订阅切换状态动效（2026-10-18）

iPhone 列表与 iPad 网格共用的 SubscriptionRowView：当前订阅勾号采用 SF Symbols 原生出现／消失过渡；「当前／Current」文字实际随选中状态变化，使用 NumericText 内容过渡。隐藏模板分别保留图标与本地化文字宽度，避免切换导致订阅标题重新换行。切换中继续使用原生 ProgressView，完成后显示当前标记，避免标记与加载内容重叠；动画只作用于局部状态，响应减少动态效果。订阅名称仍保留原有透明度过渡。

未改动切换、确认、连接、存储或云同步逻辑，也未改动 Mac。iOS Simulator Debug 构建通过；294 项范围外源码／资源／工程指纹一致，diff 空白检查通过。未安装设备或改变网络，真机动效由用户体验确认。日志：build/mobile-subscription-status-motion-build.log；回滚：build/rollback/mobile-subscription-status-motion-20261018/restore.py（默认核对，拒绝覆盖后续修改）。


## 移动端订阅名称过渡与选择模式稳定性（2026-10-18）

Current subscription 的名称原先只有 Text.contentTransition(.opacity)，本轮改为同一局部 ZStack 内按最终显示名称标识的新旧 Text 交叉淡化，包含「未选择订阅」的状态变化。名称仍为淡化，不使用状态类 NumericText。

Select／Done 原先在全页 withAnimation 中增删底部 safeAreaInset，改变列表可用高度；同时清空选择会让底部计数先变成 0、按钮宽度变化，右上角文字长度也会改变原生工具栏尺寸。现在使用固定宽度的工具栏标签，选择状态仅驱动局部动画；底部操作常驻 overlay，以淡化和轻微位移显隐，不改变 viewport，保留随动态字体缩放的底部滚动留白。离开选择模式时保留隐藏选择计数，下一次进入前清空，避免退场中缩窄。不可见操作不参与点击或辅助功能。手机选择圈与详情按钮采用等宽槽位交换，保持订阅标题的可用宽度，避免换行引起行高变化。

iOS Simulator Debug 构建通过（build/mobile-subscription-selection-layout-build.log）。iPhone 17 Pro 模拟器使用现有内存示例验证 Select → 勾选 → Done → 切换示例订阅，操作与状态更新正常，稳定帧中的行位置、底部 Tab 栏和工具栏边界保持一致；最终动效节奏仍由用户真机确认。325 项范围外源码／资源／工程指纹一致，未修改 Mac、服务、连接或同步逻辑，未安装真机、启停真实 VPN 或访问云端。回滚：build/rollback/mobile-subscription-selection-layout-20261018/restore.py（默认核对，拒绝覆盖后续改动）。


## 移动端首页订阅菜单与节点列表（2026-10-18）

Horizon 与经典样式的 iPhone／iPad 首页新增两个公用功能组件：HomeSubscriptionMenu 将当前订阅名称作为原生 Menu，显示全部订阅并标记当前项，不跳转页面；HomeNodeListView 在流量图下以 LazyVStack 显示当前订阅全部节点，直接复用 NodeSelectionRowView 的编号、协议、选中与局部进度。沿用 Nodes 的原名显示设置；没有独立嵌套滚动区域，也没有向首页加入额外的节点测速按钮。

未连接时菜单调用原有 activateSubscription(..., reconnect: false)；有活动隧道时先显示与订阅页一致的切换重连确认，确认后才交给现有控制器执行。目标存在性、忙状态与当前选择均复查；失败按需提示。菜单标题单行截断并保留完整辅助功能名称，固定加载／下拉图标槽和至少 44 点点按高度，避免进度出现时挤动标签。节点切换沿用 catalog.directSelection 与带 expectedConfigurationID 的 selectMember；不属于当前可直选策略路径时，以原有 NodeSelectionView sheet 处理，不修改订阅的自动组或规则。只在节点区局部动画化订阅变化与名称显示设置，未向实时图表加入新隐式动画。

iOS Simulator Debug 构建通过（build/mobile-home-library-controls-build.log）。iPhone 17 Pro 的现有内存示例验证：Horizon 首页展开原生菜单、订阅 A → B，列表从 1 个节点更新到 2 个，在首页切换到第二节点后确认勾号随之更新；经典样式入口与无订阅／无节点状态显示正常。测试使用 permitsNetwork: false，未访问真实订阅、CloudKit 或建立 VPN。连接中重连与最终动效／iPad 真机排版未进行实机验收。324 项范围外源码／资源／工程指纹一致；Mac 显式工程不引用新增组件。回滚：build/rollback/mobile-home-library-controls-20261018/restore.py（默认核对，包含本轮新增组件，检测后续改动时拒绝覆盖）。


## 移动端首页切换布局稳定与节点符号动画（2026-10-18）

代码审查确认：首页订阅菜单使用新旧 Text 的 ZStack 淡化，旧文字退场后仍可能改变固有宽度；HomeRoutingPickerView 由 .id(subscriptionID) 整体重建，初始 record=nil 导致分段控件灰色加载态；HomeNodeListView 的订阅 ID 动画会将懒加载内容高度变化纳入插值，同时每个 ForEach 项目产生节点和分隔线两个子项。HorizonInformationView 还将 Ping／连接状态动画作用于整个信息区。节点勾号此前只有 opacity，未采用 SymbolEffectTransition。

修复：菜单文字填满稳定可用宽度，将下拉／进度槽固定在边缘；分流 Picker 保留原生视图身份，仅按目标 ID 更换维护 store，并以 ID／来源摘要／可见性作为加载键。加载期间仅缓存上次视觉选中态；操作仍要求 store.id、当前订阅 ID、record 与忙状态匹配，异步结果同时核对引用和取消状态，失败不允许写入旧订阅。重新加载不再切换灰色样式，辅助功能仍区分加载、不可用和已应用。接受的后台操作继续由原维护服务拥有。

节点行和分隔线组成单个 lazy 子项，行身份包含订阅 ID 与节点名；去除库存高度动画和外层继承动画，叶节点的选中／进度仍局部过渡。Horizon 信息区至少占一个 viewport，短订阅变化不再通过内容尾部回收将墙体拉回；两种首页为内容尺寸变化显式采用原生顶部锚点（Apple API: https://developer.apple.com/documentation/swiftui/view/defaultscrollanchor(_:for:)）。Ping／连接变化不再动画化整个信息区；Ping 胶囊在订阅／节点提交时只锁交互并保留调色，动作守卫覆盖辅助功能。

公用 NodeSelectionRowView 的勾号改为条件插入／移除配合 SF Symbols appear 过渡，适用于首页和移动端 Nodes；固定 24×24 标识槽、150 ms 延迟的原生 ProgressView 与减少动态效果分支保留。未改动节点选择、分流提交、连接、凭据或同步服务。

验证：iOS Simulator Debug 构建通过（build/mobile-home-switch-stability-build.log）。使用现有内存示例（permitsNetwork=false）执行订阅 A（1 节点）→ B（2 节点）→ A，首页选择第二节点成功；静态截图的图表／速率／累计区域像素差为 0，回切后的标题、分流栏区域也为 0（build/mobile-home-switch-stability/）。离线示例尝试智能分流因本地资源不足得到原有失败提示，原分流与选择保留；本轮未据此声明已验证真实智能分流或连接中的重连。320 项范围外源码／资源／工程指纹一致，Mac 显式工程不引用本轮移动端组件。没有安装真机、启停真实 VPN 或访问真实云端；iPad 真机与连续动效体验仍由用户确认。回滚：build/rollback/mobile-home-switch-stability-20261018/restore.py（默认核对，拒绝覆盖后续改动）。


## 移动端节点勾号 Draw On（2026-10-18）

将公用 NodeSelectionRowView 的选中符号过渡从 appear 改为 SF Symbols 原生 drawOn.byLayer，以描绘方式进入／退场；保留原 checkmark.circle.fill 图标、24×24 占位、延迟加载与减少动态效果的 opacity 分支。仅影响 iPhone／iPad 首页和 Nodes 使用的节点行，不改 Mac 或切换业务。API 已核对本地 iOS 26 SDK 与 Apple SymbolEffectTransition 文档：https://developer.apple.com/documentation/swiftui/symboleffecttransition 。

iOS Simulator Debug 构建通过（build/mobile-node-draw-on-build.log）；327 项范围外源码／资源／工程指纹一致。未安装或启动实机，未操作真实网络；描绘节奏由用户真机体验确认。回滚：build/rollback/mobile-node-draw-on-20261018/restore.py（默认核对，拒绝覆盖后续修改）。


## 首页订阅名称在切换后滚动时飘动（2026-10-18）

用户明确范围仅为当前订阅名称。本轮没有继续调整页面高度、滚动锚点、节点列表或分流状态。原菜单名称通过 .id(title) 在 ZStack 中插入新 Text 并保留旧 Text 退场；旧视图过渡叠加父级滚动是文字独立漂移的潜在来源。改为同一 Text 的 contentTransition(.opacity)，动画边界在外层截断／占位布局之前，并为菜单标签增加 geometryGroup，让内容淡化与祖先几何移动分别处理，保留固定加载／下拉槽和点按高度。节点 Draw On 与切换／确认业务不变。

iOS Simulator Debug 构建通过（build/mobile-home-title-scroll-build.log）。现有离线内存示例验证菜单 A→B、滚动回墙体方向，更新后的名称与菜单下拉位置保持对应；工具观测不作为 0.3 秒内容过渡中逐帧或真机动效验收。未执行真实连接、云端或真机安装。327 项范围外源码／资源／工程指纹一致，Mac 未改。回滚：build/rollback/mobile-home-title-scroll-20261018/restore.py（默认核对，拒绝覆盖后续改动）。


## 首页订阅菜单右箭头（2026-10-18）

HomeSubscriptionMenu 的 chevron.down 改为 chevron.right，保持 20×20 图标槽、加载指示器、名称内容淡化和原生菜单行为。仅移动端共享首页组件变化，Mac 未改。iOS Simulator Debug 构建通过；未安装真机或操作网络。回滚：build/rollback/mobile-subscription-chevron-right-20261018/restore.py。


## 首页移除订阅说明标题（2026-10-18）

移除 HorizonInformationView 中「当前订阅／Subscription」小标题及其单用途 VStack，保留订阅名称原生菜单、右箭头与 Ping；名称和 Ping 现在直接同排对齐。iPhone／iPad 共用该组件，经典样式没有这行说明，Mac 未改。iOS Simulator Debug 构建通过；未安装真机或改变网络。回滚：build/rollback/mobile-home-subscription-caption-20261018/restore.py。


## 移动端首页双向滚动箭头（2026-10-18）

HorizonHomeView 保留连接按钮下方的同一个 60×44 点滚动按钮。以按钮在命名 viewport 内的实际中心位置判断方向：进入屏幕上方 25% 区域时切换为向上，回到 40% 以下区域时恢复向下，中间保留上次方向，避免临界位置来回闪动。几何观察只输出上／缓冲／下三种区域，箭头使用局部 SF Symbols replace 过渡，不改变布局；减少动态效果时取消符号与滚动动画。辅助功能名称随实际动作切换。

向下点按改为将按钮自身停靠到 viewport 上部（8% 锚点），保留返回入口，再次点按回到 hero 顶部。保留原有 0.65 秒滚动曲线，不增加悬浮副本或额外手势。手动继续向下滚动时仍遵循原有页面内容布局，按钮并非常驻悬浮。

iOS Simulator Debug 构建通过（build/mobile-home-scroll-toggle-build.log）。iPhone 17 Pro 离线内存示例实际点按验证：向下滚动后箭头可见且改为向上，点按返回标题／墙壁首页并恢复向下。连续动效观感与 iPad 真机效果仍由用户确认。324 项范围外源码／资源／工程指纹一致，未改动 Mac、连接或云同步服务，未安装实机或改变真实网络。回滚：build/rollback/mobile-home-scroll-toggle-20261018/restore.py（默认只核对，拒绝覆盖后续改动）。


## 移动端首页滚动箭头连续变形（2026-10-18）

将 SF Symbols 向上／向下替换改为 HorizonScrollButton 内同一条三点折线路径。按钮在 viewport 的 40%～25% 区域内，进度由实际几何位置连续映射到 0～1，再以 smoothstep 平滑两端；折线从向下、展平到向上，反向滚动可沿原路径恢复。端点与中点围绕固定中心移动，保持 16×6 图形和 60×44 点击区域，无视图替换、交叉淡化、布局增删或额外逐帧计时器。仅子组件持有变形进度，并清除图形继承的动画，避免滚动本身与第二套插值叠加。

点击目标与当前路径方向一致，以变形中点作为动作分界；保留返回 hero 顶部与下滑后按钮停靠 8% 的原生滚动。减少动态效果时直接显示最终方向，父页面同时停用自动滚动动画。辅助功能标签与实际动作同步。

iOS Simulator Debug 构建通过（build/mobile-home-scroll-morph-build.log），新组件已由同步目录纳入移动端 target。iPhone 17 Pro 离线内存示例验证向下点按后呈现向上路径、再次点按返回首页并恢复向下。324 项范围外源码／资源／工程指纹一致，Mac 工程不引用本轮两个组件，未改动连接或云同步，未安装真机或改变网络。连续动效的真机观感与 iPad 实机效果仍待用户确认。回滚：build/rollback/mobile-home-scroll-morph-20261018/restore.py（默认核对，检测到后续改动时拒绝覆盖）。


## 移动端首页节点区域留白（2026-10-18）

移除 HomeNodeListView 顶部「节点／Nodes」标题及其下方 12 pt 留白。HorizonInformationView 与经典 HomeView 两处父布局仅将节点区域横向扩展 6 pt，结合页面原有 26 pt 边距后，节点区域左右实际为 20 pt；流量图、订阅菜单与其他信息块的边距不变。分隔线额外左右缩进由 8 pt 改为 4 pt，距离内容侧边实际为 24 pt。保持节点编号、文字、固定选中／进度槽、点按范围与原有切换逻辑。

iOS Simulator Debug 构建通过（build/mobile-home-node-insets-build.log），diff 空白检查通过；322 项范围外源码／资源／工程指纹一致。仅移动端首页相关布局变化，Nodes 功能页与 Mac 未改，未安装设备或操作网络。实际真机排版观感待用户确认。用户已自行撤回的箭头改动未重新引入。回滚：build/rollback/mobile-home-node-insets-20261018/restore.py（默认核对，检测后续改动时拒绝覆盖）。


## 移动端首页节点区分界与紧凑边距（2026-10-18）

在实时流量与首页节点列表之间添加分割线。Horizon 样式沿用现有 white 0.16、0.5 pt 线条，经典样式沿用 primary 0.12、0.5 pt 线条；新线与各首页原有分割线两端同为 26 pt 边距，经典样式沿用局部入场过渡。装饰线对辅助功能隐藏。首页节点区左右边距从 20 pt 收至 16 pt，节点间分隔线保留额外 4 pt 缩进，因此实际边距同步从 24 pt 缩为 20 pt。保持无「节点」标题、单一主页滚动、节点行身份及选择动画，不修改 Nodes 功能页或 Mac。

iOS Simulator Debug 构建通过（build/mobile-home-node-divider-build.log），diff 空白检查通过；323 项范围外源码／资源／工程指纹一致。未安装实机或操作网络，实际排版与动效观感由用户确认。回滚：build/rollback/mobile-home-node-divider-20261018/restore.py（默认核对，检测后续改动时拒绝覆盖）。


## 移动端首页订阅节点替换过渡（2026-10-18）

代码确认 HomeNodeListView 清除了列表外层动画，订阅 ID 变化又会重建节点行，因此库存替换原先没有可见过渡。保留清除 lazy 布局动画的边界，在其外单独对节点区域 opacity 做 0.12 秒淡出／0.18 秒淡入。仅为呈现暂存订阅 ID、节点名称／协议和选中名称，在完全透明时更新节点布局；不叠放新旧长列表，不插值节点行高，不向主页或流量图加入隐式动画。单节点选中仍沿用原有局部符号动效。

以订阅 ID 与节点名称／协议库存、页面可见性、减少动态效果组合作为可取消任务键。连续切换时旧任务不再提交过期节点；返回仍显示的订阅时恢复透明度。隐藏页面／减少动态效果时直接采用最新库存。过渡期间旧列表不可点按、不可由辅助功能操作，节点动作再次核对库存与当前订阅，再调用原有带 expectedConfigurationID 的选择流程。当前边距、分割线和用户手工调整保持不变。

iOS Simulator Debug 构建通过（build/mobile-home-node-inventory-fade-build.log）。iPhone 17 Pro 离线内存示例验证 A（1 节点）→B（2 节点）、在 B 选择第二节点、B→A，节点库存与选中标记正确，切回后节点区正常可见；实际真机动效节奏仍由用户确认。取消／快速回切与减少动态效果分支完成源码检查，未声称已完成对应真机观感验收。324 项范围外源码／资源／工程指纹一致，Mac、Nodes 功能页及连接／分流／同步服务未改；未安装真机或改变实际网络。回滚：build/rollback/mobile-home-node-inventory-fade-20261018/restore.py（默认核对，检测后续改动时拒绝覆盖）。


## iPhone 首页信息区域随滚动聚焦（2026-10-18）

仅在 HorizonHomeView 的 phone 分支为下方 HorizonInformationView 加入 HorizonInformationFocus；iPad 直接返回原内容，经典首页与 Mac 未接入。以现有滚动偏移、hero 高度和 viewport 高度推算信息区域顶部位置，从 viewport 下方 94% 到 62% 区间以 smoothstep 连续恢复清晰；初始模糊半径 8 pt、透明度 0.12，进入信息区域后为 0 pt／1。向上滚动沿同一进度恢复背景态。信息上沿用 28 pt 黑色到透明渐变融入场景，装饰层不参与点击或辅助功能；避免对整个长节点列表增加 mask 或 drawingGroup。

无新增计时器、手势、隐式全页动画或布局位移。保留滚动锚点、最小信息 viewport、原生 Tab 栏、底部留白、连接按钮和场景清晰度。减少动态效果时仅做透明度变化；减少透明度时保持信息清晰，跳过本效果。未改变信息区操作权限、节点替换淡化、分流、同步或连接逻辑。

iOS Simulator Debug 构建通过（build/iphone-home-information-focus-build.log）。iPhone 17 Pro 离线内存示例验证首屏信息退为模糊淡化背景，向下箭头滚动后订阅／分流／图表／节点正常清晰；样例最后节点可见于 Tab 栏上方。连续动效观感、长订阅与其他 iPhone 尺寸的实机表现仍待用户确认；iPad 条件分支完成源码核对，未宣称实机验收。324 项范围外源码／资源／工程指纹一致，未安装实机或改变网络。回滚：build/rollback/iphone-home-information-focus-20261018/restore.py（默认核对，检测后续改动时拒绝覆盖）。


## iPad 原生侧栏实时流量（2026-10-18）

RootTabView 仅在 pad 分支把原有 TelemetryStore 引用传给 TabletRootView，通过 sidebar List 的底部 safeAreaInset 挂载 TabletSidebarTrafficView。沿用 Mac 的非首页显示策略：节点、订阅、策略组、测速和设置页面显示侧栏曲线及上下行速率，首页、引导或显式 detailOnly 时淡出；footer 保持挂载，导航列表 viewport 不随选中页变动。没有替换原生侧栏材质，也没有为曲线增加背景卡片。

复用已有 ScrollingTrafficPlot、TrafficWindow 历史、量程与映射设置，未新建采样器或 IPC 轮询。64 pt 曲线与上下两行速率，箭头／数字／单位列固定，数字采用 NumericText、单位采用局部透明度过渡；未知速率显示破折号。隐藏、离开窗口或场景非活跃时暂停连续绘图时钟；减少动态效果时停用显示时钟和局部动画。读数提供双语辅助功能标签。

iOS Simulator Debug 构建通过（build/ipad-sidebar-traffic-build.log），diff 空白检查通过，324 项范围外源码／资源／工程指纹一致。iPhone 分支、主页、采样与连接服务未改；Mac 显式工程不引用本次 iPad 组件。未运行 iPad 实机／模拟器布局与动效验收，实际 iPad 宽窄窗口、侧栏折叠和连续曲线观感待用户确认。未安装实机或改变网络。回滚：build/rollback/ipad-sidebar-traffic-20261018/restore.py（默认核对，检测后续改动时拒绝覆盖）。


## iPad 首页保留侧栏流量（2026-10-18）

移除 TabletRootView 的 selected != 0 显示限制：包括首页在内的所有 iPad 页面，只要侧栏可见且不在引导中，就显示侧栏实时曲线与上下行速率。保持固定占位、后台／隐藏时暂停绘图时钟与现有共享采样；首页自身图表也保留，两处使用同一份数据。更新组件注释以反映跨页面常显行为。iPhone、Mac 及采样服务未改。

iOS Simulator Debug 构建通过（build/ipad-sidebar-traffic-on-home-build.log），diff 空白检查通过；325 项范围外文件指纹一致。iPad 实际显示待用户确认，未安装实机或改变网络。回滚：build/rollback/ipad-sidebar-traffic-on-home-20261018/restore.py。


## iPad 侧栏去标题与首页订阅行微调（2026-10-18）

移除 TabletSidebarTrafficView 上方「实时流量／Live traffic」标题，保留曲线、上下行速率、固定列宽与跨页面挂载。HorizonInformationView 中订阅名称／右箭头／Ping 的 HStack 仅在 pad 设备整体 offset y=-3 pt，保持内部对齐、原布局占位和后续信息块位置。手机 offset 为 0，Mac 工程不引用这两个组件，未改动服务与采样逻辑。

iOS Simulator Debug 构建通过（build/ipad-home-header-sidebar-title-build.log），diff 空白检查通过；325 项范围外文件指纹一致。iPad 底边实际显示与动效仍待用户实机确认；未安装实机或改变网络。回滚：build/rollback/ipad-home-header-sidebar-title-20261018/restore.py。


## iPad 首页订阅菜单箭头紧随名称（2026-10-18）

HomeSubscriptionMenu 的标题 Text 仅在 pad 上取消 maxWidth infinity，按实际名称占用宽度，使右侧固定 20 pt 箭头／加载槽紧随名称，HStack 保留 8 pt 间距。Horizon 信息行已有的 Spacer 负责菜单与右侧 Ping 之间的剩余空间；保留 Ping 的 layoutPriority(1)、名称单行中间截断、44 pt 点按高度、同一 Text 的透明度过渡和 geometryGroup。没有改变订阅切换、菜单确认或节点更新逻辑。用户手工修改的 iPad 整行 offset=-20 pt 完整保留。iPhone 继续采用原标题填满行为，Mac 工程不引用该组件。

iOS Simulator Debug 构建通过（build/ipad-subscription-inline-chevron-build.log），diff 空白检查通过；326 项范围外文件指纹一致。未进行 iPad 实机排版或动效验收，实际宽窄窗口与长名称观感待用户确认；未安装实机或改变网络。回滚：build/rollback/ipad-subscription-inline-chevron-20261018/restore.py。


## iPhone 首页模糊起点延后（2026-10-18）

HorizonInformationFocus 保留最大模糊终点 94% viewport，将恢复清晰／开始模糊的边界从 62% 移到 80%，过渡距离由 32% 收至 14%。返回场景时，信息顶部退到屏幕下方 80% 才开始模糊、变淡与上沿渐隐；展开信息时沿相同 smoothstep 更早恢复清晰。最大模糊 8 pt、最低透明度 0.12、无障碍分支、布局和点击行为保持原样。该修饰器仍只在 iPhone Horizon 首页启用，iPad 与 Mac 未改。

iOS Simulator Debug 构建通过（build/iphone-home-focus-later-build.log），diff 空白检查通过；326 项范围外文件指纹一致。仅调整过渡区间，未安装实机或操作网络，真机动效节奏由用户确认。回滚：build/rollback/iphone-home-focus-later-20261018/restore.py。
