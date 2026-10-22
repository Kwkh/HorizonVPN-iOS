import NetworkExtension
import Foundation
import Observation

@MainActor @Observable final class NetworkInspectionStore {
    private(set) var observing = false
    private(set) var querying = false
    private(set) var rules: [RuleObservation] = []
    private(set) var dns: [DNSStage] = []
    private(set) var message: String?
    @ObservationIgnored private var ruleTask: Task<Void, Never>?
    @ObservationIgnored private var dnsTask: Task<Void, Never>?
    @ObservationIgnored private var ruleTicket = UUID()
    @ObservationIgnored private var dnsTicket = UUID()

    func clearRules() { rules = [] }
    func stopRules(clear: Bool = false) {
        ruleTicket = UUID(); ruleTask?.cancel(); ruleTask = nil; observing = false
        if clear { clearRules() }
    }
    func startRules(_ tunnel: TunnelController) {
        guard !observing, tunnel.permitsNetwork, tunnel.status == .connected else { return }
        let ticket = UUID(); ruleTicket = ticket; observing = true; message = nil; rules = []
        ruleTask = Task {
            let current = await tunnel.liveSample()
            guard ruleTicket == ticket else { return }
            guard let sample = current else { stopRules(); message = "无法获取当前隧道，请重试。"; return }
            while !Task.isCancelled, ruleTicket == ticket {
                let request = InspectionCommand(action: .rules, requestID: UUID(), sessionID: sample.sessionID, configurationID: sample.configurationID)
                guard let reply = await exchange(request, tunnel: tunnel), reply.state == "complete", ruleTicket == ticket else {
                    if ruleTicket == ticket { stopRules(clear: true); message = "会话已改变或快照不可用，已停止记录。" }; return
                }
                let known = Set(rules.map(\.id))
                rules = Array((reply.rules.filter { !known.contains($0.id) } + rules).prefix(60))
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
    func runDNS(_ domain: String, tunnel: TunnelController) {
        guard !querying, !tunnel.isDiagnosingDNS, tunnel.canDiagnoseDNS, tunnel.permitsNetwork else { return }
        let domain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DNSStage.validDomain(domain) else { message = "请输入域名，不包含 URL、路径、端口或凭据；国际域名请使用 Punycode。"; return }
        let ticket = UUID(); dnsTicket = ticket; querying = true; tunnel.isDiagnosingDNS = true; dns = []; message = nil
        dnsTask = Task {
            defer {
                if dnsTicket == ticket { querying = false; tunnel.isDiagnosingDNS = false }
            }
            let current = await tunnel.liveSample()
            guard dnsTicket == ticket else { return }
            guard let sample = current else { message = "无法获取当前隧道。"; return }
            let id = UUID()
            var command = InspectionCommand(action: .dnsStart, requestID: id, sessionID: sample.sessionID,
                configurationID: sample.configurationID, domain: domain)
            let deadline = ContinuousClock.now.advanced(by: .seconds(60))
            while !Task.isCancelled, dnsTicket == ticket, ContinuousClock.now < deadline {
                guard let reply = await exchange(command, tunnel: tunnel), dnsTicket == ticket else {
                    if dnsTicket == ticket { message = "诊断响应失效；请检查隧道状态。" }; return
                }
                if reply.state == "complete" { dns = reply.dns; return }
                guard reply.state == "running" else { message = "内核忙或检查不可用；请稍后重试。"; return }
                command = InspectionCommand(action: .dnsPoll, requestID: id, sessionID: sample.sessionID, configurationID: sample.configurationID)
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            }
            if dnsTicket == ticket { message = "等待超时；内核中已发出的查询仍受内核自身超时限制。" }
        }
    }
    func cancelDNS(_ tunnel: TunnelController) {
        dnsTicket = UUID(); dnsTask?.cancel(); dnsTask = nil; querying = false; tunnel.isDiagnosingDNS = false
        dns = []; message = nil
    }
    private func exchange(_ request: InspectionCommand, tunnel: TunnelController) async -> InspectionReply? {
        guard let data = try? JSONEncoder().encode(request),
              let response = await tunnel.engineMessage(data, limit: 32768),
              let reply = try? JSONDecoder().decode(InspectionReply.self, from: response),
              reply.requestID == request.requestID, reply.sessionID == request.sessionID,
              reply.configurationID == request.configurationID,
              reply.rules.count <= 60, reply.dns.count <= 4 else { return nil }
        return reply
    }
}
