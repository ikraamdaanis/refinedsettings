import SwiftUI

struct SystemPreferencePickerRow: View {
    let title: String
    let detail: String
    let preference: SystemPreference
    let unsetValue: String
    let choices: [(storedValue: String, title: String)]
    @ObservedObject private var store = SystemPreferenceStore.shared

    /// Terminal guides and older versions of macOS can leave a value that isn't one of the choices, such as `JPG` where
    /// the choice is `jpg`. Listing it keeps the pop-up from showing blank.
    private var choicesIncludingCurrent: [(storedValue: String, title: String)] {
        let currentValue = store.string(preference, whenUnset: unsetValue)

        guard !choices.contains(where: { choice in choice.storedValue == currentValue }) else { return choices }

        return choices + [(storedValue: currentValue, title: "Other (\(currentValue))")]
    }

    var body: some View {
        SystemPreferenceRow(title: title, detail: detail, isChanged: store.isChanged(preference), reset: { store.reset(preference) }) {
            Picker(title, selection: store.choiceBinding(for: preference, whenUnset: unsetValue)) {
                ForEach(choicesIncludingCurrent, id: \.storedValue) { choice in
                    Text(choice.title).tag(choice.storedValue)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}
