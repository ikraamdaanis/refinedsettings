import SwiftUI

struct DockSection: View {
    @ObservedObject private var store = SystemPreferenceStore.shared

    private var dockHidesItself: Bool {
        store.bool(.dockAutohide, whenUnset: false)
    }

    var body: some View {
        Section {
            if !dockHidesItself {
                LabeledContent {
                    Button("Open Desktop & Dock…") {
                        AppInfo.openSystemSettings(paneID: "com.apple.Desktop-Settings.extension")
                    }
                } label: {
                    Text("Your Dock doesn't hide itself")
                    Text("These only do something once \"Automatically hide and show the Dock\" is on.")
                }
            }
            Group {
                SystemPreferenceSliderRow(
                    title: "Delay before showing",
                    detail: "How long the pointer rests at the screen edge before the Dock appears.",
                    preference: .dockAutohideDelay,
                    unsetValue: 0.2
                )
                SystemPreferenceSliderRow(
                    title: "Animation time",
                    detail: "How long the Dock takes to slide in and out.",
                    preference: .dockAutohideAnimationTime,
                    unsetValue: 0.5
                )
            }
            .disabled(!dockHidesItself)
            AppRestartRow(app: .dock, detail: "The Dock and Mission Control blink for a moment.")
        } header: {
            PaneSectionHeader(title: "Dock", help: "How quickly the Dock comes back when it's set to hide itself.")
        }
    }
}
