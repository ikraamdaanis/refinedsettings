import SwiftUI

/// Picks what one mouse button does, with a shortcut recorder under it when the button presses a shortcut.
struct MouseButtonRow: View {
    let button: Int
    @Binding var mapping: MouseButtonMapping?

    private var title: String {
        let name = MouseButtonSetting.name(of: button)

        return button > MouseButtonSetting.forwardButton ? name : "\(name) button"
    }

    private var detail: String {
        switch button {
        case MouseButtonSetting.middleButton: "Pressing down on the scroll wheel."
        case MouseButtonSetting.backButton: "The side button nearer your palm. Safari and Finder ignore it unless you pick Back."
        case MouseButtonSetting.forwardButton: "The side button nearer the front. Safari and Finder ignore it unless you pick Forward."
        default: "An extra button the test above picked up."
        }
    }

    private var action: Binding<MouseButtonAction?> {
        Binding(
            get: { mapping?.action },
            set: { newAction in
                mapping = newAction.map { action in MouseButtonMapping(action: action, shortcut: mapping?.shortcut) }
            }
        )
    }

    private var shortcut: Binding<RecordedShortcut?> {
        Binding(
            get: { mapping?.shortcut },
            set: { newShortcut in
                mapping = MouseButtonMapping(action: .keyboardShortcut, shortcut: newShortcut)
            }
        )
    }

    var body: some View {
        LabeledContent {
            Picker(title, selection: action) {
                Text("Default").tag(MouseButtonAction?.none)
                Divider()
                ForEach(MouseButtonAction.allCases, id: \.self) { choice in
                    Text(choice.title).tag(Optional(choice))
                }
            }
            .labelsHidden()
            .fixedSize()
        } label: {
            Text(title)
            Text(detail)
        }
        if mapping?.action == .keyboardShortcut {
            LabeledContent {
                ShortcutRecorder(shortcut: shortcut)
            } label: {
                Text("Shortcut")
                Text("Click, then type the shortcut this button should press.")
            }
        }
    }
}
