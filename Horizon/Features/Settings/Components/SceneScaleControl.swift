import SwiftUI

struct SceneScaleControl: View {
    let title: String
    let symbol: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let identifier: String
    @Environment(AppSettings.self) private var settings
    var body: some View {
        VStack(spacing: 12) {
            LabeledContent {
                Text(value.formatted(.number.precision(.fractionLength(1))) + "×")
                    .monospacedDigit().foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            } label: { Label(title, systemImage: symbol) }
            Slider(value: $value, in: range, step: 0.1) {
                Text(title)
            } minimumValueLabel: {
                Text(settings.text("小", "Small")).font(.callout)
            } maximumValueLabel: {
                Text(settings.text("大", "Large")).font(.callout)
            }
            .accessibilityIdentifier(identifier)
            .accessibilityValue(value.formatted(.number.precision(.fractionLength(1))) + "×")
        }.padding(.vertical, 8)
    }
}
