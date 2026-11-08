import SwiftUI

struct KeyboardPane: View {
    var body: some View {
        Form {
            Section {
                PaneSummary(pane: .keyboard)
            }
            Section {
                SystemPreferenceToggleRow(
                    title: "Hold a key to repeat it",
                    detail: "Holding a letter normally offers accents such as é. With this on the letter repeats, which suits code editors and games.",
                    preference: .pressAndHoldShowsAccents,
                    unsetValue: true,
                    valueWhenOn: false
                )
            } header: {
                PaneSectionHeader(title: "Key Repeat", help: "Apps you already have open need reopening to pick this up.")
            }
        }
        .paneFormStyle()
        .refreshesSystemPreferences()
    }
}
