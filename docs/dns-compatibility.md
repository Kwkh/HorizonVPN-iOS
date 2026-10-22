# DNS YAML 兼容性增量（2026-10-04）

> 2026-10-06 当前增量：复杂 DNS、SS 插件、节点参数、load-balance 与大订阅边界见 [通用兼容性记录](general-yaml-compatibility.md)。下文历史记录中的旧限制以该增量为准。

本轮保留页面布局，在原有 info 兼容性报告中展示适配。未修改内核版本或二进制；使用已固定 Hako 的 DNS resolver 与 GeoIP 实现。

| 字段 | 当前处理 |
| --- | --- |
| `dns.listen` | 接受 IP:端口、:端口、方括号 IPv6:端口、空字符串；原文保留，运行配置移除桌面监听。iOS 从 Packet Tunnel 接入 DNS，不开放订阅指定端口。info 明示适配。 |
| `dns.prefer-h3: false` | 接受且保留 false。true 明确拒绝，尚未完成 iOS DoH HTTP/3 验证；不是默默降级。 |
| `fallback-filter.geoip: true` + `geoip-code: CN` | 交给内核按 GeoIP 选择主 DNS / fallback 结果，支持 MMDB 与 DAT。国家码接受两位 ASCII 字母并规范为大写。 |
| 省略 fallback-filter / geoip / geoip-code | 有非空 fallback 时沿用内核 true / CN 默认值，写入运行配置并在 info 说明；不是默认关闭 Geo。 |
| `geoip: false` / 没有 fallback | 不为该筛选加载 Geo 依赖；无效字段类型仍拒绝。未启用筛选时从运行配置移除无效用的国家码，避免 DAT 编译多余分类；原文保留。 |

主 DNS 的目标国家结果保留；出现非目标国家结果、混合结果、空结果或上游失败时按固定内核语义回退。私有/回环等地址沿用内核 LAN 例外，不因为国家未知直接触发 GeoIP 回退。已有 domain / ipcidr 筛选仍保留。GeoIP 描述的是 DNS 答案地址分类，不代表代理出口国家或 DNS 无泄漏保证。

只在 DNS 使用 GeoIP、主 rules 没有 GEOIP 时，也会规划、保存并检查完整资源快照。默认来源离线使用已校验的内置数据；自定义来源仍按原 URL 准备，不替换。DAT 校验包含 DNS 所引用分类；缺资源、缺分类、坏文件或编译失败阻止候选版本启用。已有来源 URL、更新、回滚和下载超时策略沿用。

尚未扩展：prefer-h3 true、fallback-filter.geosite、Geo/provider DNS policy、DoQ、上游 URL 附加参数、系统 DNS 标记。无完整 Clash YAML 等价承诺。

## 可重复验证

1. `python3 scripts/check-configuration.py`：建立固定版本主机桥接并执行既有回归。
2. `python3 scripts/check-dns-compatibility.py`：合成配置；验证监听移除、H3 false、错误类型拒绝、显式/默认国家、DNS-only 依赖、离线内置资源、原文保留与 info 结果。生成 `.build/research/dns-{mmdb,dat}/runtime.json`。
3. `python3 scripts/check-dns-core.py`：固定源码 overlay 测试；仅绑定 127.0.0.1 UDP 临时端口。两种 Geo 格式各覆盖 CN、非 CN、混合、LAN、空结果、主上游失败、IPv6 两种国家结果、双方失败。公网上的 IP 只作为合成 DNS 答案，不向这些地址发请求。测试按 service executor 设置运行 Geo 模式；单纯 preflight 会恢复全局状态，不能代替实际 resolver 测试。
4. Xcode `ClashTests/OfflineGeoImportTests`：iOS 模拟器中使用 App 包内真实 Geo 数据完成离线导入、内核预检及旧快照保留。

本轮自动化验证不包含真机隧道联网验收，不改变系统 DNS、代理或 VPN。

语义参考：[Mihomo DNS 配置文档](https://wiki.metacubex.one/config/dns/)；实际执行以本项目固定内核与测试为准。
