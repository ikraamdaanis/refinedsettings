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
                SystemPreferenceStopsSliderRow(
                    title: "Key repeat rate",
                    detail: "How fast a held key repeats. The far right is quicker than System Settings goes.",
                    preference: .keyRepeatRate,
                    stops: [120, 90, 60, 30, 12, 6, 2, 1],
                    unsetValue: 5,
                    leadingLabel: "Slow",
                    trailingLabel: "Fast"
                )
                SystemPreferenceStopsSliderRow(
                    title: "Delay until repeat",
                    detail: "How long you hold a key before it starts repeating. The far right is shorter than System Settings goes.",
                    preference: .keyRepeatDelay,
                    stops: [120, 94, 68, 35, 25, 15, 10],
                    unsetValue: 30,
                    leadingLabel: "Long",
                    trailingLabel: "Short"
                )
            } header: {
                PaneSectionHeader(title: "Key Repeat", help: "Open apps need reopening to pick up the switch. The rate and delay apply after you log out and back in.")
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
