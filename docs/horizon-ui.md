# 界面实现

Horizon 使用黑白线条、Metal 砖墙与地理粒子地球；Classic 使用彩色粒子和深浅色布局。设置可切换风格，两者共用订阅、选择、连接与测速服务。

## 布局与动效

- iPhone 采用主页、节点、设置三个 Tab；iPad 使用原生侧栏，并持续展示真实流量。
- 首页场景、订阅菜单、节点选择和信息区各自保持明确职责。曲线的持续滚动不依赖全页隐式动画。
- 列表按稳定身份更新；切换订阅、加载、数字、符号和按钮尺寸采用局部过渡，不用临时 busy 状态让整页反复变灰。
- iPhone 信息区按滚动位置调节清晰度；iPad 保持自身布局。命中区域不因场景层、滚动或框选而遮住功能操作。
- 减少动态效果、低电量、后台和离页分别管理动画与渲染时钟。

## 场景与资源

渲染位于 `Horizon/Features/Horizon/Rendering/`，SwiftUI／Metal 封装位于 Components。连接画面由真实系统状态驱动；视觉状态不反向修改 VPN。

地球采样来自 Natural Earth，来源与摘要见 [`Configuration/Geography/source.json`](../Configuration/Geography/source.json)，声明见 [`NaturalEarth-NOTICE.txt`](../Horizon/Features/Horizon/Resources/NaturalEarth-NOTICE.txt)。取得固定输入归档后运行 `python3 scripts/build-globe-points.py` 可重建粒子数据。

具体颜色、布局与组件原则见[设计规范](design/Horizon-Design-System.md)，首次流程见[引导说明](first-launch-introduction.md)。构建和逻辑测试用于检查状态与连续性，设备观感及帧率需单独验证。
