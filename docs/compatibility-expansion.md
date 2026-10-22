# 协议与资源导入

## 协议

| 协议 | 契约 |
| --- | --- |
| SS／SS2022 | 已接入 AEAD／2022 密码；严格验证密钥长度和身份链，插件见通用 YAML |
| VMess | UUID、显式 cipher／alterId、UDP、TLS、WS／gRPC 和约定编码 |
| VLESS | TCP／WS／gRPC、TLS／Reality／Vision 和约定 packet-encoding；组合受校验约束 |
| Trojan | 密码、TLS、SNI、ALPN、证书及客户端指纹、TCP／WS／gRPC |
| Hysteria2 | HY2 别名、TLS、Salamander 和约定带宽参数；URI 缺省端口为 443 |
| TUIC | v5 及已接入的 TLS／拥塞和 UDP 参数 |

字段支持不代表所有服务器组合均经真机验证。未接入的密码、传输、插件或额外字段明确拒绝。

## 格式与桌面字段

Clash YAML／JSON、节点 URI、URI 列表与 Base64 列表进入同一校验管线。sing-box／Xray JSON、SIP008、WireGuard／OpenVPN／其他客户端格式和 HTML 错误页会被识别并说明，不猜测转换。

桌面控制器、Dashboard、监听端口、profile 持久化提示和显示元数据按约定适配，原文保留；不下载管理页面或开放桌面端口。进程识别仅接受关闭值。

## 自动组与资源

select、url-test、fallback、load-balance 可组合内联节点和 provider。自动组显示真实运行选择；没有运行结果时不把首节点冒充自动结果。默认健康检查地址为 `https://cp.cloudflare.com/generate_204`，默认 interval 300 秒、lazy true、timeout 5000 ms；正数间隔最低 60 秒，适配在报告中说明。

proxy-provider 支持 HTTPS／inline Clash 节点列表。rule-provider 支持 domain／ipcidr／classical；远程格式为 YAML／text，domain／ipcidr 另支持 MRS。classical 不嵌套 RULE-SET、MATCH 或 Geo 规则。

导入或手动刷新先准备全部依赖，校验成功后形成完整候选快照。扩展只读既有快照，使用受保护临时资源；不读取订阅任意指定的本地路径。provider interval 与 Geo 自动更新适配为手动完整刷新，失败保留旧版本。

资源大小、条数和容量见[兼容清单](compatibility.md)。下载策略与回滚见[订阅管理](subscriptions.md)，筛选见[策略契约](selection-policy-compatibility.md)。

验证入口：`check-import-formats.py`、`check-import-qr.py`、`check-compatibility-batches.py`、`check-compatibility-core.py`、`check-target-compatibility.py` 和 `check-target-core.py`。
