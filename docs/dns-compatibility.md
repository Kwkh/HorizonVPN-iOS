# DNS 兼容性

支持 fake-ip／redir-host、显式上游、A／AAAA 设置和约定范围的策略、fallback 与 hosts。

- hosts 接受 IPv4／IPv6 单值或列表，不支持域名别名和系统 hosts。
- nameserver-policy 支持约定域名、GeoSite、domain 类型 RULE-SET 及逗号分隔域名；保留原始策略顺序。
- 上游支持 `#节点/组/DIRECT` 路由引用；节点引导 DNS 禁止引用代理，避免递归。
- `system`／`system://` 派生为连接前的系统 DNS；网络改变后重连刷新。
- fallback-filter 支持 GeoIP 国家筛选、GeoSite 及已有 domain／ipcidr。存在 fallback 且省略 GeoIP 开关／国家时沿用内核 true／CN 默认，并在报告披露。
- `dns.listen` 保留原文，移除运行配置中的桌面监听。`prefer-h3:false` 可用；true、DoQ、任意 URL 参数／接口绑定和 fake-ip-filter 规则模式尚未开放。

Geo 依赖即使只被 DNS 引用，也进入完整快照和分类校验。默认来源可使用固定内置数据；自定义来源不替换。缺文件、分类或校验失败阻止候选启用。

GeoIP 表示 DNS 答案地址分类，不代表代理出口。缓存、解析策略和系统 TUN 入口需要分别测试；配置摘要不能证明实际 DNS 路径或无泄漏。

验证：`check-dns-compatibility.py`、`check-dns-core.py`、`check-priority-compatibility.py`、`check-priority-core.py`，以及 `HorizonTests/OfflineGeoImportTests.swift`。运行顺序以[构建说明](core-build.md)和脚本前置条件为准。
