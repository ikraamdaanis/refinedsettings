import ApplicationServices
import SwiftUI

struct MousePane: View {
    @AppStorage(MouseScrollSetting.verticalKey) private var reversesVertically = false
    @AppStorage(MouseScrollSetting.horizontalKey) private var reversesHorizontally = false
    @AppStorage(MouseButtonSetting.mappingsKey) private var buttonMappingsData = Data()
    @State private var mouseNames = MouseDevices.connectedNames()
    @State private var hasAccessibilityAccess = AXIsProcessTrusted()
    @State private var extraButtons = MouseButtonSetting.extraButtons

    private var remapsAnyButton: Bool {
        MouseButtonSetting.decode(buttonMappingsData).values.contains { mapping in mapping.takesOverButton }
    }

    private var mappableButtons: [Int] {
        [MouseButtonSetting.middleButton, MouseButtonSetting.backButton, MouseButtonSetting.forwardButton] + extraButtons
    }

    private var mouseName: String {
        mouseNames.isEmpty ? "None connected" : mouseNames.joined(separator: ", ")
    }

    var body: some View {
        Form {
            Section {
                PaneSummary(pane: .mouse)
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
            Section {
                LabeledContent {
                    EmptyView()
                } label: {
                    Text("Test your buttons")
                    Text("With the pointer over this window, press each button and turn each wheel. One that never lights up isn't reaching your Mac. Buttons keep their usual job while this window is in front.")
                }
                MouseButtonTester(extraButtons: $extraButtons)
                ForEach(mappableButtons, id: \.self) { button in
                    MouseButtonRow(button: button, mapping: mapping(for: button))
                }
                if remapsAnyButton && !hasAccessibilityAccess {
                    AccessibilityAccessRow(reason: "Refined Settings can't change what your buttons do without it.")
                }
            } header: {
                PaneSectionHeader(title: "Buttons", help: "Choose what each button does. Left and right clicks always stay as they are.")
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

    private func mapping(for button: Int) -> Binding<MouseButtonMapping?> {
        Binding(
            get: { MouseButtonSetting.decode(buttonMappingsData)[button] },
            set: { newMapping in
                var mappings = MouseButtonSetting.decode(buttonMappingsData)
                mappings[button] = newMapping
                buttonMappingsData = MouseButtonSetting.encode(mappings)

                if newMapping != nil && !AXIsProcessTrusted() {
                    SafariProfiles.requestAccess()
                }
            }
        )
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
