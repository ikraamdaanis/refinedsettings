import SwiftUI

/// A time in seconds, from nothing up to two seconds.
struct SystemPreferenceSliderRow: View {
    let title: String
    let detail: String
    let preference: SystemPreference
    let unsetValue: Double
    /// Only the slider turns off, so a value that has already been changed can still be reset.
    var isAdjustable = true
    @ObservedObject private var store = SystemPreferenceStore.shared

    private var valueText: String {
        let seconds = store.double(preference, whenUnset: unsetValue)

        return seconds == 0 ? "None" : String(format: "%.2f s", seconds)
    }

    var body: some View {
        SystemPreferenceRow(title: title, detail: detail, isChanged: store.isChanged(preference), reset: { store.reset(preference) }) {
            Slider(value: store.sliderBinding(for: preference, whenUnset: unsetValue), in: 0...2, step: 0.05)
                .labelsHidden()
                .frame(width: 130)
                .disabled(!isAdjustable)
                .accessibilityLabel(title)
                .accessibilityValue(valueText)
            Text(valueText)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
    }
}
