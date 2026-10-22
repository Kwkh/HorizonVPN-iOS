# 策略组筛选与 provider 覆盖

| 字段 | 行为 |
| --- | --- |
| 组 filter | 筛选自动成员和 use 成员，保留显式 proxies |
| 组 exclude-filter | 排除显式与自动成员 |
| 组 exclude-type | 使用内核类型名，如 Shadowsocks，以竖线分隔 |
| provider filter／exclude-filter | 按改名前名称筛选，保持多表达式顺序 |
| provider exclude-type | 使用 YAML 类型名，如 ss、vmess |
| additional-prefix／additional-suffix／proxy-name | 按内核顺序替换名称并添加前后缀 |
| provider override | 支持约定 udp、证书、带宽、tfo、ip-version 字段；覆盖后逐节点重新验证 |

正则与替换使用固定内核 regexp2。有效成员计算复用内核实现，不用 Foundation 正则近似。provider 快照保留 use 与健康检查，移除已物化的筛选／覆盖，避免重复改名。

规则上限：正则最长 2048 UTF-8 字节、最多 16 段，替换规则最多 16 条；匹配超时 10 ms、单次策略预算 2 秒，均不是实时调度保证。容量见[兼容清单](compatibility.md)。

非法表达式、重名、空 provider／组、循环、引用失效和不适用的覆盖均拒绝。rule-provider 不接受节点 override。skip-cert-verify:true 需要配置版本级授权。

刷新保留仍有效的选择；失效时采用新组首个有效成员并在预览中披露。回滚恢复原版本资源、成员和选择。

验证：`check-selection-policy.py`、`check-selection-core.py` 和 `HorizonTests/SelectionPolicyImportTests.swift`；主机桥接由 `check-configuration.py` 准备。
