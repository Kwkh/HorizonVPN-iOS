# 原生 macOS 适配

使用独立的 `HorizonMac.xcodeproj`，最低 macOS 26。`Horizon Mac` 为正常入口，`Horizon Mac Offline` 使用虚构数据并禁止 VPN／iCloud。原生 Mac 功能仍需按发布版本和真实配置验收。

## 实现范围

- 原生侧栏、订阅矩阵、文件／链接导入、节点与策略组、测速、诊断和设置。
- 独立 MacVPNController、Data Protection Keychain 和 Packet Tunnel，复用共享配置校验、资源快照及版本事务。
- 菜单栏复用同一配置库和连接控制器，提供状态、连接／断开、订阅与手动组选择。关闭主窗口保留进程；菜单操作仍遵守确认、忙碌及过期状态保护。
- 可选 iCloud 同步复用移动端私有容器和合并逻辑，默认关闭；本机选择与 VPN 独立。
- UIKit、CoreMotion、显示时钟及 AppKit 事件处理按平台分开；Mac 不运行移动端灵动岛。

## 构建

```sh
python3 scripts/build-macos-core.py --build
python3 scripts/build-macos-dynamic-core.py
xcodebuild -project HorizonMac.xcodeproj -scheme 'Horizon Mac' -destination 'platform=macOS,arch=arm64' -derivedDataPath build/Mac CODE_SIGNING_ALLOWED=NO build
```

Mac 锁文件为 `Configuration/MacCore.lock.json`，校验移动基础 lock 和 Mac 增量补丁。产物位于 `.build/macos/`，不替换 iOS SDK。动态封装使用 HakoSymbols.xcframework，输出 HakoDynamic.xcframework，避免 App／扩展重复打包静态内核。

符号流程保留真实 Go 调试信息，生成匹配的 dSYM 后再剥离发布二进制。检查使用 `python3 scripts/check-macos-symbols.py`；归档可追加 `--archive <归档路径>`。旧的已剥离产物无法仅靠 dsymutil 补回调试信息。

## 签名与运行边界

App 与隧道需匹配 Bundle ID、共享钥匙串组、Network Extension 和 App Sandbox 权限；以 `Configuration/Mac/` 及实际签名产物为准。内核的本地 UDP 绑定还需对应网络 server 权限，不能只凭客户端网络权限判断可用。

开发机存在多个副本时，应核对系统实际登记的扩展路径和签名，避免调试产物注册冲突。注册扩展、添加 VPN、切换其他 VPN 或改动 DNS 前需明确授权，不以构建命令自动处理这些系统变更。

## 验证入口

- 内核与配置：`check-macos-core.py`、`check-macos-privacy.py`、`check-macos-library.py`。
- 动态内核与符号：`check-macos-dynamic-runtime.py`、`check-macos-symbols.py`。
- 沙盒与扩展：`check-macos-network-sandbox.py`、`check-macos-extension-preparation.py`。
- 交互与服务：`check-macos-selection-events.py`，以及 scripts 中对应的 cloud-sync、traffic、menu-bar 检查。

已有双架构构建／链接、离线回归、签名与归档记录。Intel 编译不代表 Intel 实机通过，商店校验不代表 VPN 可用。真实节点、DNS、权限、后台、菜单操作和系统升级后的运行情况需分别验收；移动端回归也需独立执行。
