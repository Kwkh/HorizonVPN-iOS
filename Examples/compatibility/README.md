# 兼容性固定样例

所有值均为虚构数据；不访问服务器，不由真实订阅复制凭据。
除手写的 `dns-geoip-fallback.yaml`（需要导入管线附加 Geo 快照）外，生成源是 `Clash/Support/CompatibilitySamples.swift` 与 `CompatibilityFixture.swift` / `ExtendedCompatibilitySelfCheck.swift`。
运行 `python3 scripts/check-configuration.py` 校验后重新生成本目录 YAML。

| 文件 | 预期 | 重点 |
| --- | --- | --- |
| extended-protocols.yaml | 需要适配 | 17 个虚构 SS/SS2022、VLESS/VMess/Trojan TCP/WS/gRPC 节点；仅节点模板 |
| dual-protocol.yaml | 支持并明确适配 | HY2 + Salamander、VLESS Reality/Vision、select、fake-ip |
| system-dns.yaml | 需要适配 | 缺失 DNS 时的明确默认与系统引导解析 |
| unsupported-mixed.yaml | 拒绝 | 缺少 cipher 的 SS、TUIC、providers、sniffer、url-test、Geo/RULE-SET 同时展示 |
| unsupported-dns.yaml | 拒绝 | DoQ 与 profile/hosts 同时展示 |
| invalid-reference.yaml | 拒绝 | 多条策略组成员及规则目标失效 |

“支持”表示当前结构／桥接契约通过，不代表这些虚构节点能够联网。
真实新增需求先新增脱敏结构用例，再扩展解析与真机验收；禁止为了导入成功静默丢弃不支持项。

DNS 增量：`desktop-dns-listener.yaml` 验证监听适配与 H3 false；`dns-h3-pending.yaml` 验证 true 明确拒绝；`dns-geoip-fallback.yaml` 通过 App 导入可用，未附 Geo 快照时应拒绝直接运行。`scripts/check-dns-compatibility.py` 覆盖该依赖链；`scripts/check-dns-core.py` 验证真实 DNS 结果选择。

通用增量：`automatic-membership.yaml` 验证自动收集、数字状态码和简写 DNS 监听；`node-bundle-metadata.yaml` 验证附带 IPv6 与显式 DNS 的节点列表，原始 DNS 不被默认模板替换。

新增 `provider-selection-policy.yaml` 与 `empty-filter-result.yaml`：前者展示筛选、批量改名与有效节点覆盖；后者验证空组明确拒绝。协议与字段边界见 `docs/selection-policy-compatibility.md`。均为虚构节点，不可用于实际联网。
