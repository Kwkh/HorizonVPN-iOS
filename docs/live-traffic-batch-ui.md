# 测速与流量

## 手动测速

首页、节点行和独立页面均可测试当前节点；批量测试当前订阅的全部节点，支持受控并发、追加单节点、取消和重测，不自动改选节点。

测试采用内核 URL 延迟接口：`http://cp.cloudflare.com/generate_204`，超时 10 秒。unified-delay 使用对应第二次请求口径。它测量 HTTP 响应延迟，不是 ICMP Ping，也不是带宽测试；与其他客户端比较前需对齐节点、网络、目标、超时和计时口径。

没有 VPN 时使用独立 adapter session，不创建隧道、DNS 或监听器。已连接时使用扩展接口；跳过证书校验仍需对应版本授权。队列结果按订阅、内容版本和会话隔离，迟到结果不能覆盖新上下文。

## 真实流量曲线

- 同图绘制上下行，60 秒横轴、90 pt 高度，约 2.5 秒绘图缓冲。固定对数模式上限 10 MiB/s，另有四档线性量程。
- 采用相邻中点二次贝塞尔平滑；普通显示帧平移已有图层。原始数值和累计计数不因图形平滑改变。
- 扩展每秒读取累计字节，保留最近 66 秒、最多 72 条内存采样；前台恢复和 App 冷启动通过 telemetry.history.v1 补取真实历史。
- 会话改变、计数回退、数据过期或采样间隔超过 3.5 秒时重新建立基线；缺失段回零，不制造漏采数据。
- 内核 URLTest 的实际读写计入统计。口径为节点连接应用流字节，不含外层握手、IP 头或重传，不能等同运营商账单。

后台定时器仍受系统调度影响。减少动态效果、低电量和页面可见性分别控制绘制；采样不依赖当前选中的 Tab。

## 验证

相关入口：`check-traffic.swift`、`check-traffic-plot.swift`、`check-traffic-recorder.swift`、`check-ping-core.py`、`check-standalone-core.py`，以及 TelemetryHistoryTests、ProbeExperienceTests、ProbeAdmissionQueueTests。长期后台、锁屏漏采、真实服务互通和设备帧率按[稳定性清单](stability-validation.md)验收。
