import AppIntents
import OSLog

struct PingCurrentNodeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Ping current node"
    static var openAppWhenRun: Bool = false
    static var supportedModes: IntentModes { .background }
    static var isDiscoverable: Bool = false

    @Parameter(title: "Session") var sessionID: String
    init() {}
    init(sessionID: String) { self.sessionID = sessionID }

    func perform() async throws -> some IntentResult {
        #if !HORIZON_WIDGET
        Logger(subsystem: "Kenote.Clash", category: "LiveActivityPing")
            .info("Ping intent entered in host process")
        #if DEBUG
        if await LiveActivityPreview.handlePing(sessionID: sessionID) { return .result() }
        #endif
        await LiveActivityPingService.shared.run(sessionID: sessionID)
        #endif
        return .result()
    }
}
