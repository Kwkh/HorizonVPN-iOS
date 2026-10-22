# HorizonVPN iOS

使用 SwiftUI 和 Network Extension 构建的 iOS／iPadOS 代理客户端，集成固定版本的 Hako 内核。原生 macOS 适配仍在开发中。

## 功能

- 本地文件、HTTPS 链接和二维码导入；多订阅管理、更新预览与版本回滚。
- 节点与策略组选择、单节点／批量测速、真实流量曲线及网络诊断。
- Horizon／Classic 界面、iPad 布局、灵动岛和系统连接控件。
- 可选的 iCloud 个人订阅同步，默认关闭。

Clash 配置按字段校验并提示适配，不承诺全部 Mihomo／Clash Verge 配置兼容。支持范围见[兼容清单](docs/compatibility.md)。

## 构建

主 App 最低 iOS／iPadOS 26.0。使用具备对应 SDK 的 Xcode；内核和 Go 工具版本由 `Configuration/Core.lock.json` 固定。

```sh
python3 scripts/build-core.py --build
xcodebuild -project Horizon.xcodeproj -scheme Horizon -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath build/iOS CODE_SIGNING_ALLOWED=NO build
python3 scripts/check-bundle.py build/iOS/Build/Products/Debug-iphoneos/Horizon.app
```

真机安装需要配置开发团队、Bundle ID 及对应能力。[构建说明](docs/core-build.md) · [签名与安装](docs/device-validation.md)

## 目录

- `Horizon/`：页面、应用服务和资源。
- `PacketTunnel/`：隧道扩展与数据包桥接。
- `Shared/`：配置、存储、诊断和进程间消息。
- `Configuration/`：工程配置、依赖锁文件与补丁。
- `HorizonTests/`、`HorizonUITests/`、`scripts/`：测试和构建工具。

## 文档与依赖

[文档索引](docs/README.md) · [macOS 适配](docs/macos-adaptation.md)

真实订阅和签名材料不纳入 Git。本机配置受钥匙串保护；开启 iCloud 同步会上传配置、来源链接和凭据，详见[同步范围](docs/icloud-subscription-sync.md)。

Hako／Hako-Adapter 与 GeoData 保留各自的第三方许可。构建会生成 `CoreLicenses`；地球数据来源为 Natural Earth。依赖清单和原始声明随源码或构建产物保留。
