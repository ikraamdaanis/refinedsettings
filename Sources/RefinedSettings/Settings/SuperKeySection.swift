import AppKit
import SwiftUI

/// Picks the super key and what it does when tapped on its own.
struct SuperKeySection: View {
    let hasAccessibilityAccess: Bool
    @AppStorage(SuperKeySetting.keyKey) private var keyName: String?
    @AppStorage(SuperKeySetting.tapActionKey) private var tapActionName = SuperKeyTapAction.nothing.rawValue
    @AppStorage(SuperKeySetting.includesShiftKey) private var includesShift = false
    @State private var isCapsLockChangedInSystemSettings = CapsLockRemap.isChangedInSystemSettings()

    private var key: Binding<SuperKeyChoice?> {
        Binding(
            get: { keyName.flatMap(SuperKeyChoice.init(rawValue:)) },
            set: { newKey in
                keyName = newKey?.rawValue

                if newKey != nil && !AXIsProcessTrusted() {
                    SafariProfiles.requestAccess()
                }
            }
        )
    }

    private var tapAction: Binding<SuperKeyTapAction> {
        Binding(
            get: { SuperKeyTapAction(rawValue: tapActionName) ?? .nothing },
            set: { newAction in tapActionName = newAction.rawValue }
        )
    }

    private var symbols: String {
        includesShift ? "⌃⌥⇧⌘" : "⌃⌥⌘"
    }

    private var tapDetail: String {
        if key.wrappedValue == .capsLock && tapAction.wrappedValue != .capsLock {
            return "A quick press without another key. Pick Caps Lock to keep typing in capitals."
        }

        return "A quick press without another key."
    }

    var body: some View {
        Section {
            LabeledContent {
                Picker("Super key", selection: key) {
                    Text("Off").tag(SuperKeyChoice?.none)
                    Divider()
                    ForEach(SuperKeyChoice.allCases, id: \.self) { choice in
                        Text(choice.title).tag(Optional(choice))
                    }
                }
                .labelsHidden()
                .fixedSize()
            } label: {
                Text("Super key")
                Text("Holding it presses \(symbols) together, which apps leave free, so shortcuts made with it never clash with theirs.")
            }
            if key.wrappedValue != nil {
                LabeledContent {
                    Picker("Tapped on its own", selection: tapAction) {
                        ForEach(SuperKeyTapAction.allCases, id: \.self) { action in
                            Text(action.title).tag(action)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                } label: {
                    Text("Tapped on its own")
                    Text(tapDetail)
                }
                Toggle(isOn: $includesShift) {
                    Text("Include Shift")
                    Text("Off leaves ⇧ for you to add, for a second set of shortcuts. macOS keeps a few ⌃⌥⇧⌘ shortcuts for itself.")
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                if key.wrappedValue == .capsLock && isCapsLockChangedInSystemSettings {
                    LabeledContent {
                        Button("Open Keyboard Settings…") {
                            AppInfo.openSystemSettings(paneID: "com.apple.Keyboard-Settings.extension")
                        }
                    } label: {
                        Text("Caps Lock is changed in System Settings")
                        Text("Under Keyboard Shortcuts > Modifier Keys, set Caps Lock back to Caps Lock for each keyboard. macOS applies that first, so the super key never sees it.")
                    }
                }
                if !hasAccessibilityAccess {
                    AccessibilityAccessRow(reason: "Refined Settings can't turn a key into the super key without it.")
                }
            }
        } header: {
            PaneSectionHeader(title: "Super Key", help: "Turn a key you rarely use into one that holds several modifiers at once. Use it for the app shortcuts below, or in any app that lets you record a shortcut.")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isCapsLockChangedInSystemSettings = CapsLockRemap.isChangedInSystemSettings()
        }
    }
}
