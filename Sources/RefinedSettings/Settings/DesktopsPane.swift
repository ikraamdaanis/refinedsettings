import ApplicationServices
import SwiftUI

struct DesktopsPane: View {
    @AppStorage(DesktopCyclingSetting.key) private var isCycling = false
    @State private var shortcuts = DesktopShortcut.loadAll()
    @State private var hasAccessibilityAccess = AXIsProcessTrusted()

    private var isCyclingBinding: Binding<Bool> {
        Binding(
            get: { isCycling },
            set: { isNowCycling in
                isCycling = isNowCycling

                if isNowCycling && !AXIsProcessTrusted() {
                    SafariProfiles.requestAccess()
                }
            }
        )
    }

    /// Uses one of their real shortcuts, because "the shortcut for the desktop you're on" is hard to picture.
    private var cyclingExplanation: String {
        guard let shortcut = shortcuts.first else { return "Pressing the shortcut for the desktop you're on normally does nothing. With this on, each press brings another of its windows to the front." }

        return "On Desktop \(shortcut.desktopNumber), pressing \(shortcut.displayName) normally does nothing. With this on, each press brings another window on that desktop to the front."
    }

    var body: some View {
        Form {
            Section {
                PaneSummary(pane: .desktops)
            }
            Section {
                Toggle(isOn: isCyclingBinding) {
                    Text("Cycle through windows")
                    Text(cyclingExplanation)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                if isCycling && !hasAccessibilityAccess {
                    AccessibilityAccessRow(reason: "Refined Settings can't respond to your shortcuts without it.")
                }
            }
            Section {
                if shortcuts.isEmpty {
                    LabeledContent {
                        Button("Open Keyboard Settings…") {
                            AppInfo.openSystemSettings(paneID: "com.apple.Keyboard-Settings.extension")
                        }
                    } label: {
                        Text("No desktop shortcuts turned on")
                        Text("Under Keyboard Shortcuts > Mission Control, turn on the Switch to Desktop shortcuts. They only appear once you have more than one desktop.")
                    }
                } else {
                    ForEach(shortcuts, id: \.desktopNumber) { shortcut in
                        LabeledContent("Desktop \(shortcut.desktopNumber)", value: shortcut.displayName)
                    }
                }
            } header: {
                PaneSectionHeader(title: "Your Shortcuts", help: "From System Settings > Keyboard > Keyboard Shortcuts > Mission Control. Pressing the shortcut for a different desktop still takes you there.")
            }
        }
        .paneFormStyle()
        .task {
            // Only while this pane is showing, so a changed shortcut or a grant being made shows up here.
            while !Task.isCancelled {
                shortcuts = DesktopShortcut.loadAll()
                hasAccessibilityAccess = AXIsProcessTrusted()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
