# 首页首次入场

## 表现

默认 Horizon 风格下，全新本地数据首次启动在读取真实系统状态后先展示三章功能指南，再播放约 5 秒序幕：

- 0–0.6 秒：无墙，完整的地理粒子地球淡入。地球采用 1.3 倍尺寸，窄视口保留完整球面的边缘余量，不覆盖用户保存的地球尺寸。
- 0.6–2.6 秒：原位置的实体砖块按层从下到上入场；同层砖块逐块错峰，相邻层交替方向，按可见区域安排延迟，避免屏幕外的大量砖块挤占时序。每块独立缓动约 160 ms；每块沿用生产环境的实体面、抗锯齿白边及深度遮挡。砂浆背板在墙完成后加入，避免未建成的墙提前遮挡地球。
- 2.6–5 秒：未连接时，地球散开并淡出，镜头沿原有路径退回墙内。实际已连接时保留成形地球和墙顶视角，平滑恢复用户保存的地球尺寸。连接中/恢复中则交接给正常的墙外散点场。
- 结束后标题、操作按钮和信息淡入。全程使用同一个 Metal renderer，保留粒子时间与地球旋转，不替换场景。

“跳过”从当前姿态用约 0.45 秒收束到实际状态。系统减少动态效果或关闭粒子动效时，省略筑墙和运镜，以约 0.4 秒的简化显示交接。切后台暂停时间线，返回继续；Tab Bar 从启动状态判定、指南到序幕最后一帧呈现期间隐藏；完成或跳过动画收束后才恢复，回到首页不重播。入场不显示虚假的连接状态、不调用连接/断开接口，正常连接按钮在序幕中不可操作。

## 前置功能指南

`HorizonGuideView.swift` 是独立页面，三章依次介绍订阅导入（文件/URL/二维码）、节点切换/Ping/首页流量、点击或下拉连接。每章使用一个标题与一行关键词，支持中英文、上一步、继续和跳过指南；不自动翻页。结束或跳过指南都会进入地球筑墙序幕，序幕仍有独立跳过按钮。最后一章墙后使用现有 Natural Earth 陆地点数据绘制地球，实体砖面遮挡其下半部分。第三章改为下拉上方场景进入：捕获最后已呈现的场景姿态，手指进度经柔和跟随与缓进缓出映射，驱动相机、地球和虚拟视口对齐首页序幕，同时淡出墙和文案；达到阈值后松手补完过渡。跳过指南仍可用原来的自动衔接。Metal 画布保持整页大小，只改变投影，避免 UIKit 尺寸动画与 Metal drawable / 透视宽高比不同步造成地球压扁。前后两段共用一个可暂停的环境时钟，地球自转与外围粒子在交接期间继续运动；先等待指南终点帧，再等待首页对应帧真正呈现，两个画面在尺寸、位置、朝向和时间一致时直接交接，然后才开始筑墙。匹配帧不再做双 Metal 图层交叉淡化，避免透明粒子与黑色底层的独立透明度叠加造成亮度下探。真机使用 drawable 呈现回调；模拟器 SDK 不提供此接口，使用 GPU 完成回调，并另行检查录屏。前两章跳过或减少动态效果时仅淡化，不强制经过第三章运镜。

`HorizonGuideScene` 的卡片、节点、墙使用 SwiftUI Canvas；地球改为真正共用首页 Metal 粒子管线 `HorizonParticlePass`，由透明 `HorizonGuideGlobeView` 显示在实体墙之后。三组示意物体位于同一空间，原生动画驱动镜头连续移动；入场有轻微推近和淡入。节点与曲线仅为无数值的演示，不读取配置或发起网络请求。主页面在指南期间不可操作，Metal 序幕暂停，直到指南交接后才开始计时。

指南新增 Core Motion 手机倾斜视差：三章共用一个以进入时姿态为中位的相机偏移，约 17° 达到幅度上限，使用 0.20 秒低通跟随，镜头水平/垂直偏移限制为 1.40/1.00 世界单位（比上一版增加约五成）。文字与按钮不随之移动；切章不会重置姿态。横竖屏切换及后台恢复重新取中位，并从保留的偏移平滑归位。只在指南可见且动效开启时以 30 Hz 读取姿态，退出/后台/减少动态效果/关闭粒子时停止采样；无传感器时保留正常场景。数据不保存或上传，Info.plist 包含运动用途说明。正常首页和后续 Metal 地球筑墙序幕的相机不受此视差影响。

第二章保留第一版细线圆节点树：圆形编号、直线分支和下方两条示意曲线，不使用厚实的倒角节点。曲线现在嵌入一个有透视倾角的线框屏幕，配有上、下行模拟速率。三个节点在高低和深度方向错位，02 靠后、03 靠前，下方汇合点作为第四个不共面的顶点，形成开放的三角锥构图；仍只绘制三条分支。节点与卡片、墙一起响应手机倾斜和手指拖动。圆形编号始终朝向相机，半径按透视变化并限制在 11–18 pt，数字保持可读；先画分支，再按远近绘制编号，避免连线盖过数字。背景粒子采用连续的横、纵、深度漂移，位置不周期性重置，并提高可见度。节点绘制在 `HorizonGuideNodeTree.swift`，相机/粒子轨迹和地球交接几何在 `HorizonGuideGeometry.swift`，指南和首页的地理粒子绘制均在 `HorizonParticlePass.swift`，统一参数结构在 `HorizonRenderFrame.swift`。传感器生命周期在 `GuideDeviceMotion.swift`，平滑计算在 `GuideTiltFilter.swift`。

指南环境动画限制为 30 fps，交接期间为 60 fps；后台暂停且恢复时不跳过经过的时间；减少动态效果或关闭粒子动效时停止环境运动，减少动态效果还会取消镜头位移，仅保留文字淡变。大字号可滚动阅读；VoiceOver 获得完整操作说明。

首次记录沿用原来的完成标记：已完成旧版序幕的用户不会因新增指南而再次被强制首播。调试版“重播首次入场”现在会重播指南和序幕全流程。

## 首次记录及迁移

`Clash/Services/FirstLaunchExperience.swift` 在 UserDefaults 保存 `launch.homeIntroductionCompleted.v1`，完成或主动跳过后记录；普通冷启动不重播，序幕期间进程被终止则下次可以重试。

已有 UI/连接偏好、系统 VPN 配置或本地订阅作为旧版本迁移证据，避免老用户首次更新后被强制首播。旧版从未保存任何偏好/配置时无法与全新数据严格区分。记录随本地 App 数据而存在，备份恢复/保留数据的重装也可能保留记录；它不是“此人从未下载过”的证明。记录不写入钥匙串，不读取或记录订阅凭据。

调试构建：设置 → 外观 → **重播首次入场**。此入口只重播视觉表现，不修改 VPN 或尺寸偏好；正式构建不显示。

隔离模拟器预览环境：`CLASH_SUBSCRIPTIONS_DEMO=1`、`CLASH_STARTUP_AUDIT=empty`、`CLASH_STARTUP_STYLE=horizon`、`CLASH_FIRST_LAUNCH_PREVIEW=1`。使用内存订阅库，禁用 VPN 操作；预览完成不覆盖首次记录。

## 验证

- 离线回归覆盖五种连接阶段的时间线连续性、完整地球横纵向适配、跳过、减少动态效果、途中断开、旋转/时间交接、首次完成记录、旧版迁移和预览；断言包含逐帧采样。
- 原有下拉连接、取消/继续、地球拖动/归位和墙体几何回归通过。
- 模拟器隔离空库完成全段播放并到达“等待导入”首页；设置重播和跳过入口已操作验证。
- 模拟器构建、真机签名构建通过。未安装真机或改变 VPN；已连接分支由离线逻辑检查覆盖，真机上的节奏、亮度、遮挡观感、性能及后台续播仍待体验。

复现离线检查：

```sh
xcrun swiftc -parse-as-library -module-cache-path .build/bridge-check-module-cache \
  Clash/Features/Horizon/Rendering/HorizonMotion.swift \
  Clash/Features/Horizon/Rendering/HorizonIntroduction.swift \
  Clash/Features/Horizon/Rendering/HorizonGeometry.swift \
  Clash/Features/Horizon/Rendering/HorizonSceneClock.swift \
  Clash/Services/FirstLaunchExperience.swift scripts/check-first-launch.swift \
  -o .build/check-first-launch
.build/check-first-launch
```

指南检查：`scripts/check-guide.swift` 检查相机路径与后台计时连续性；`scripts/check-first-launch.swift` 检查指南交接、旧回调隔离、跳过与冷启动记录。模拟器隔离空库已走通三章 → 序幕 → 等待导入首页。真机观感、VoiceOver 实机朗读及实际耗电尚未验收。

本轮指南调整验证：模拟器操作三章，检查圆节点、墙后地球和最终交接；离线检查覆盖章节顺序、背景漂移、倾斜极值限幅、突变平滑、无效输入、长时间暂停后归位，以及不同宽高比下地球/相机交接位置和朝向保持。模拟器无法验收实际传感器手感，需在手机的“重播首次入场”中检查轻微左右/前后倾斜；本轮不安装真机、不改变 VPN。

```sh
xcrun swiftc -parse-as-library -module-cache-path .build/bridge-check-module-cache \
  Clash/Features/Horizon/Rendering/HorizonGeometry.swift \
  Clash/Features/Horizon/Rendering/HorizonSceneClock.swift \
  Clash/Features/Horizon/Rendering/HorizonGuideTransition.swift \
  Clash/Features/Horizon/Rendering/HorizonGuidePullMotion.swift \
  Clash/Features/Horizon/Rendering/HorizonGuideGeometry.swift \
  Clash/Features/Horizon/Rendering/HorizonIntroCamera.swift \
  Clash/Features/Horizon/Rendering/HorizonGuidePullState.swift \
  Clash/Features/Horizon/HorizonGuideStep.swift Clash/Services/GuideTiltFilter.swift \
  scripts/check-guide.swift -o .build/check-guide
.build/check-guide
```

## 地球渲染一致性

已移除指南原先的 Canvas 近似地球（半数陆地点、实心圆点、12 档透明度、0.7 亮度补偿）。指南与首页现共用完整陆地点、1,200 个海洋点及 1,200 个外围漂浮点，同一个柔边粒子 shader、加法混合、MSAA、随深度变化的点大小和低功耗抽样策略。当前保留 intro 前的粒子尺寸与柔边；仅指南小球的陆地／海洋点亮度系数设为 0.8，外围漂浮点不变。随下拉／自动交接进度，用五次缓动恢复到 1，终点斜率为零。首页该参数为零（禁用），保持原版输出。指南保留自己的镜头构图与墙后遮挡；交接终点匹配首页序幕的相机、地球、旋转和时间。主场景原有点云外观不变。外围点云随指南构图缩放，交接时归一到主场景原有空间。

`scripts/check-particle-parity.swift` 用生产 Metal 管线离屏检查：正常/降采样两种质量、三个时间点，指南交接与首页序幕平均 RGB 字节误差最大约 0.00031；基准直接读取 Git 快照 `ce20c95` 的原始 shader 和陆地数据，避免由当前源码反推基准掩盖共同回归。核对完整陆地数据一致、指南小球仅适度调暗且外围漂浮点不变，以及主场景 1×／2× 地球在散点、汇聚中和成球三种状态下与旧版输出一致。指南外围漂浮点保留适配镜头的空间位置，点尺寸和亮度不单独缩减。此检查验证粒子层，不等于真机整页动效验收。

```sh
xcrun swiftc -parse-as-library -module-cache-path .build/bridge-check-module-cache \
  Clash/Features/Horizon/Rendering/HorizonGeometry.swift \
  Clash/Features/Horizon/Rendering/HorizonSceneClock.swift \
  Clash/Features/Horizon/Rendering/HorizonGuideTransition.swift \
  Clash/Features/Horizon/Rendering/HorizonGuidePullMotion.swift \
  Clash/Features/Horizon/Rendering/HorizonGuideGeometry.swift \
  Clash/Features/Horizon/Rendering/HorizonRenderFrame.swift \
  Clash/Features/Horizon/Rendering/HorizonParticlePass.swift \
  scripts/check-particle-parity.swift -o .build/check-particle-parity
.build/check-particle-parity
```

## 第三章无缝交接回归

- `HorizonGuideTransition.swift` 统一场景与视口进度；`HorizonFramePresentation.swift` 负责两端画面准备确认。完成通知按首次入场会话 ID 隔离，旧回调和尚未呈现的首页不能提前释放序幕。
- `check-guide.swift` 增加横/竖视口、带倾斜及切章未完成时开始交接的逐帧检查：固定画布内的横纵像素投影比例一致，初末姿态准确衔接，开始/结束速度趋零。环境及过渡时钟在后台暂停。
- `check-first-launch.swift` 共 5,087 项检查通过，含等待目标帧与过期回调处理；生产 GPU 粒子一致性检查通过。模拟器和真机签名构建、扩展包检查通过。
- 模拟器录屏 `.build/guide-seamless.mp4` 已检查交接段连续帧：原先点击后压成椭圆的现象不再出现，地球平滑放大并保持位置与朝向交给后续序幕，最终到达等待导入首页。模拟器结果不能替代真机帧时序和观感验收；本轮未安装手机或操作 VPN。

### 交接闪烁与 Tab Bar 时序修复

- 上一版录屏的交接区存在亮度先降后升，位置已对齐但两层 Metal 交叉淡化仍有波动。匹配帧改为无淡化交接；前两章直接跳过的路径仍保留简短淡出。
- `FirstLaunchExperience.suppressesTabBar` 覆盖尚未判定首次状态、指南、预渲染、筑墙、回落及跳过收束，最终帧通过呈现回调确认后才释放系统 Tab Bar。普通启动和完成后恢复原生滚动收起行为。
- 首页恢复原始 `max(540, min(880, geometry.size.height * 0.96))` 高度计算。`HorizonIntroductionTabBar` 仅在 intro 中隐藏系统 Tab Bar 的显示、交互与辅助功能入口，并保留原有布局占位；完成后恢复原状态并淡入，因此不必把底部安全区永久计入首页场景。
- 新模拟器录屏 `.build/intro-stable-tabs.mp4` 已检查指南交接与最终入场：交接亮度下探消失，序幕中无 Tab Bar，Tab Bar 出现时墙的位置保持稳定。5087 项首次入场逻辑检查、模拟器构建、真机签名构建与扩展包检查通过。本轮没有安装真机或改变 VPN，手机动效观感仍由用户确认。

### 场景互动与连续自转

- Skip 按钮在指南交接完成后的下一次 UI 更新中独立淡入 0.45 秒；减少动态效果时为 0.2 秒，不再随底层页面直接露出。
- `HorizonSceneClock` 贯穿第三章、空间过渡、目标画面准备和筑墙序幕。序幕姿态可以等候交接，但地球旋转与漂浮粒子继续使用同一时钟；后台暂停，接回正常首页时保留当前时间和朝向。
- 第一章三张实体卡片分别有少量 yaw/pitch/roll 偏转，SF Symbol 跟随卡片平面的投影；不改变砖墙模型。
- 三章及后续序幕的场景区域可二维拖动摄像机，拖动按视口归一化且限制在单位圆内；松手 0.75 秒柔和归位，归位途中再次触摸从当前姿态继续。手机倾斜与手指视角偏移叠加；自动交接采用最后呈现的姿态，序幕退场时手动偏移逐渐归零。文字区域仍可正常滚动，场景演示不触发 VPN。
- `HorizonCameraDragSurface` 负责场景局部手势，`HorizonIntroCamera` 负责有界视角与归位。计算每帧姿态直接使用 TimelineView 日期，不经过 GeometryReader 的延后布局闭包，避免手势更新干扰时间线取样。关闭粒子或减少动态效果时，拖动仍直接响应，松手立即归位；应用退到后台时清除未完成手势。
- 离线覆盖旋转持续推进、共享时钟交接与后台暂停、手动视角限幅、归位连续性、重新抓取及卡片刚性旋转。模拟器完成横/纵拖动、随后切章与桥接、自转、Skip 淡入和序幕结束回归；录屏为 `.build/intro-drag-final.mp4`。真机晃动手感与最终动效观感仍待用户确认。

### 首页布局恢复

移除了先前为防止 intro 结束跳动而加入的全局底部安全区补偿，恢复原有场景高度及连接按钮、下方信息区的位置。intro 的 Tab Bar 控制独立在 `Components/HorizonIntroductionTabBar.swift`，使用公开 UIKit 父控制器关系定位所属 Tab Bar，保留布局占位；只临时修改透明度、点击及辅助功能状态，结束或组件拆除时恢复原值，不切换系统栏的布局可见性。

模拟器已走完三章 → 序幕 → 首页，Tab Bar 入场时场景位置稳定，恢复后的 Nodes/Home 切换可用；录屏 `.build/home-layout-restored.mp4`。模拟器和真机签名构建、扩展包检查通过。本轮未安装真机或改变 VPN。

## 线框流量屏与下拉进入

- 第二章的 `HorizonGuideTrafficDisplay.swift` 绘制同一世界空间中的线框屏幕，左侧约 70% 显示曲线，右侧纵向排列上传／下载速率，以细线分隔，整体随视角变化；两个通道采用平滑的伪随机演示信号，曲线持续滚动，数字每 3 秒更新，`HorizonGuideTrafficReadout.swift` 使用独立的原生 SwiftUI Text 和 NumericText 过渡（约 1.15 秒），不再使用 Canvas 双份文字交叉淡化。箭头、单位及数字区域宽度固定；坐标仍投影到同一个屏幕平面。曲线信号约放慢 4 倍，节点明暗轮换由 2.6 秒放慢为 6.5 秒。示意数值始终使用 KB/s，与曲线来自同一信号，完全不读取真实隧道统计或发起请求。按用户要求移除面板 DEMO 字样；数据仍仅用于指南演示，辅助功能说明仍明确这一点。
- 第三章取消 Begin 按钮，说明文字下方、底部导航上方的留白中央显示缓慢浮动的向下箭头与“Swipe to continue／下滑以继续”，字体与标题同为白色轻字重。每次进入第三章，在前台停留 5 秒后用 1.8 秒渐显；离开章节或切到后台会取消并重置等待。第三章小字为“Now start your journey at HORIZON!”（中文随语言设置）。场景下拉以五次缓进缓出曲线生成目标，再由统一限速、限加速度运动模型追随；约下拉场景高度的 38% 后可松手进入。手指仍按住时可以反向撤回，绝不提前进入。起步阶段（进度约 0–12%）标题、说明、页眉及底部指引即渐隐，手势表面本身不隐藏。`HorizonGuidePullMotion.swift` 在拖动、松手、重新接手之间保留同一位置与速度，最大空间进度速度 0.65/s、加速度 1.8/s²，急速反向也先制动再回退。归位必须等运动模型到达起点并已呈现才恢复正常场景，不再由固定时长的 SwiftUI completion 提前撤掉镜头；重新接手对已呈现进度反解且保留惯性。停帧追赶限制为 50 ms，内部以至多 1/240 秒子步积分。
- `HorizonGuidePullState.swift` 管理阈值、取消和提交，`HorizonGuidePullSurface.swift` 负责场景区域的原生手势与辅助功能入口。第三章滑动不触发 VPN；文字区仍可滚动，前两章的视角拖动保留。减少动态效果或关闭粒子时保留阈值及取消行为，完成后采用原有淡化交接；VoiceOver 可激活场景继续，顶部也保留跳过。
- 仍由同一个时钟维持地球自转；只有最终匹配帧呈现才交接到序幕，Tab Bar 继续等序幕播放结束后出现。
- 验证：模拟器短拉退回、完整下拉进入序幕已通过；录屏 `.build/guide-pull-interaction.mp4` 检查了退回与完成交接。离线检查覆盖反向拖动、系统取消、归位中重新接手、重复结束以及底层交接映射、手势缓动的单调性、缓进缓出端点和重新接手的逆映射。模拟器及真机签名构建、包检查通过。本轮未安装真机，实际手感及 VoiceOver 朗读仍待手机体验。

本次节奏调整验证：模拟器录屏 `.build/guide-polish.mp4` 检查数字滚动、中央箭头、短拉退回及完整交接；局部连续帧 `.build/guide-numeric-contact.png` 可见原生数字过渡时箭头与单位保持稳定。模拟器/真机签名构建和包检查通过，实际手机手感待用户体验。

布局与回退更新验证：30/60/120 Hz 下快速反向、松手、重新接手、最终收敛和停帧恢复均检查速度与加速度上限；模拟器录屏 `.build/guide-layout-motion.mp4` 检查右侧纵排速率、5 秒等待后指引渐显、短拉退回、快速上滑及完整进入序幕。模拟器和真机签名构建、包检查通过，本轮未安装手机或更改 VPN；真机急甩手感仍待用户确认。

指引与归位显示修复：箭头改为文字左侧横向排列；指引成为 ScrollView 正常内容中的独立行，按剩余可视高度居中，底部导航单独占位。小屏／大字体下可滚动，不与返回按钮叠放。文案透明度锁定本次拖动的最大隐藏程度，反向拖动和重新接手都不会提前亮起；归位帧确认位置和速度均为零后，才通过同一次 0.16 秒 ease-out 动画恢复标题、说明、页眉、指引与底部控件。原有 5 秒首次指引延迟保留。状态回归覆盖反向／重新接手时隐藏及归位重置；模拟器录屏 `.build/guide-return-visibility.mp4` 已检查回退全程隐藏、到位后渐显和布局间距。模拟器／真机签名构建、包检查通过，真机观感待用户确认。

归位等待缩短：原来的距离 0.00001／速度 0.0001 收敛阈值会留下肉眼难以辨认的指数运动尾段，现改为距离 0.0002／速度 0.001，然后归到精确起点。仍由起点帧呈现回调触发文字恢复，不在运动途中提前显示；文字渐显由 0.5 秒 ease-in-out 改为 0.35 秒 ease-out。固定手势模型在 30/60/120 Hz 下均提前约 0.73 秒结束，属于离线模型测量，不代表真机延迟实测。投影回归检查横竖屏、倾斜范围下墙顶点与地球取样点的最终修正小于 0.5 pt；速度／加速度及取消／重新接手检查通过。模拟器短拉返回检查、模拟器及真机签名构建、包检查通过；未安装手机，观感仍待用户体验。

2026-10-04 粒子外观回归：已取消指南额外点尺寸／亮度补偿；生产 Metal 离屏比较通过，包含正常与低功耗抽样、三个旋转时间点、小球原始外观、1×／2× 首页和交接一致性。真机签名构建及扩展包检查通过（`.build/particle-restore-device.log`），本轮未安装手机；整页观感由用户验收。运镜、归位文字时机和 intro 几何布局未调整。

2026-10-04 小地球过曝修复（后续已按用户要求撤回，以下为历史验证）：只对指南球面粒子补偿，漂浮点和正常首页不变。固定离屏样例中高亮饱和像素由 18,330 降至 1,261（正常质量），降采样模式由 13,326 降至 612；这是指定样例的 GPU 结果，不是手机整屏指标。与首页交接平均 RGB 字节误差最大约 0.00031；首页 1×／2×、多个时间与汇聚阶段继续通过旧版 shader 对比。签名构建与包检查通过（`.build/intro-small-globe-device.log`），本轮未安装手机，真机视觉验收待用户反馈。

2026-10-04 对比回退：撤回上一次指南小球专用尺寸／亮度补偿，恢复较亮的原始粒子表现，并恢复对应旧版画面对比断言。仅回退该项视觉调整，保留镜头、交接、文字时机等既有行为。

## 2026-10-04 指南交互细节更新

- 地球：维持用户选择的较粗粒子，不恢复点尺寸缩放或亚像素覆盖率衰减；只把指南球面点亮度调为 80%，随交接进度连续恢复，反向下拉同一路径回退。完整点集、首页 1×／2×、三个时间点及散点／汇聚／成球状态均继续与 intro 前快照比较；交接平均 RGB 字节误差最大约 0.00031。
- Part 3 返回上一章：指引使用稳定的视图身份及布局占位，局部 0.22 秒退场，非第三章暂停箭头 Timeline 并从辅助功能隐藏。首次停留 5 秒、1.8 秒渐显规则保留；手势隐藏透明度放在独立外层，避免被指引初次渐显的慢动画干扰。
- 手机静止校准：角速度小于 0.04 rad/s 且相对候选姿态累计漂移小于 0.004 rad，持续约 0.4 秒后，将当前姿态设为中位。滤波时间常数 0.55 秒平滑归中，开始移动恢复原 0.20 秒响应；持续缓慢倾斜、短暂停顿和后台时间不计作稳定。相机手势、普通首页不改变；传感器真机手感尚待用户体验。
- 下拉取消：保持最大速度 0.65/s、加速度 1.8/s² 和原终点误差限制，加快回退尾段并预留制动距离。最初直接加快响应的方案在越界回归中失败，增加制动距离后通过。固定手势模型从近静止（进度 < 0.001）到精确归位约 0.20 秒；这是模型结果，不是真机时延测量。仍等起点帧呈现后立即启动 0.16 秒文字恢复；没有动画场景的降级路径不再额外等待 0.85 秒。
- 验证：30/60/120 Hz 运动边界、取消／重新接手、静止校准／慢漂移／暂停、亮度 1,001 个进度点、GPU 首页及交接对比通过。模拟器构建和真机签名构建、包检查通过；模拟器录屏 `.build/intro-refinements.mp4` 检查了 Part 3 返回、指引多帧淡出和短拉取消恢复。现有非本轮文件的 Swift actor 隔离警告仍存在。本轮未安装手机、未操作 VPN，最终视觉及传感器体验由用户确认。

归中触发微调：稳定等待从 1.2 秒缩短为 0.4 秒；同步缩短稳定窗口内累计角漂移上限，保持持续缓慢倾斜不会被误判为静止。归中滤波时间常数仍为 0.55 秒，0.4 秒指开始回正的等待时间。指引字号现按用户确认调为 26 pt（跟随动态字体），标题字号保持独立。

2026-10-04 指引字号与筑墙时机：Swipe to continue 使用独立的 26 pt 动态字号；Part 3 已呈现地球后接续序幕，移除原来留给地球淡入的 0.6 秒等待，首个动画推进帧开始筑墙。初始交接帧仍为无墙，保持画面匹配；逐砖构建仍用 2 秒，后续回落仍用 2.4 秒。没有地球交接的直接序幕保留原先淡入等待。

本轮验证：5,202 项首次入场时序／状态检查通过，包含 30/60/120 Hz 下接续首帧启动筑墙、独立序幕保留等待与完整结束；真机签名构建和包检查通过（`.build/intro-wall-timing-device.log`）。本轮未安装手机，字体比例与筑墙观感待用户确认。

过渡序幕 Skip 布局：从场景底部移到页面安全区域右上角，使用原生玻璃胶囊按钮，保持 44 pt 最小点击高度及原有独立淡入淡出。按钮作为页面 overlay，不参与场景布局／滚动，不改变 Metal 画布尺寸和交接坐标。欢迎页已加入，详见下文。

## 欢迎页

新增独立页面 `HorizonWelcomeView.swift`，文案为 Welcome to / HORIZON / Here, you can…，提供中文版本、右下角 Next 和右上角跳过指南。欢迎页不自动翻页、不计入 Part 1–3；Part 1 的返回按钮可回到欢迎页。

父页仍由 `HorizonGuideView` 统一协调导航和操作，使用同一场景实例、设备倾斜状态与 `HorizonGuidePlayback` 时间线。欢迎相机位于第一章左侧，欢迎停留时环境粒子隐藏、时间线及设备倾斜暂停；点击 Next 完成文字退场后，镜头连续移向三张卡片，环境粒子按同一空间进度平滑显示。已有三章粒子种子、相机端点和地球渲染保持原值，仅向欢迎区域扩展环境粒子。欢迎页隐藏示意物，后台暂停，减少动态效果时省略空间移动；动态字体布局可滚动。

欢迎页玻璃控件淡出后移出视图树，避免透明控件继续参与叠加；共享场景不移除。欢迎页沿用首次体验的记录，不新增永久标记；完成后普通冷启动不重播，调试重播从欢迎页开始，直接跳过仍进入现有序幕。全程不读取节点用于演示、不连接 VPN。

验证：指南离线回归（含欢迎相机到 Part 1 的连续路径）和 5,202 项首次启动检查通过；模拟器／真机签名构建、包检查通过。模拟器已操作欢迎 Next → Part 1 → 返回欢迎 → 再进入 → Part 2 → Part 3 → 下拉 → 序幕 → 首页，以及欢迎页直接跳过 → 序幕 → 首页。录屏 `.build/welcome-guide-final.mp4` 和连续帧已检查；本轮没有安装手机，真机视觉与 VoiceOver 实际朗读待体验。

### 欢迎页字体与文字编排

欢迎页 HORIZON 使用与指南左上角标识一致的系统默认字体，欢迎页单独使用极细字重，显示为 `H O R I Z O N`（字母间加空格、额外字距 1.5），辅助功能标签仍为 HORIZON，保留 46 pt 主标题尺寸。Welcome to 保持系统等宽轻字重 24 pt／字距 1，引导句为 19 pt，均随动态字体缩放。背景纯黑，不显示粒子；进入 Part 1 时恢复现有粒子场。

三行使用稳定 Text identity、隐藏的最终文字测量占位和原生 `.numericText(value:)` 内容过渡；间隔 0.18 秒出现，每行约 0.6 秒。点击 Next 后，文字退场、指南淡入和相机移动在同一次状态更新中开始，统一使用 1.5 秒、控制点 (0.42, 0, 0.58, 1) 的缓进缓出曲线；文字只保留 0.04 秒逐行错峰，1.58 秒后移除欢迎页。导航在退场期间锁定，入口任务取消。Skip 使用相同文字退场后进入既有序幕，不经过 Part 1。减少动态效果改为短淡化；任务随视图移除取消，返回欢迎页重新入场。隐藏占位不参与辅助功能。

验证：模拟器欢迎 Next → Part 1 → 返回欢迎 → Skip 到首页已操作；录屏 `.build/welcome-synchronized.mp4` 及连续帧检查文字退场期间场景已同时移动。模拟器与 iOS 签名构建、包检查通过（`.build/welcome-synchronized-device.log`），本轮未安装手机，最终字体和动效观感待用户确认。

本轮细化：HORIZON 与引导句之间加入 0.5 pt／20% 白色分割线，最大宽度 230 pt，固定占位避免入场改变布局。标题出现后延迟 0.12 秒，用 0.8 秒从左向右绘制；退场跟随文字左移淡出，减少动态效果时仅淡化。Part 1／2／3 的双向相机切换同样改为 1.5 秒，保留其原缓动曲线；Part 3 手势入口等待相机完成（1.55 秒）再启用，不修改手势跟随或后续序幕时序。

本轮验证：模拟器欢迎页及 Part 1 → Part 2 → Part 3 导航通过，录屏 `.build/welcome-divider.mp4` 检查欢迎页入场；模拟器构建、iOS 签名构建及包检查通过（`.build/welcome-divider-device.log`）。未安装手机，真机动效观感待用户体验。

Part 3 文字渐隐细化：完全淡出的手势进度由 0.12 延长到 0.24，仍从起步开始按平滑曲线淡出；不改场景跟随、提交阈值或归位后的 0.16 秒淡入。取消／重新抓取时使用同一个淡出阈值保持文字隐藏，直到实际场景归位。离线回归覆盖微小下拉、中段可见度、取消和重新抓取；模拟器构建、iOS 签名构建（`.build/welcome-spacing-device.log`）及包检查通过，欢迎页布局和 HORIZON 辅助功能标签已在模拟器检查。本轮未安装手机，真机动效观感待用户确认。


### 普通冷启动首页入场（2026-10-04）

RootTabView 在本次进程中保存一次性的 homeEntered 展示状态。等待真实配置与 VPN 初始状态读取完成后，场景淡入，标题、连接操作和信息区以 0–160 ms 错峰、420 ms ease-out 出现，文字区上移仅 6–8 pt。减少动态效果时使用 180 ms 淡入，不位移、不错峰。HomeEntrance 通过 SwiftUI 局部动画闭包仅控制透明度和偏移，不修改布局、摄像机、流量采样或图表时间轴。

首次 introduction 直接旁路这段动画，保留原有指南与电影过渡；切换 Tab、后台恢复和切换界面风格不重置入场标记。任务在后台取消时等待下次前台继续，避免普通启动停留在透明状态。

验证：模拟器构建通过；隔离示例验证 Horizon 已连接首页、经典无配置首页、Tab 返回，以及首次预览的 Welcome 入口。示例状态不代表真实 VPN，未安装手机；错峰与淡入的真机观感仍由用户确认。


### 首次介绍后的 VPN 配置询问（2026-10-04）

真实首次指南与电影过渡完成（包括主动跳过）后，记录待询问标记；等首页收尾淡入 500 ms、应用在前台且初始状态已读取后展示 VPNSetupView。询问本身不保存系统配置；只有用户点击“添加配置”才刷新系统状态并调用 prepareProfile，且不调用 start/connectCurrentProfile。支持没有订阅时预先完成 VPN 配置授权，关闭按需连接。已有可用配置直接消耗待询问标记。

“稍后”、关闭 sheet 或成功授权均消耗询问标记，冷启动不重复；介绍刚结束但尚未处理询问就结束进程时，下次可继续询问。授权失败保留 sheet 和安全错误信息，支持重试或稍后。DEBUG 预览、设置重播及旧用户升级不新增询问。模拟器和离线演示禁用添加动作。系统授权由用户操作，不能绕过；用户跳过或随后删除配置时，首次连接仍可能需要系统授权。

验证：首次启动离线检查 5,213 项通过；模拟器通过临时启动参数注入待询问标记，验证英文 sheet、模拟器禁用添加和 Not now 关闭。未触发真实 VPN 配置变更；系统允许、拒绝及重新授权等待真机验收。


### 添加配置后提前检查互联网访问（2026-10-04）

用户点击添加配置后，若 VPN profile 已准备，等待系统权限弹窗退出 inactive 状态，再向固定的 `https://cp.cloudflare.com/generate_204` 发出 HEAD 请求。成功添加配置不会启动 VPN；请求只检查 App 的当前互联网可达性，并给需要无线数据授权的系统一次提前询问机会。没有通用的“互联网权限已授予”判定：204 只代表该请求成功，其他响应／超时均显示未能确认联网，不直接解释为用户拒绝权限。系统是否弹窗取决于设备与已有授权，不能保证强制出现。

请求使用临时 URLSession，禁用缓存、Cookie、凭据存储与重定向，不携带订阅内容；不请求本地网络权限。目标服务会像普通 HTTPS 访问一样看到连接来源与协议元数据。使用 waitsForConnectivity，资源超时 30 秒；选择稍后／关闭 sheet／真正进入后台会取消检查。系统权限弹窗导致的 inactive 不取消。失败保留已添加的 VPN profile，可重试网络检查或稍后继续，不重复创建 profile。只有检查成功才自动关闭本次 sheet。

参考：[URLSession waitsForConnectivity](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/waitsforconnectivity)、[Apple 本地网络权限说明](https://support.apple.com/zh-cn/102229)。

验证：模拟器构建通过；`scripts/check-network-access.swift` 用 URLProtocol 拦截全部请求，覆盖 204、非 204、超时、取消、固定 HEAD 目标和无 Cookie／凭据／缓存配置。没有真实网络请求或 VPN 配置变化。真机无线数据询问、允许／拒绝与重试仍待验收。

```sh
xcrun swiftc -parse-as-library -module-cache-path .build/bridge-check-module-cache Clash/Services/NetworkAccessCheck.swift scripts/check-network-access.swift -o .build/check-network-access
.build/check-network-access
```


### Horizon 连接按钮的断开过渡（2026-10-04）

修正 disconnecting 阶段原先立即显示灰色 Connect/xmark、随后又切换 Connect/arrow 的两段状态变化。现在在系统 disconnecting 时保留 Disconnect/power，按钮禁用且辅助功能读作 Disconnecting VPN，直到系统真正断开才变为 Connect。实际可用性仍由原有 actionDisabled 决定。

HorizonConnectionButton 保持同一个按钮和图标占位；根据用户后续反馈，取消最大文字宽度预留，恢复随当前标题自然伸缩。按钮宽度、玻璃轮廓、文字淡变、图标原生替换和禁用状态使用统一 0.3 秒局部动画，响应减少动态效果。不会给整页、Metal 运镜或实时曲线附加动画。

验证：模拟器构建通过，隔离连接状态下按钮显示和可访问标签正常。未启停真机 VPN，连续断开动效仍由用户体验确认。


#### 回退后：按钮整体居中过渡修正

用户回退文字度量／自定义交叉淡变方案后，进一步确认问题是按钮整体跳动。本轮保留回退后的原生 Text、symbolEffect、glass Button 和自然宽度，只在 HorizonConnectionButton 的动画边界内加入 geometryGroup 与居中的弹性外层 frame。玻璃与标签使用同一几何坐标空间，外层居中位置随内部宽度一起过渡。外层占满行宽，实际玻璃胶囊和可点击按钮仍使用当前标题的自然宽度；没有最长文字预留、UIKit 字体度量或延迟断开操作。

参考：[Apple geometryGroup](https://developer.apple.com/documentation/swiftui/view/geometrygroup())。它用于建立局部几何动画边界；不对首页、运镜和流量图施加额外动画。

验证：模拟器构建通过。DEBUG HorizonScenePreviewView 复用生产按钮，以虚构 connected → disconnecting（80 ms）→ idle 状态录制同一场景前后连续帧。旧版可观察到外框过渡初段短暂向右偏移后归中；修复后的对应序列未观察到这一横向偏移。最终可访问标签为 Connect，仍可再次操作。此证据限于隔离模拟器序列，不代替真机视觉验收；未安装手机或操作真实 VPN。减少动态效果仍沿用原有关闭局部尺寸动画的逻辑。

#### 冷启动 Connect 图标的无效切换

把按钮的临时交互禁用与持久连接条件分开。原先 symbol 依赖 isDisabled，前台 refresh 的 isBusy 波动也会驱动 arrow → xmark → arrow，并播放 replace。现在 unavailable 仅取未能读取系统配置或缺少订阅；临时 refresh、准备操作仍禁用按钮，但不更换图标。保留原有 `.symbolEffect(.replace)`，按用户要求不更改正常图标切换动画；保留前一轮 geometryGroup 与自然宽度修复。图标本身变化也有局部动画，减少动态效果仍使用 opacity 并关闭局部动画。

验证：模拟器构建通过。隔离预览以 450 ms 虚构 refresh 验证暂时禁用 → 恢复可用，录制连续帧中箭头保持不变，操作从禁用恢复可用。此为无网络模拟状态验证，不代表捕获到了用户设备上的具体时序；真机冷启动观感待用户确认。

### 无网络时拦截首页连接（2026-10-04）

NetworkAvailability 在服务层持有一个 NWPathMonitor，主线程发布状态，不访问任何网站或启动网络请求。仅系统明确报告 unsatisfied 时判为离线；首次 unknown 不误判，requiresConnection 允许连接尝试，因为系统可能按需激活该通路。参考：[Apple NWPath.Status](https://developer.apple.com/documentation/network/nwpath/status-swift.enum)。这不是 Internet、DNS 或节点可达性证明；Wi-Fi 已连接但无外网等情况仍由连接诊断处理。

Horizon 与经典首页离线时弱化连接按钮，Horizon 使用已有 xmark 不可用图标；保留点击以显示“无网络连接／请检查 Wi-Fi 或蜂窝数据。”的中英文本地化原生 alert。辅助功能提示可轻点查看详情。禁止离线下滑启动；下滑途中断网重置手势。连接确认提交时再次校验，若离线，待 sheet 关闭后显示 alert。connectCurrentProfile 在准备 VPN 配置之前检查，start 在实际启动之前再次检查；在系统配置授权期间离线同样不继续启动。已有 connected／connecting／reasserting 的断开或取消操作不受网络限制。网络恢复自动更新按钮，但不自动连接 VPN。

保留用户指定的原生 symbolEffect.replace、自然按钮宽度及居中过渡；只有离线状态变化驱动局部外观动画，不给整页或流量曲线添加动画。

验证：模拟器构建通过，NetworkAvailabilityTests 两项测试通过，覆盖明确离线、可用、按需通路、初始未知、离线首页服务入口拒绝和恢复后不自动启动。隔离 UI 检查通过：Horizon／经典首页断网点击提示；模拟恢复后可进入连接确认；确认 sheet 打开后模拟断网，提交后显示 alert；已连接且模拟离线时 Disconnect 仍可点击。全程没有更改 Mac／iPhone 网络或启动真实 VPN。真机关闭 Wi-Fi／蜂窝、恢复后的系统状态时序与视觉观感尚待验收。

DEBUG 验证使用 CLASH_SUBSCRIPTIONS_DEMO=1 + CLASH_STARTUP_AUDIT=idle/connected + CLASH_STARTUP_STYLE=horizon/classic；CLASH_NETWORK_AUDIT=offline 固定离线，recover 在 12 秒后恢复，drop 在 8 秒后断网。只作用于内存演示控制器，不监测或改动系统网络。

### 介绍期间提前出现网络询问：监控启动时机（2026-10-04）

排查发现 NetworkAvailability 曾在构造时立即创建并启动 NWPathMonitor，早于首次介绍状态的解析；显式 NetworkAccessCheck 则仅在添加 VPN 配置成功后执行。现在 NetworkAvailability 构造不初始化系统监控，由 RootTabView 在介绍完成且首次设置提示处理完、前台展示时启动。首次添加 VPN 的路径在系统 VPN 授权结束、介绍完成后启动监控并继续原有联网检查。普通冷启动在首屏状态解析后启动一次监控，不自动发起 HTTP 检查。未得到路径回调时维持 unknown，不等同于离线。

这移除了已发现的提前初始化入口，不证明 NWPathMonitor 就是系统无线数据弹窗的直接原因。真实首次安装弹窗时序仍需真机验证；不重置手机权限，不删除现有订阅。离线状态机检查覆盖未解析、指南、电影过渡、待设置提示、提示处理后及普通冷启动。

### Welcome 笔画标题与按钮时序（2026-10-05）

Welcome 标题采用独立 HorizonWelcomeWordmark 矢量组件，字母间 55 ms 错峰，字母内部逐笔减速绘制。按原系统 UltraLight 字体、实际空格和 tracking 1.5 的度量排版，单笔采用四次 ease-out 及较长收尾；后台暂停，减少动态效果时渐显完整字样。

分割线增强为白色透明度 0.34、宽 0.75 pt，保留 0.8 秒绘制及 0.12 秒延迟。Next 等标题完成回调、分割线和说明文字入场结束，再以 0.35 秒渐显；隐藏期间保留占位，但关闭点击与辅助功能访问。Skip 始终可用，退场会取消尚未完成的出现任务。

绘制前的标题源码及恢复注意事项见 [回档基准](design/welcome-title/README.md)，不提供额外设置项。构建验证和真机动效验收分开记录。

Welcome 时序补充：分割线改为 trim 从 0.5…0.5 展开至 0…1，由中心同时向两端绘制。删除笔画完成后的 0.16 秒停留、父页 0.12 秒等待和分割线 0.12 秒延迟；每笔四次 ease-out 与加长收尾不变。标题真实绘制完成即衔接说明文字／细线，Next 仍在两者完成后渐显。iPhone 签名构建通过；本轮未安装真机，动效观感待用户确认。
