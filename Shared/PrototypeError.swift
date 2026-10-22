import Foundation

nonisolated enum PrototypeError: Int, Error, LocalizedError, CaseIterable {
    case invalidFile = 2001, unsupportedShape, unsupportedFields, coreValidation, coreDeviation
    case missingConfiguration, keychain, setup, physicalNetwork, networkSettings, bridge, start, cancelled
    case runtimeShape, deviationReport, invalidPort, coreService, coreStorage, bootstrapUnavailable
    case incompatibleFormat = 2020
    case certificateConsent = 2021
    case resourceDownload = 2022
    var errorDescription: String? { summary }
    var summary: String {
        switch self {
        case .invalidFile: "输入需为不超过 1 MiB 的 UTF-8 YAML、受支持节点链接或 Base64 节点列表，且结构合法。"
        case .incompatibleFormat: "配置格式不兼容或无法识别，请提供 Clash / Mihomo 配置或已支持的节点链接。"
        case .certificateConsent: "此配置包含跳过证书校验的节点，请在 App 中明确确认后再连接。"
        case .resourceDownload: "订阅依赖下载失败，现有订阅未改变；请检查当前网络后重试。"
        case .unsupportedShape: "配置不在已支持范围内，或字段类型、引用有误。"
        case .invalidPort: "节点 port 必须是 1–65535 的整数，或带引号的十进制数字（不含前导零、空格或进制前缀）。未显示原始字段值。"
        case .unsupportedFields: "配置含当前原型未支持的字段，已拒绝导入；现有配置保持不变。"
        case .coreValidation: "内核结构校验失败；为保护凭据，未显示原始错误。"
        case .runtimeShape: "原型生成的运行配置未通过内核结构校验。"
        case .deviationReport: "无法读取内核的配置适配报告，已阻止启用。"
        case .coreDeviation: "内核报告未约定的配置适配，已阻止启用。"
        case .missingConfiguration: "请先导入并确认测试配置；解锁后重试。"
        case .keychain: "无法访问本机钥匙串；请检查共享访问组签名。"
        case .setup: "内核初始化失败。"
        case .coreService: "内核服务创建失败；尚未启动数据转发。"
        case .bootstrapUnavailable: "无法读取启动前的系统 DNS；请断开其他 VPN，确认当前网络可用后重试。"
        case .coreStorage: "无法准备内核的应用内临时目录。"
        case .physicalNetwork: "未找到可用的 Wi-Fi 或蜂窝网络。"
        case .networkSettings: "iOS 隧道路由或 DNS 设置失败。"
        case .bridge: "数据包桥接失败，隧道已停止。"
        case .start: "内核启动失败；请检查固定阶段日志。"
        case .cancelled: "启动已取消。"
        }
    }
    var tunnelError: NSError {
        NSError(domain: TunnelDiagnostics.errorDomain, code: rawValue, userInfo: [NSLocalizedDescriptionKey: summary])
    }
}
