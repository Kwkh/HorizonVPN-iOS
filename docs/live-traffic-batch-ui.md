# 构建 16：实时曲线、批量测速与三页界面

## 2026-10-05 更新：后台真实历史补取

以下新行为取代早期版本“前台采样、后台没有历史”的限制：

- Packet Tunnel 在内核运行期间通过 lifecycle 串行队列每秒读取累计字节（100 ms timer leeway），缓存最近 66 秒、最多 72 条真实采样。主 App 不必存活或保持前台。停止／失败时取消定时器并清空缓存，不落盘、不包含节点名称或凭据。
- 主 App 使用 `telemetry.history.v1` 读取快照，核对连接 epoch、配置标识、会话、时间顺序、数据大小及新鲜度。返回前台／同一 VPN 仍在运行时冷启动，可直接恢复最近一分钟波形；热切节点保留同会话计数，新 VPN 会话不混入旧数据。
- 快照整体重建最多 72 个采样，重复回复不会重复追加，过期回复不能倒退时间。原 `telemetry.v2` 保留给诊断及其他单点计数用途。
- 等待首次历史回复时暂时保留原图位置，收到后恢复真实时间轴。读取失败后仍按原设计回零；不以冻结的旧速率冒充当前速率。
- 扩展定时器若被系统延迟超过 3.5 秒，或计数不可用／倒退，重新建立基线，缺失段按未测量零线处理，不计算跨长间隔平均速率。不能承诺系统休眠期间每秒都能执行定时器；恢复已有真实数据，不生成漏采数据。

验证：`HorizonTests/TelemetryHistoryTests` 覆盖 90 秒以上后台恢复、冷 App 恢复、重复／倒序、热切／会话重启、漏采与计数倒退、缺失计数时间戳、容量及 IPC 编解码。`scripts/check-traffic-recorder.swift` 使用虚构计数验证无 App 轮询的定时采样、停止、重启和补采；另运行原 `check-traffic.swift`、`check-traffic-plot.swift`。真机后台运行、锁屏调度及视觉体验需安装后确认，模拟器测试不代替真实 VPN 验收。

```sh
xcrun swiftc -parse-as-library -module-cache-path .build/bridge-check-module-cache Shared/LiveTelemetry.swift Shared/TelemetryHistory.swift PacketTunnel/TunnelTrafficRecorder.swift scripts/check-traffic-recorder.swift -o .build/check-traffic-recorder
.build/check-traffic-recorder
```

## 已实现

- 主页、节点、设置三个原生 Tab。默认深色，无卡片堆叠，使用细分割线；系统 Tab、导航按钮和主要控制使用 iOS 26 原生玻璃效果。
- 主页单图显示上传（珊瑚橙）、下载（蓝）两条曲线，共用速率尺度，下方独立读数。最近 60 秒，最多保留 60 个点；速率按十进制 B/s、KB/s、MB/s 换算。
- 数据来自扩展中内核的累计上下载字节，以同一隧道会话内单调时钟间隔计算增量速率。范围是经过内核统计的流量，包括 DIRECT 和代理；不等同于 iPhone 全部接口流量，也不是测速推算值。
- 按用户要求，断开或无法采样时绘制零线并继续前进。此类点内部标记为未测量，数值区显示“—”。计数倒退、采样间隔超过 3.5 秒、会话或配置变化时重新建立基线，不计算跨间隔速率。
- 前台主页约每秒采样一次（消息往返时间额外计入实际间隔）。切换 Tab 或退后台停止采样，不在后台伪造历史；回到主页从新基线继续。
- 批测当前订阅全部节点，原生请求共享最多 5 个并发名额，每节点 10 秒超时。使用与单节点 Ping 相同的 HTTP HEAD／unified-delay 配置；需要 2xx 响应才算成功。它是请求延迟测试，不是 ICMP Ping 或带宽测试。
- 批测不会切换节点；可取消，可手动按延迟排序。取消传递至 Go context，排队和已发起请求都会结束。退后台、断开、网络不可用和配置变化使当前批次取消/过期；扩展 15 秒未收到批次轮询也会取消，防止 App 退出后继续测试。
- 结果按 batch/session/configuration 三个标识校验，旧响应不能覆盖新连接或新批次。原始节点名、地址、密码和服务器响应不通过批测 IPC 返回。
- 设置提供跟随系统／简体中文／English、深色／浅色／跟随系统、粒子动效开关。主页面及订阅、选择、测速操作界面提供双语；旧诊断记录、配置适配说明和错误细节目前仍以中文为主。
- 粒子采用单 Canvas，确定性轨道与光晕；离开主页或进后台暂停，响应 Reduce Motion，低电量模式降至最多 20 次更新/秒。灵动岛仅标记后续加入，没有可用开关。

## 文件组织

每个主要页面和 sheet 独立成文件，按功能存放在 `Clash/Features/`；主页子视图在 `Home/Components/`。业务位于 `Clash/Services/`，IPC 数据模型位于 `Shared/`，批测队列位于 `PacketTunnel/BatchProbeRunner.swift`。

## 构建与检查

依赖版本仍固定在 `Configuration/Core.lock.json`，仅更新本地隐私桥接补丁的校验值。批测新增 `CancellableURLTests`，从固定 Hako 源码构建，不能沿用旧 XCFramework。

```sh
python3 scripts/build-core.py --build
python3 scripts/check-ping-core.py
python3 scripts/check-configuration.py
xcrun swiftc -parse-as-library -module-cache-path .build/bridge-check-module-cache scripts/check-traffic.swift Shared/LiveTelemetry.swift -o .build/check-traffic
.build/check-traffic
xcodebuild -project Clash.xcodeproj -scheme Clash -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/Clash-UI16Signed build
python3 scripts/check-bundle.py /private/tmp/Clash-UI16Signed/Build/Products/Debug-iphoneos/Clash.app
```

先完成内核构建再运行内核测试；这些命令会准备同一个源码缓存，不要并行启动准备阶段。已有签名可直接使用，命令未开启 provisioning updates。更新手机前先断开 VPN；保留原 YAML 和构建 15 的源码/安装产物以便回退。构建 16 没有修改订阅钥匙串格式。

## 已验证与边界（2026-10-02）

- 固定内核重新构建成功，模块校验与许可证清单生成通过。
- Go 回归通过：统一延迟第二次响应计时、超时、HTTP 状态校验；12 个任务分属两个批次时最多 3 个原生请求，取消可终止排队/执行中任务，取消后新批次可用。
- Swift 纯模型检查通过：实测增量、重复/倒序响应、真实零和未测量零的区分、长间隔、计数重置、会话/配置隔离与 60 点上限。
- 61/61 虚构配置检查及双协议内核预检通过，没有使用真实订阅。
- 主 App 和 Packet Tunnel 真机构建、嵌入扩展标识与版本检查通过。
- iOS 26.5 模拟器已检查三页导航、默认深色、切到浅色、切到简体中文和未连接时禁用批测。模拟器使用内存中的虚构订阅，不能作为 VPN 联网证据。
- 真机已安装构建 16，连接后观察到同图两条实际速率曲线和增长的累计字节；一次观察累计下行 52 KB、上行 42 KB、当时下载 614 B/s（仅为测试瞬时数据）。
- 真机单节点批测完成 221 ms；切到双节点订阅后旧结果标记过期，新一轮 Hysteria2 / VLESS 分别为 214 / 213 ms。取消后两行显示 Cancelled，随后观察未被迟到结果覆盖；重测完成，Hysteria2 / VLESS 为 213 / 305 ms，当前选择仍为节点 1。VLESS 的这一证据仅证明本次原生 HTTP 延迟请求成功，不代表完整 PacketFlow、UDP、IPv6 和全部规则验收。
- 新动画的实际帧率、内存与耗电尚未做 Instruments 定量分析；大量真实节点批测和 App 被杀后 15 秒租约兜底也尚未真机验收。

- 收尾真机检查：离开批测回到主页后采样恢复；断开进入 Disconnecting 后再进入 Disconnected，速率读数变为“—”，图表继续沿零线推进。已恢复测试前的订阅，保留未连接状态。

## 构建 17：连续滚动（2026-10-02）

本次只调整实时图表与其绘图缓冲，不改内核、订阅格式和测速口径。

- 图高 112 → 90 pt；上方留白从峰值的 1.15 倍增至 1.45 倍，波形纵向更紧凑。
- Swift Charts 的逐采样动画替换为两个长期保留的 CAShapeLayer，由 CADisplayLink 的显示时钟统一平移。每帧移动量严格按经过时间计算，60 秒通过整个视窗，采样之间也持续向左移动。
- 路径只在数据、尺寸或平滑纵轴比例变化时重建；提交时关闭隐式动画，并补偿已移动的坐标，不做交叉淡化、点身份替换或每秒重启的转场。
- 曲线使用保形 Hermite 插值，经过实测点且不产生超出相邻值的峰值。为保留下一段插值所需的数据，最终图形约延后 2.5 秒显示；下方速率数字仍是最新实测值。暂停采样时仅图形回零，不生成实测数值。
- 纵轴上限随峰值上升平缓扩大，旧峰离开后缓慢回落；缓存保留 66 秒、最多 72 点，绘图仍显示 60 秒，避免左边缘过早删除样本。
- 时间位置和缓存裁剪都使用单调时钟。屏幕可见且 App 前台时请求 60 Hz 绘图，低电量 30 Hz；离开主页／后台停止显示回调。减少动态效果时保留采样读数和静态绘图。
- 新增独立、明确标注“虚构数据 · 无网络请求”的 Debug 渲染页，仅在 `CLASH_CHART_PREVIEW=1` 时启用。正常 App 不注入演示流量。

主机检查 `scripts/check-traffic-plot.swift` 覆盖连续帧的匀速位移、路径重建前后位置一致、不同刷新率下相同的纵轴缓动、插值无越界以及追加数据不改写旧段切线。`scripts/check-traffic.swift` 继续覆盖真实速率计算和未测量零点。

```sh
xcrun swiftc -parse-as-library -module-cache-path .build/bridge-check-module-cache scripts/check-traffic-plot.swift Shared/LiveTelemetry.swift Clash/Features/Home/Components/TrafficPlotGeometry.swift -o .build/check-traffic-plot
.build/check-traffic-plot
```

Debug 设置 `CLASH_CHART_METRICS=1` 后记录 1800 个绘图回调，在 App Cache 写入 `traffic-plot-metrics.json`；仅包含耗时和回调间隔，不保存配置、流量数值或地址。此测量不能替代合成器帧率、Instruments 卡顿分析或长期功耗测试。

实现依据：[Apple CADisplayLink](https://developer.apple.com/documentation/quartzcore/cadisplaylink/targettimestamp)、[matchedGeometryEffect 的布局关联范围](https://developer.apple.com/documentation/swiftui/view/matchedgeometryeffect(id:in:properties:anchor:issource:))。连续时间序列使用显示时钟推进；没有将视图间的布局转场套在采样更新上。

构建 17 验证：Swift 速率与滚动几何检查、模拟器构建、真机签名构建及包结构检查通过。模拟器独立波形页连续采集 1800 个回调，绘图耗时中位数 0.451 ms、P95 0.698 ms，回调间隔中位数 16.67 ms、P95 16.67 ms，超过 1.5 倍目标间隔的回调 1 次。此轮模拟器测量早于最终“仅尺寸变化才标记路径重建”的优化；最终签名包已包含该优化。

用户确认暂时断开后，真机已安装构建 17，并在关于页核对版本。使用正常主页与真实隧道采样，观察到上／下行波形、累计字节变化，以及离开设置返回主页后的采样恢复；本轮没有启用虚构波形页。原订阅与 VPN 连接已恢复，手机无线设置未修改。

真机首轮 1800 次回调（包含启动、连接确认与连接过程）：绘图耗时中位数 0.339 ms、P95 0.689 ms、最大 1.425 ms；回调间隔中位数及 P95 均约 16.67 ms，最大 94.13 ms，超过 1.5 倍目标间隔的回调 2 次。该证据证明本轮绘图回调耗时较低，不能排除主线程调度、系统合成或镜像传输造成的卡顿；尚未做 Instruments 合成帧率与长期功耗分析，也不承诺绝无掉帧。原始不含配置内容的报告保存在忽略目录 `.build/research/ui17/device-render-metrics.json`。

复现签名构建与包检查：

```sh
xcodebuild -project Clash.xcodeproj -scheme Clash -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/Clash-UI17Signed build
python3 scripts/check-bundle.py /private/tmp/Clash-UI17Signed/Build/Products/Debug-iphoneos/Clash.app
```

本轮未改变钥匙串格式或固定内核。需要回退时，先断开 VPN，再安装保留的构建 16 签名包；若原签名已过期，按签名说明重新构建，不删除手机上的订阅。

## 构建 18：固定量程、首页 Ping 与跨 Tab 采样（2026-10-02）

- 用户确认采用固定线性纵轴：默认 1 MB/s，图表右上角手动选择 100 KB/s、1 MB/s、10 MB/s 或 100 MB/s。选择保存在本机设置，采样、旧峰移出、Tab 切换均不自动改变量程。曲线超过量程时截在顶部并显示向上超限图标；数字保持真实值。低流量在较大量程下接近零线，是线性比例的预期表现。60 秒横轴、90 pt 图高、约 2.5 秒绘图缓冲保留。
- 上行为亮红色，下行使用当前主题强调色；浅色模式使用更深色值维持可读性。曲线、方向符号和速率数字配色一致。
- 首页右上角新增独立 `HomePingView`，使用原生 Liquid Glass 胶囊按钮，显示未测、测试中、结果或失败关键词。复用原有手动 HTTP 延迟测试、超时和会话失效逻辑，不自动测速、不切节点。未连接、诊断／批测忙碌等沿用原有禁用条件。
- 速率 Text 的 NumericText 增加局部 0.28 秒动画事务，按真实数值判断滚动方向；减少动态效果或离开主页时禁用数字动画，不把动画施加到曲线路径。
- 粒子旧实现使用“绝对时间 × 当前速度”，连接切换会使相位突变。新 `ParticleMotion` 连续积分速度，颜色和速度以同一个渐变进度过渡，快速反向切换也从当前状态继续。离开主页／后台冻结运动时钟，恢复时不归零；关闭动效时静态颜色仍反映连接状态。
- 采样任务归属于 RootTabView 的前台生命周期，不再依赖选中 Tab。节点、设置页仍持续每秒请求真实计数；仅绘图／粒子暂停。离开前台仍停止采样、清除微分基线，回前台重新建立基线，防止把后台长间隔平均值当作实时值。

已验证：固定量程及超限裁剪的纯模型检查、连续滚动检查、真实速率模型回归、粒子长运行时间下切换连续性、过渡反向、暂停恢复及减少动态效果检查通过。模拟器与真机签名构建、嵌入扩展版本检查通过。

模拟器使用虚构订阅，没有实际 VPN 采样：主页轮询 82 次，节点页后增至 97 次，设置页再返回主页增至 134 次；全过程采样任务 starts=1、stops=0。已验证首页 Ping 未连接禁用，四档量程菜单，选择 100 KB/s 后跨 Tab 和 App 重启保留。诊断只保存计数，不包含配置、节点标识或流量值。

USB 开发连接恢复后，构建 18 已安装，关于页核对为 18，首页 Ping 成功返回 207 ms。真实隧道下依次经过主页、节点、设置再回主页，诊断计数为：polls 58 → 111 → 190，measured 14 → 67 → 146；starts 始终为 1、stops 始终为 0。返回主页时真实数字直接可用，原订阅 VPN 保持连接。报告仅包含计数，位于 `.build/research/ui18/device-*-lifecycle.json`。粒子、数字与曲线的主观动效验收按用户新约定由用户在手机上体验反馈。

```sh
xcrun swiftc -parse-as-library -module-cache-path .build/bridge-check-module-cache scripts/check-particle-motion.swift Clash/Features/Home/Components/ParticleMotion.swift -o .build/check-particle-motion
.build/check-particle-motion
xcrun swiftc -parse-as-library -module-cache-path .build/bridge-check-module-cache scripts/check-traffic-plot.swift Shared/LiveTelemetry.swift Clash/Features/Home/Components/TrafficPlotGeometry.swift -o .build/check-traffic-plot
.build/check-traffic-plot
xcodebuild -project Clash.xcodeproj -scheme Clash -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/Clash-UI18Signed build
python3 scripts/check-bundle.py /private/tmp/Clash-UI18Signed/Build/Products/Debug-iphoneos/Clash.app
```

Debug 可显式设置 `CLASH_TELEMETRY_METRICS=1`，在 App Cache 的 `telemetry-lifecycle.json` 查看 starts、stops、polls、measured 四个计数，验证切 Tab 不重启采样。正常启动不写此报告；构建 19 起最多记录前 300 次轮询，避免诊断长期写盘。此版本未改变内核和钥匙串格式，可在断开 VPN 后安装保留的构建 17 回退。

API 依据：[NumericText](https://developer.apple.com/documentation/swiftui/contenttransition/numerictext(value:))、[原生 Glass 按钮样式](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass)。

## 构建 19：首页动态内容过渡补充（2026-10-02）

针对用户在构建 18 试用时指出的突然变化，补充首页局部过渡：Ping 加载图标采用固定宽度区域交叉淡化，结果与玻璃胶囊尺寸参加同一动画事务；累计上下行分别使用 NumericText，速率单位改变使用淡化。连接状态文字、订阅名称、状态点、等待采样提示、诊断入口与量程提示也加入各自的局部过渡。减少动态效果或页面不可见时关闭这些过渡，曲线路径仍由独立显示时钟平移，不套全页隐式动画。

模拟器构建与启动、真机签名构建及嵌入扩展检查通过。用户再次确认后，构建 19 已安装到 iPhone 并正常启动，原订阅 VPN 已恢复连接，真实累计上下行继续增长。本次按正常模式启动，未开启额外诊断写盘；首页 Ping 复测成功返回 202 ms，收尾保持原订阅已连接。动效观感交由用户直接测试反馈，不宣称所有页面、所有系统弹窗的变化已逐一验收。

构建 19 重复构建路径：

```sh
xcodebuild -project Clash.xcodeproj -scheme Clash -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/Clash-UI19Signed build
python3 scripts/check-bundle.py /private/tmp/Clash-UI19Signed/Build/Products/Debug-iphoneos/Clash.app
```

## Verge 曲线源码对照（2026-10-02）

针对用户反馈“波形太平、细节不明显”，检查与此前本机版本一致的 Clash Verge Rev v2.5.2，固定源码提交 `28f2efc504059b1dc75c793618b775c8e1b2a5f1`。只下载公开源码到忽略的研究目录，没有读取真实订阅或改动 Mac 网络。

- 左下角小图 `src/components/layout/traffic-graph.tsx` 使用 Canvas 2D，约 30 个可见点，每 1000 ms 从最新数据缓存取值；线条以二次贝塞尔的相邻中点连接，滚动以一次采样间距／1000 ms 推进，目标绘图频率 15 Hz。
- 该小图的纵轴是固定分段非线性映射，边界包括 10、100、1024、10240、102400、1048576、10485760 B/s。它不会根据当前峰值自动缩放；小流量仍占明显图高。分段公式在部分边界存在小跳变，移植时更适合借鉴数量级压缩的原则并使用连续映射。
- `src/components/home/enhanced-canvas-traffic-graph.tsx` 是另一套仪表盘大图，按当前数据最小／最大值及留白计算线性纵轴。不能把它的自动纵轴行为误当成左下角小图的行为。
- 本项目构建 19 是固定线性 1 MB/s，绘图可用高度约 86 pt：1 KB/s 只有 0.086 pt，5 KB/s 只有 0.43 pt。这足以解释本次“太平”的反馈，继续提高帧率或调整插值不能改变这种比例关系。
- 候选方案：保留固定刻度原则，以 `log1p(rate) / log1p(10 MiB/s)` 做连续的数量级映射，保留线性模式可选。5 KB/s 在此映射下约占 45.3 pt；图形仅用于呈现趋势，高度不再与速率成正比，数值保持原始实测值。因这与此前已确认的固定线性默认不同，须由用户确认后实施。暂不据本次研究改变 60 秒窗口、颜色或显示时钟。

源码：[小图实现](https://github.com/clash-verge-rev/clash-verge-rev/blob/28f2efc504059b1dc75c793618b775c8e1b2a5f1/src/components/layout/traffic-graph.tsx)、[大图实现](https://github.com/clash-verge-rev/clash-verge-rev/blob/28f2efc504059b1dc75c793618b775c8e1b2a5f1/src/components/home/enhanced-canvas-traffic-graph.tsx)。上游为 GPL-3.0；本次为实现对照研究，没有引入 WebView、JS 图表依赖或复制桌面组件。

## 构建 20：固定对数细节模式（2026-10-02）

用户确认上述思路后，加入默认“对数”模式。绘图高度为 `log1p(max(0, rate)) / log1p(10 * 1024 * 1024)`，限制在 0...1；零值准确回到基线，超出 10 MiB/s 时显示原有超限标记。此映射是连续的固定数量级压缩，没有 Verge 分段公式的边界跳变，也不根据采样峰值改变刻度。5 KB/s 在 86 pt 可用图高下约占 45.3 pt，原 1 MB/s 线性模式下为 0.43 pt。

右上菜单提供“细节（固定对数）”和原四档固定线性量程；标题显示“对数”或具体线性量程，避免把非线性图误读为线性高度。新增独立 `ui.trafficMapping` 设置，缺省对数；旧线性量程 `ui.trafficScale` 保留，切回线性后仍可使用。选择持久保存，不会在每次启动时强制改回对数。VoiceOver 提示固定对数上限和高度不成正比。

只有手动改模式／量程时进行约 0.3 秒过渡；反向切换从当前绘图比例继续，普通采样不能重启动画。减少动态效果或离开主页时直接使用目标刻度。数字、累计流量、内核采样、60 秒滚动窗口、2.5 秒绘图缓冲及现有保形插值不变。本轮只借鉴 Verge 的固定非线性呈现思路，不复制其 15 Hz 绘制或 30 秒窗口。

已通过：模拟器构建与启动、真机签名构建、嵌入扩展检查；固定线性／对数映射的单调性、边界连续、零值、超限、异常值、快速切换连续性、减少动态效果立即完成，以及既有滚动与插值检查。模拟器确认默认对数、菜单选择及切回 1 MB/s 线性模式。

用户明确授权后，已断开 VPN、安装构建 20，并按正常模式启动。真机确认原订阅保留、默认显示“对数”，恢复连接后出现真实上下行波形，累计下行 50 KB／上行 37 KB；首页 Ping 成功返回 172 ms。收尾保留原订阅 VPN 已连接。主观动效仍由用户体验反馈；本次未在真机逐档复测量程或重启验证设置持久性。

```sh
xcrun swiftc -parse-as-library -module-cache-path .build/bridge-check-module-cache scripts/check-traffic-plot.swift Shared/LiveTelemetry.swift Clash/Features/Home/Components/TrafficPlotGeometry.swift -o .build/check-traffic-plot
.build/check-traffic-plot
xcodebuild -project Clash.xcodeproj -scheme Clash -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/Clash-UI20Signed build
python3 scripts/check-bundle.py /private/tmp/Clash-UI20Signed/Build/Products/Debug-iphoneos/Clash.app
```

本轮不新增外部依赖，不改变钥匙串或内核版本。可直接在菜单选择线性模式恢复原有刻度；需要二进制回退时，断开 VPN 后安装保留的构建 19，原线性设置仍能读取。

## 构建 21：圆润波形（2026-10-02）

根据用户“更加平滑圆润”的反馈，将精确经过采样点的 Hermite 插值改为相邻中点二次贝塞尔曲线：采样点作为控制点，前后中点作为端点。连接处的一阶切线连续，不规则采样间隔也不会形成折角；曲线始终位于局部控制点的范围内，不产生负值或额外峰值。孤立单点尖峰的图形高度约柔化到原高度的 75%，速率数字、累计值及原始采样保持不变。图形平滑不用于推算实际流量。

固定对数／线性刻度、60 秒横轴、2.5 秒绘图缓冲和持续左移保持不变。路径仍只在采样、布局或手动刻度过渡时重建，普通显示帧只平移已有图层。新采样或移除屏外历史不会改变成熟曲线段。

已通过：既有刻度和滚动检查；不规则采样连接处的切线连续性、无过冲、时间单调、零值尾段，以及新增／裁剪历史稳定性检查；真机签名构建与嵌入扩展检查。用户明确授权后已安装到 iPhone，恢复原订阅 VPN 并保持连接；实际上下行采样绘制出新版曲线，首页 Ping 成功返回 239 ms。主观圆润度待用户体验。本轮未采集性能 trace，不能据此宣称帧率或耗电改善。

构建命令沿用构建 20，将 DerivedData 路径替换为 `/private/tmp/Clash-UI21Signed`。回退可在断开 VPN 后安装保留的构建 20，配置与钥匙串格式未变。

## 构建 22：计入 Ping 实际流量（2026-10-02）

此前内核 URLTest 直接连接节点，绕过普通隧道转发的流量 tracker，所以首页速率与累计值不包含该测试流量。现在在实际测试连接上包装一次 Read/Write，以实际返回的字节数增加原有统计管理器的上下行计数及对应出站分类。首页 Ping、批量测速和同路径内核 URLTest 都适用；统一延迟的两次 HEAD 请求各计实际字节，共享同一次实际请求的调用不会按结果重复加数。

不注册带目标信息的连接记录，不写请求内容或原始日志，不改变测速 URL、超时、状态判断及第二次响应的计时方式。失败状态、取消前和部分读写已经传输的字节也计入；拨号之前没有应用流字节。统计口径是节点连接的应用流字节，不包含外层代理协议握手、IP 包头或重传，不能等同于运营商流量账单。

图表沿用约一秒采样和 2.5 秒绘图缓冲。延迟测试请求量小，正常情况下仅出现较小波动；高背景流量下不保证有可辨认的独立波峰。真实速率和累计值直接使用统一的内核计数，不在 Swift 中补加估算值。

已验证：本机 HTTP 服务独立统计与内核计数逐字节一致（单次、统一延迟双请求、HTTP 503、三路并发）；取消前已上传字节立即可见；部分读写遇到错误时只计实际返回字节；原有超时、统一延迟时钟、批测三并发与取消检查通过。隐私及临时服务回归通过，固定源码 XCFramework 重建、模块校验和三架构 Swift 链接通过。主 App 与扩展签名构建、包检查及内核构建清单与锁文件一致性检查通过。

用户明确授权后已安装构建 22，恢复原订阅并保持连接。真机首页 Ping 返回 164 ms，之后可见双线波形、速率及累计值更新。该次观察同时存在手机后台流量，不能把全部累计增量归因于 Ping；精确字节一致性由隔离的本机回环服务验证。本轮没有在真机重新执行完整批量测速，其共用计数路径及并发行为已经过本机测试。

本轮更新 `Configuration/Patches/hako-private-diagnostics.patch` 及锁文件中的 SHA-256，保留原上游 revision 和 Go/gomobile 版本。需先运行 `python3 scripts/build-core.py --build`，再按构建 20 的 Xcode 命令将 DerivedData 替换为 `/private/tmp/Clash-UI22Signed`。核心检查使用 `python3 scripts/check-ping-core.py`、`python3 scripts/check-core-privacy.py` 和 `python3 scripts/check-core-link.py`。配置与钥匙串格式不变，可断开 VPN 后用保留的构建 21 回退。

## 2026-10-04：无需 VPN 的测速与节点行操作

### 行为

- 首页 Ping、Nodes 右侧 Ping、批测页都可在 VPN 未连接时使用。首页需要可解析到具体节点的选择；自动组还没有实际选择时，可在节点列表直接测成员。存在系统网络才可以请求，不自动安装或启动 VPN。
- 已连接时继续使用扩展内核；未连接时主 App 创建临时单节点 adapter，用同一 HEAD URL、2xx 成功条件、10 秒超时及 unified-delay 口径。独立请求解析节点地址使用系统网络，不加载订阅 DNS、规则、provider 健康检查或 TUN。因此可达性与延迟可能不同于连接后的路径；不是 ICMP、带宽或完整隧道验收。
- 单测/批测共用每节点结果。批量最多三并发，可取消；取消、离开前台或配置变化会释放临时 adapter。未连接的测速不会假计入系统隧道流量。已连接的原有真实字节计数保持不变。
- Nodes 与批测页右侧 Ping 只测该节点，不改选择。点名称使用现有选择逻辑；需要明确策略组时进入策略组页。正在测速时不能切换节点，可以先取消；切换订阅则取消旧测速。
- 结果归属 `订阅 UUID + 源内容摘要`。切换订阅或更新源内容清空数值、时间和状态，迟到回调不能回填；同一订阅内更换节点保留已有结果。选择变化的运行配置 ID 仍用于验证扩展 IPC。
- 跳过证书校验仍须按订阅内容版本明确确认。确认按钮区分“允许并连接”和“允许并测速”；批准测速不会顺带连接 VPN。
- 扩展 IPC 批量沿用 v1，指定节点用 v2；旧扩展会拒绝 v2，不能把单测误执行成全量测速。已连接时需新版主 App 和扩展配套运行。

### 构建与回归

新增 `Configuration/Patches/hako-standalone-probe.patch`，哈希写入 `Core.lock.json`；上游 revision、Go/gomobile 版本不变。先运行 `python3 scripts/build-core.py --build`，再构建 Xcode 工程。独立 adapter 的 unified-delay 用每请求 context 控制，不修改并发请求的全局口径。

已完成：

- iOS 主 App、Packet Tunnel、模拟器构建与包结构/Geo 哈希检查。
- `scripts/check-standalone-core.py`：5 组本地 SOCKS/HTTP 回环检查，验证真实代理路径、第一次/第二次请求计时、超时、取消、失败状态和跨 session 三并发；不连接公共节点。
- `scripts/check-ping-core.py`：原有已连接测速的延迟、并发、取消及实际字节计数回归。
- 模拟器 `ProbeExperienceTests` 5 项，覆盖无 VPN 的单测/批测/首页、结果隔离与晚到回调、同源不同订阅、内容版本变化、证书授权不连接、取消/离线门禁、provider 有效覆写和 IPC 版本保护。只用内存库和本机关闭的端口。
- 同轮证书授权、网络状态、选择策略共 7 项既有模拟器测试通过；选择策略宿主检查 79 项通过。

尚未验证：手机上的真实节点独立测速、已连接状态的新单节点 IPC 端到端请求，以及复杂订阅的真机帧率。本轮未安装手机或改变手机 VPN 状态。

手机体验重点：反复进入导入页/详情页；断开 VPN 后测首页与单个节点；批测中取消并切换订阅；重新进入批测页确认没有旧数值；批测完成后点名称选节点并核对真实选择。


## 2026-10-08：单节点队列与五并发

Nodes 页面单独点击多个节点会追加到同一测速队列；同一轮内重复节点不重复提交，节点各自显示等待/测速/结果。选择多个节点不会标记为“全部节点”测试。全部测速仍使用同一五并发准入规则。

未连接路径使用可动态补充任务的队列；连接路径使用版本 3 的累积节点索引命令，隧道端幂等追加，保留版本 1/2 校验兼容。主 App、隧道调度及 Go 共享原生准入都设为 5。取消、订阅/版本切换仍通过任务 ticket 与运行身份隔离旧结果。核心 patch 校验与 XCFramework 必须同步重建。
