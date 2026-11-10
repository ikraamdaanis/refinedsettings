import SwiftUI

/// A whole number macOS stores with no documented unit, so it's shown as stops between two words rather than as a value.
struct SystemPreferenceStopsSliderRow: View {
    let title: String
    let detail: String
    let preference: SystemPreference
    /// In slider order, from left to right.
    let stops: [Int]
    let unsetValue: Int
    let leadingLabel: String
    let trailingLabel: String
    @ObservedObject private var store = SystemPreferenceStore.shared

    private var position: Binding<Double> {
        store.stopBinding(for: preference, stops: stops, whenUnset: unsetValue)
    }

    var body: some View {
        SystemPreferenceRow(title: title, detail: detail, isChanged: store.isChanged(preference), reset: { store.reset(preference) }) {
            Text(leadingLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
            Slider(value: position, in: 0...Double(stops.count - 1), step: 1)
                .labelsHidden()
                .frame(width: 130)
                .accessibilityLabel(title)
                .accessibilityValue("\(Int(position.wrappedValue) + 1) of \(stops.count)")
            Text(trailingLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)
        }
    }
}
