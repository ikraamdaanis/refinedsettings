import SwiftUI

struct SystemPreferenceToggleRow: View {
    let title: String
    let detail: String
    let preference: SystemPreference
    let unsetValue: Bool
    var valueWhenOn = true
    @ObservedObject private var store = SystemPreferenceStore.shared

    var body: some View {
        SystemPreferenceRow(title: title, detail: detail, isChanged: store.isChanged(preference), reset: { store.reset(preference) }) {
            Toggle(title, isOn: store.switchBinding(for: preference, whenUnset: unsetValue, valueWhenOn: valueWhenOn))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }
}
