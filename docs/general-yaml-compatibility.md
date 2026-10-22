# 通用 YAML 契约

所有导入入口共用校验，不按服务商、文件名或节点名称特判。容量上限见[兼容清单](compatibility.md)。

## 结构与默认值

- 节点列表在没有策略组和 rules、且字段属于约定范围时补 select + MATCH；显式 DNS 保留。已有组却缺少规则时拒绝。
- 完整规则可以直接引用节点或内置目标，不强制存在策略组。重复键、重名、循环和失效引用均拒绝。
- `include-all`、`include-all-proxies`、`include-all-providers` 基于完整快照展开；显式成员优先，自动成员按固定顺序收集，空组不降级为 DIRECT。
- `expected-status` 接受合法整数、字符串、范围和 `*`。`dns.listen` 可使用 `:端口` 简写，运行时移除桌面监听。

## 节点参数

支持约定 TCP 协议的 tfo、ip-version、SS UDP-over-TCP、VMess padding／authenticated-length，以及 SS／VMess／VLESS／Trojan 的 smux、yamux、h2mux。smux 服务器能力、字段组合及连接／流数量仍需校验，Brutal 未接入。

SS 插件支持 obfs http／tls 和 v2ray-plugin WebSocket，可选 TLS、host、path、headers、mux 及证书参数。SIP002 参数从 URI、二维码和 Base64 入口导入；未知、重复或无效参数拒绝。跳过证书校验仍需对应配置版本授权。

VMess 的 cipher 和 alterId 均为必填，不自动补 auto／0。HY2 udp:true 适配为原生 UDP，不能用 udp:false 禁用；QUIC 节点不接受 tfo:true。

## 关闭项与等价写法

| 输入 | 处理 |
| --- | --- |
| tun.enable:false、sniffer.enable:false | 省略关闭的桌面功能块 |
| 空 listeners／authentication；空 hosts | 接受并省略；非空 hosts 按 DNS 契约处理 |
| mptcp:false、smux.enabled:false | 保持关闭，省略运行字段 |
| network:'' | 对已支持的传输规范为 TCP；与 WS／gRPC 参数冲突时拒绝 |
| VMess／VLESS packet-encoding:'' | 与省略相同 |

关闭开关必须是布尔 false；字符串、数字、null 或缺少开关不等价。原文和适配报告保留，关闭项不代表其启用功能可用。

## 验证

先运行 `python3 scripts/check-configuration.py`，再按需运行 `check-general-compatibility.py`、`check-general-core.py`、`check-inactive-compatibility.py`、`check-priority-compatibility.py` 和 `check-priority-core.py`。脚本位于 `scripts/`，使用合成配置；真实服务互通另行验收。
