# Welcome 标题回档参考

[旧版源码](HorizonWelcomeView.pre-stroke.swift.txt)来自提交 `1e77965`，只供参考，不参与编译。SHA-256：`627a0194f33d456ad92626387d02b576aac534add0fd20c1199010d56cac8959`。

该版使用 46 pt ultraLight 系统字形、实际字间空格与 tracking 1.5，通过 NumericText 入场。回退时只提取标题相关实现，不覆盖整页后续改动；同时将依赖 HorizonWelcomeWordmark.completed 的收尾时序接回新的完成事件，否则 Next 无法显示。
