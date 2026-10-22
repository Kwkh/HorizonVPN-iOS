import NetworkExtension
import Foundation
import Observation

@MainActor @Observable final class ConnectionCaptureStore {
    private(set) var rows: [CapturedConnection] = []
    private(set) var remaining = 0
    private(set) var busy = false
    private(set) var unavailable = false
    private var ticket = UUID()

    func clearLocal() { ticket = UUID(); rows = []; remaining = 0; busy = false }
    func exchange(_ action: InspectionCommand.Action, tunnel: TunnelController) async {
        guard !busy, tunnel.permitsNetwork, tunnel.status == .connected else { return }
        busy = true
        let ticket = ticket
        defer { if self.ticket == ticket { busy = false } }
        let current = await tunnel.liveSample()
        guard self.ticket == ticket else { return }
        guard let sample = current else { unavailable = true; rows = []; remaining = 0; return }
        let command = InspectionCommand(action: action, requestID: UUID(), sessionID: sample.sessionID, configurationID: sample.configurationID)
        guard let data = try? JSONEncoder().encode(command),
              let bytes = await tunnel.engineMessage(data, limit: 32768), self.ticket == ticket,
              let reply = try? JSONDecoder().decode(InspectionReply.self, from: bytes),
              reply.requestID == command.requestID, reply.sessionID == command.sessionID,
              reply.configurationID == command.configurationID, let values = reply.capture, values.count <= 30 else {
            if self.ticket == ticket { unavailable = true; rows = []; remaining = 0 }
            return
        }
        rows = values; remaining = reply.captureSecondsRemaining ?? 0; unavailable = false
    }
    func poll(_ tunnel: TunnelController) async {
        while !Task.isCancelled {
            await exchange(.capturePoll, tunnel: tunnel)
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
        }
    }
}
