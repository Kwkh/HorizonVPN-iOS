# Welcome 标题回档基准

保存于 2026-10-05。来源 Git 提交 `1e77965afe721ec170fd0e97237a0e4bf1b6a89e`，路径 `Clash/Features/Horizon/HorizonWelcomeView.swift`。

[原版完整源码快照](HorizonWelcomeView.pre-stroke.swift.txt)只作回档参考，未加入 App 编译。SHA-256：`627a0194f33d456ad92626387d02b576aac534add0fd20c1199010d56cac8959`。

## 笔画动画之前的效果

- 标题内容 `H O R I Z O N`（字母之间有实际空格），system / ultraLight / default，46 pt，使用 largeTitle 动态缩放，tracking 1.5。
- 单行，minimumScaleFactor 0.55；隐藏的最终 Text 保留占位，可见 Text 从空格切换为全文。
- 整行 NumericText 入场，与 Welcome to、Here, you can… 每行间隔 0.18 秒，smooth 0.6 秒；减少动态效果时改为短渐显。
- 分割线在标题行开始显示时绘制：白色透明度 0.2、宽 0.5 pt，0.8 秒 easeInOut、延迟 0.12 秒。
- 退场是向左推出并淡出，1.5 秒 timingCurve(0.42, 0, 0.58, 1)，行间错峰 0.04 秒。

## 以后如何只回退标题

请以快照中的标题 `line(...)` 调用和 `line` 函数为准恢复系统字体与 NumericText，不要直接覆盖整份当前页面。当前版的 Next 延后显示、分割线亮度等是后续独立改动，应按用户当时要求保留。

恢复 NumericText 后，必须同时将当前依赖 `HorizonWelcomeWordmark.completed` 的收尾时序接回标题实际入场完成事件；否则 Next 会一直隐藏。当前笔画组件可以在确认不再使用后移除。
