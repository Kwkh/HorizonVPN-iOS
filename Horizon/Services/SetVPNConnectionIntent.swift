import AppIntents

struct SetVPNConnectionIntent: SetValueIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Set HORIZON connection"
    static var description = IntentDescription("Connect or disconnect the current HORIZON configuration.")
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Connected") var value: Bool
    init() {}
    init(value: Bool) { self.value = value }
    func perform() async throws -> some IntentResult {
        #if !HORIZON_WIDGET
        do { try await ConnectionWidgetService.shared.setConnected(value) }
        catch ConnectionWidgetService.Failure.setupRequired {
            throw needsToContinueInForegroundError("Open HORIZON to select a configuration and complete VPN setup.")
        }
        #endif
        return .result()
    }
}
