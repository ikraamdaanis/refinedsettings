import SwiftUI

struct ScreenshotsPane: View {
    var body: some View {
        Form {
            Section {
                PaneSummary(pane: .screenshots)
            }
            Section {
                SystemPreferencePickerRow(
                    title: "File format",
                    detail: "JPG and HEIC make smaller files. PNG keeps every detail.",
                    preference: .screenshotFormat,
                    unsetValue: "png",
                    choices: [
                        (storedValue: "png", title: "PNG"),
                        (storedValue: "jpg", title: "JPG"),
                        (storedValue: "heic", title: "HEIC"),
                        (storedValue: "pdf", title: "PDF"),
                        (storedValue: "tiff", title: "TIFF"),
                    ]
                )
                SystemPreferenceToggleRow(
                    title: "Window shadow",
                    detail: "Adds the soft shadow around a single window you capture. Turn it off for tighter images.",
                    preference: .screenshotDisablesShadow,
                    unsetValue: false,
                    valueWhenOn: false
                )
                SystemPreferenceToggleRow(
                    title: "Date and time in file name",
                    detail: "Turn it off for shorter names such as Screenshot.png and Screenshot 1.png.",
                    preference: .screenshotIncludesDate,
                    unsetValue: true
                )
                ScreenshotNameRow()
            } header: {
                PaneSectionHeader(title: "Saved Images", help: "These apply from your next screenshot.")
            }
        }
        .paneFormStyle()
        .refreshesSystemPreferences()
    }
}
