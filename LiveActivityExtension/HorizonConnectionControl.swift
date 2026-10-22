import SwiftUI
import WidgetKit

struct HorizonConnectionControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ConnectionWidgetState.controlKind, provider: Provider()) { value in
            ControlWidgetToggle("Connect", isOn: value, action: SetVPNConnectionIntent()) { isOn in
                Label(isOn ? LocalizedStringKey("Connected") : LocalizedStringKey("Disconnected"), systemImage: "globe.europe.africa")
            }
        }
        .displayName("Connect")
        .description("Connect")
    }
    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }
        func currentValue() async throws -> Bool { ConnectionWidgetState.read().phase.isOn }
    }
}
