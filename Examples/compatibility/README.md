# 兼容性样例

所有节点、来源和凭据均为虚构值，不可用于真实联网。生成源位于 `Horizon/Support/` 的 CompatibilitySamples、CompatibilityFixture 和 ExtendedCompatibilitySelfCheck；运行 `python3 scripts/check-configuration.py` 校验并生成样例。

样例覆盖已支持协议、节点列表、自动成员、provider 筛选、桌面字段适配、DNS／Geo、关闭项，以及非法字段、空组和失效引用。预期以生成源和对应测试为准；手写的 dns-geoip-fallback.yaml 需由导入管线附加 Geo 资源。

当前支持范围见[兼容清单](../../docs/compatibility.md)。结构校验通过不表示虚构节点可达。
