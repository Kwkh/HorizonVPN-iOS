# 内核构建

版本、源码提交、构建标签和补丁 SHA-256 以 [`Core.lock.json`](../Configuration/Core.lock.json) 为准。当前使用 Go 1.26.6、sagernet gomobile/gobind v0.1.13，以及固定的 Hako／Hako-Adapter 源码。

## 命令

```sh
python3 scripts/build-core.py
python3 scripts/build-core.py --build
python3 scripts/check-core-link.py
python3 scripts/check-configuration.py
python3 scripts/check-core-privacy.py
```

第一条准备工具链和源码；`--build` 生成设备 arm64、模拟器 arm64／x86_64 切片。最后三项分别检查 Swift 链接、配置契约和隐私约束。

工具链、源码与缓存位于 `.build/`，产物为 `.build/artifacts/Hako.xcframework`。同目录的 `core-build-manifest.json` 记录构建环境和文件摘要。`GOTOOLCHAIN=local` 阻止隐式升级；脚本拒绝不匹配的检出、补丁或额外源码修改。首次构建需下载公开依赖，保留上游完整源码及 third_party。

## 集成约束

- App 和扩展使用相同固定内核，Adapter 源码按工程引用编入扩展。
- 本地补丁提供临时 Packet Tunnel 服务、私有诊断、选择策略、测速及退出修正。补丁必须通过锁文件校验，不手改缓存副本。
- 关闭原始内核日志、持久缓存及外部控制 socket。桥接仅返回固定类别和数量，原始错误、URL 和配置不进入普通日志。
- PacketFlow 使用公开 API，但 fork 内部包含 `dns_configuration_copy` 等平台 DNS 路径。分发和系统升级前需单独审核其兼容性，不能据 PacketFlow 接口推定整个内核仅使用公开 API。

## 许可与复现

构建生成 `CoreLicenses`，保留 Hako、Adapter、Go、gomobile、模块清单、锁文件及补丁。模块清单可能包含未实际链接的模块；分发前还需核对最终依赖和对应源码义务。

manifest 用于追踪构建输入与产物，不代表已证明字节级可复现。签名安装见[设备说明](device-validation.md)，原生 Mac 产物见[macOS 适配](macos-adaptation.md)。
