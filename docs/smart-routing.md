# 智能分流

按订阅保存本机分流方案，默认遵循原订阅。启用后保留原规则顺序，在最终代理 MATCH 前补充 `GEOSITE,cn,DIRECT` 和 `GEOIP,CN,DIRECT`，原有明确规则仍优先。

原始配置不改写，选项进入版本化快照，刷新沿用、关闭可恢复；历史和失败恢复使用原有事务。原订阅没有 DNS 时补充受控解析方案：国内／直连使用国内 HTTPS 解析器并显式 DIRECT，其余经末尾代理目标，节点域名由系统 DNS 引导。已有 DNS 策略不覆盖。

缺失资源、规则超限或最终 MATCH 为 DIRECT／REJECT 时拒绝候选，不静默启用。国内 IP 不通过系统 excludedRoutes 绕过，实际选择仍由内核规则决定。

iOS App 预检后生成编译 MRS 缓存，扩展验证源快照、ABI、长度和摘要后加载，避免隧道进程重复编译大型分类。缓存缺失或损坏进入明确失败／恢复路径。

已有真机规则命中、国内外网页与 DNS 出口的专项记录；这些不能代替所有国内应用、视频上传、UDP／IPv6 或长期运行验收。

验证入口：智能分流相关 HorizonTests、固定内核规则／DNS 测试及 `check-configuration.py`。短时连接观测的边界见[网络诊断](node-and-network-diagnostics.md)。
