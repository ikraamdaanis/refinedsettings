import ApplicationServices
import SwiftUI

struct MouseScrollingPane: View {
    @AppStorage(MouseScrollSetting.verticalKey) private var reversesVertically = false
    @AppStorage(MouseScrollSetting.horizontalKey) private var reversesHorizontally = false
    @State private var mouseNames = MouseDevices.connectedNames()
    @State private var hasAccessibilityAccess = AXIsProcessTrusted()

    private var mouseName: String {
        mouseNames.isEmpty ? "None connected" : mouseNames.joined(separator: ", ")
    }

    var body: some View {
        Form {
            Section {
                PaneSummary(pane: .mouseAndScrolling)
            }
            Section {
                LabeledContent {
                    Text(mouseName)
                } label: {
                    Text("Mouse")
                    if mouseNames.isEmpty {
                        Text("You can still change these settings. They apply when you connect a mouse.")
                    }
                }
                Toggle(isOn: requestingAccess($reversesVertically)) {
                    Text("Reverse vertical scrolling")
                    Text("Turn this on if rolling the wheel moves pages the opposite way to what you expect. Your trackpad stays the same.")
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                Toggle(isOn: requestingAccess($reversesHorizontally)) {
                    Text("Reverse horizontal scrolling")
                    Text("The same for sideways scrolling, including a thumb wheel. Your trackpad stays the same.")
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                if (reversesVertically || reversesHorizontally) && !hasAccessibilityAccess {
                    AccessibilityAccessRow(reason: "Refined Settings can't change your mouse's scrolling without it.")
                }
            }
        }
        .paneFormStyle()
        .task {
            // Only while this pane is showing, so a mouse connecting or a grant being made shows up here.
            while !Task.isCancelled {
                mouseNames = MouseDevices.connectedNames()
                hasAccessibilityAccess = AXIsProcessTrusted()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func requestingAccess(_ setting: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { setting.wrappedValue },
            set: { isOn in
                setting.wrappedValue = isOn

                if isOn && !AXIsProcessTrusted() {
                    SafariProfiles.requestAccess()
                }
            }
        )
    }
}
