# 架构

| 部分 | 职责 |
| --- | --- |
| SwiftUI App | 订阅管理、选择、连接控制、显示状态与诊断 |
| Packet Tunnel | 内核生命周期、路由／DNS、物理接口和数据包桥接 |
| Shared | 配置契约、完整资源快照、钥匙串仓库和 IPC 数据结构 |
| Hako／Hako-Adapter | 固定源码内核及 Apple 平台桥接，版本见 Core.lock.json |

连接状态以系统 NEVPNStatus 为准；节点可用性由独立请求检测。App 与扩展通过受限消息交换结构化结果，不开放桌面控制器或 Dashboard。

原始配置、派生运行配置和依赖快照分离。候选配置完成校验和预检后才原子提交；失败保留旧版本。凭据存入共享钥匙串，默认不跨设备同步。

PacketFlow 桥接使用公开接口；内核内部仍有需单独审计的平台 DNS 路径，见[内核构建](core-build.md)。

页面和服务的目录、状态所有权及协作约定见 [AGENTS.md](../AGENTS.md)。原生 macOS 使用独立工程和产物目录，见[适配说明](macos-adaptation.md)。
