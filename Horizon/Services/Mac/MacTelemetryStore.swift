#if os(macOS)
import Foundation
import Observation

@MainActor @Observable final class MacTelemetryStore {
    private(set) var window = TrafficWindow()
    private(set) var sample: LiveTelemetry?
    func collect(vpn: MacVPNController, identity: String) async {
        while !Task.isCancelled {
            if vpn.status == .connected,
               let data = await vpn.message(Data(TelemetryHistory.command.utf8), limit: TelemetryHistory.maximumBytes),
               let history = try? JSONDecoder().decode(TelemetryHistory.self, from: data),
               history.isValid(configurationID: identity, now: ProcessInfo.processInfo.systemUptime) {
                guard !Task.isCancelled else { return }
                if window.restore(history, now: ProcessInfo.processInfo.systemUptime) { sample = history.latest }
            } else if vpn.isIdle { window.baseline(); sample = nil }
            else { window.missedPoll(at: ProcessInfo.processInfo.systemUptime) }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
        }
    }
}
#endif
