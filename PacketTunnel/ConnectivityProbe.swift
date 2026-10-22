import Foundation
import Hako
import OSLog

enum ConnectivityProbe {
    static func run(nodeName: String) -> ConnectivityReport {
        let logger = Logger(subsystem: "Kenote.Clash.PacketTunnel", category: "probe")
        logger.notice("phase2.probe.node-begin")
        let raw = HakoPrivateNodeProbeJSON(nodeName)
        let result = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any]
        let bootstrap = ConnectivityReport.safeProbeStatus(result?["bootstrap"] as? String)
        let node = ConnectivityReport.safeProbeStatus(result?["https"] as? String)
        let delay = (result?["delay"] as? NSNumber)?.int32Value ?? -1
        logger.notice("phase2.probe.node-end bootstrap=\(bootstrap, privacy: .public) https=\(node, privacy: .public)")
        logger.notice("phase2.probe.dns-begin")
        let dns = ConnectivityReport.DNSOutcome.decode(HakoDNSQueryJSON("ping0.cc", "A"))
        logger.notice("phase2.probe.dns-end result=\(dns.rawValue, privacy: .public)")
        return ConnectivityReport(nodeHTTPSMilliseconds: delay, dns: dns, bootstrap: bootstrap, nodeFailure: node)
    }
}
