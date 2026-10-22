# 策略组与 provider 筛选兼容性（2026-10-04）

> 2026-10-06 当前增量：复杂 DNS、SS 插件、节点参数、load-balance 与大订阅边界见 [通用兼容性记录](general-yaml-compatibility.md)。下文历史记录中的旧限制以该增量为准。

适用于受支持的 Clash YAML／JSON 配置及 HTTPS／inline proxy-provider，不按订阅域名、供应商、节点名或文件名特判。页面布局不变，适配说明与错误沿用现有 info。

## 新增支持

| 字段 | 行为 |
|---|---|
| 组 `filter` | 筛选 include-all-proxies 自动成员与 `use` 引用的 provider 成员；显式 `proxies` 保留，遵循固定内核语义。 |
| 组 `exclude-filter` | 对显式和自动成员都进行排除。 |
| 组 `exclude-type` | 按内核适配器类型名、不区分大小写排除，以 `\|` 分隔。例如 `Shadowsocks`，并非节点 YAML 中的 `ss`。 |
| provider `filter` / `exclude-filter` | 按改名前的名称筛选，保留反引号分隔表达式的顺序。 |
| provider `exclude-type` | 按原始 YAML 类型名、不区分大小写排除，例如 `ss\|vmess`。与组字段的类型命名不同。 |
| provider `override.additional-prefix` / `additional-suffix` | 批量增加前后缀，参与后续组筛选、引用、显示、选择和差异比较。 |
| provider `override.proxy-name` | 支持 pattern / target 列表，使用固定 regexp2 的替换语法；替换后再加前后缀。 |
| provider `override.udp` / `skip-cert-verify` | 布尔覆盖；覆盖后的节点重新经过协议契约检查。有效的 skip-cert-verify:true 仍触发对应配置版本的证书风险确认。 |
| provider `override.up` / `down` | 数值／字符串带宽覆盖，数值规范为内核字符串，用于已支持这些字段的 Hysteria2 节点；不适用的协议组合明确拒绝。 |

覆盖字段必须适用于该 provider 筛选后留下的所有节点。例如当前 HY2／TUIC 不接受通用 `udp` 字段，SS 不接受 TLS 证书字段；不会因为内核能忽略字段就声称生效。`tfo`、`mptcp`、`udp-over-tcp`、`dialer-proxy`、`interface-name`、`routing-mark`、`ip-version`、`name-cert-verify`、`override-expr` 尚未开放。rule-provider 不接受节点筛选或 override。

## 与固定内核保持一致

- `Configuration/Core.lock.json` 固定源码及本地补丁 SHA-256；新增 `hako-selection-policy.patch` 一并进入构建许可证包。
- 正则使用该内核的 regexp2，而非 Foundation 正则；支持前后查找、内联标志、反引号多表达式、捕获组替换。
- 组成员计算直接复用 `GroupBase.GetProxies`，用纯名称／类型的内存描述对象代替真实节点，不启动网络或健康检查。
- provider 快照投影沿用固定 `NewProxiesParser` 的筛选／去重／修改顺序，并直接调用同一个 `overrideSchema.Apply`。多表达式与改名叠加时，后续表达式可能匹配已改名的映射，行为通过原生 parser 对照测试约束。
- `include-all-proxies` 按 UTF-8 排序的名称优先遍历；provider 按表达式优先遍历。多 provider、多表达式时的全局重排仍由内核完成。自动收集不重复加入已有显式节点，沿用已披露的去重适配。
- provider 的运行快照保留 `use` 与健康检查，仅移除已物化的 provider 筛选／override，避免重复改名或覆盖。原文和资源快照不改写，更新与回滚重新计算。
- App 列出的组成员、可选项与运行内核保持一致。更新保留仍有效的选择；消失的选择采用新组的第一个有效成员，更新差异会标记有效组成员变化；更新仍需既有预览确认。回滚恢复原版本的成员和选择。

## 边界与安全

- 原始单个 provider 最多 128 节点，完整有效配置仍最多 128 节点、32 组、4096 主规则，未在本轮放宽。
- 正则最长 2048 UTF-8 字节、最多 16 段；替换规则最多 16 条。匹配设置 10 ms 超时（受 regexp2 定时器检查粒度影响，不是实时保证），一次策略操作设 2 秒预算；失败明确拒绝，不能作为普通“不匹配”静默继续。
- 无效表达式、原始／改名后重名、空 provider、空组、失效引用、循环或原生预检失败，均阻止采用候选配置。空组不会降级为 DIRECT。
- 覆盖后的有效节点决定证书风险计数，导入不表示已授权使用。原始 URL、节点密码与改名内容不进入诊断；桥接仅以内存传递，主机回归经管道传递。
- 未扩展 load-balance/relay、脚本、桌面 TUN、进程识别、DNS Geo/RULE-SET policy 或新协议组合。

## 可重复验证

```sh
python3 scripts/build-core.py --build
python3 scripts/check-configuration.py
python3 scripts/check-selection-policy.py
python3 scripts/check-selection-core.py
python3 scripts/check-general-compatibility.py
```

主机测试使用虚构节点；native 对照分别解析 App 派生配置和保留原生筛选／override 的配置，比较实际成员与顺序，并对 select 组逐一执行 Set / Now。另有 iOS `SelectionPolicyImportTests`，验证原生预检、模拟 HTTPS 资源快照、证书确认、刷新、回滚和错误拒绝。均不拨号访问真实节点；真机联网与长期运行仍需后续验收。

## 本轮实际结果

- 主机新增策略用例 79 项通过，14 组原生配置／派生配置对照通过；比较成员、顺序、provider 节点类型和 UDP 能力，并逐项验证 select 切换。
- 原有基础 141、通用 YAML 69、格式 84、DNS 49、兼容批次／维护 53 项检查通过。
- iOS 模拟器 6 项导入／维护测试通过（本轮 4 项、已有通用 2 项），包含实际 Hako 预检。
- 固定内核框架重建成功；主 App 与 Packet Tunnel 扩展的 iOS 无签名构建及包结构／Geo 数据校验通过。
- 未安装到 iPhone、未改变 VPN 状态，未使用真实节点测量连接、健康检查或长期运行；这些仍需真机验证。
