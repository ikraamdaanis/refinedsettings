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
                    Text("The delay and animation only do something once \"Automatically hide and show the Dock\" is on.")
                }
            }
            SystemPreferenceSliderRow(
                title: "Delay before showing",
                detail: "How long the pointer rests at the screen edge before the Dock appears.",
                preference: .dockAutohideDelay,
                unsetValue: 0.2,
                isAdjustable: dockHidesItself
            )
            SystemPreferenceSliderRow(
                title: "Animation time",
                detail: "How long the Dock takes to slide in and out.",
                preference: .dockAutohideAnimationTime,
                unsetValue: 0.5,
                isAdjustable: dockHidesItself
            )
            SystemPreferenceToggleRow(
                title: "Dim icons of hidden apps",
                detail: "Apps hidden with ⌘H look faded in the Dock, so you can tell them apart.",
                preference: .dockDimsHiddenApps,
                unsetValue: false
            )
            SystemPreferenceToggleRow(
                title: "Lock Dock size",
                detail: "Stops the divider being dragged to resize the Dock.",
                preference: .dockLocksSize,
                unsetValue: false
            )
            SystemPreferenceToggleRow(
                title: "Lock Dock items",
                detail: "Stops apps being added, removed or moved in the Dock.",
                preference: .dockLocksItems,
                unsetValue: false
            )
            SystemPreferenceToggleRow(
                title: "Lock Dock position",
                detail: "Stops the Dock being moved to another edge of the screen.",
                preference: .dockLocksPosition,
                unsetValue: false
            )
            AppRestartRow(app: .dock, detail: "The Dock and Mission Control blink for a moment.")
        } header: {
            PaneSectionHeader(title: "Dock", help: "Changes apply when you restart the Dock.")
        }
    }
}
