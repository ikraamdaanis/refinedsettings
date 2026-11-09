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
            Section {
                SystemPreferenceToggleRow(
                    title: "Smart quotes",
                    detail: "Turns straight quotes into curly ones as you type.",
                    preference: .smartQuotes,
                    unsetValue: true
                )
                SystemPreferenceToggleRow(
                    title: "Smart dashes",
                    detail: "Turns two hyphens into a long dash as you type. macOS only has one switch for both of these.",
                    preference: .smartDashes,
                    unsetValue: true
                )
            } header: {
                PaneSectionHeader(title: "Text Input", help: "Apps you already have open need reopening. Apps with their own copy of these settings keep it.")
            }
        }
        .paneFormStyle()
        .refreshesSystemPreferences()
    }
}
