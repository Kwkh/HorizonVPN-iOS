# 配置兼容性

以固定 Hako 内核和本项目字段校验为准。导入报告区分直接支持、需要适配和无法使用；原始输入保留，未知字段或无效引用不会被静默忽略。

| 范围 | 支持内容 |
| --- | --- |
| 输入 | Clash YAML／JSON、节点 URI、URI 列表、Base64 节点列表 |
| 协议 | SS／SS2022、VMess、VLESS、Trojan、Hysteria2、TUIC v5；传输和参数组合需符合字段契约 |
| 模式 | rule；可叠加本机智能分流 |
| 策略组 | select、url-test、fallback、load-balance，以及受限筛选和覆盖 |
| Providers | HTTPS／inline 节点与规则资源；规则支持 domain、ipcidr、classical，指定类型可使用 MRS |
| 规则 | 域名、IP、端口、网络、RULE-SET、GEOIP／GEOSITE 等已接入匹配条件 |
| DNS | fake-ip／redir-host、hosts、受限策略与 fallback、Geo 资源及上游目标引用 |

## 输入上限

主输入 1 MiB，内部快照外壳 2 MiB；最多 512 个节点、64 个组、8192 条主规则、每组 576 个成员。每类 provider 最多 32 项、远程依赖最多 35 项。节点 provider 2 MiB、规则 provider 8 MiB、单项 Geo 32 MiB、依赖合计 64 MiB；domain／ipcidr 规则集最多 20000 条，classical 最多 4096 条。

容量是输入边界，不是真机内存保证。大型配置的运行峰值与协议组合需按实际设备验证。

## 不支持或需适配

不提供桌面 TUN、系统代理、进程识别、脚本、relay、文件 provider、任意跨源跳转及完整 Mihomo 参数集合。桌面监听和管理字段按明确规则省略，iOS 网络接入由 Packet Tunnel 管理。

详细契约：[通用 YAML](general-yaml-compatibility.md) · [协议与资源](compatibility-expansion.md) · [DNS](dns-compatibility.md) · [筛选与覆盖](selection-policy-compatibility.md) · [智能分流](smart-routing.md)
