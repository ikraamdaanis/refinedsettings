import SwiftUI

/// A title and explanation on the left; on the right the control, with a reset button once the setting has been changed.
struct SystemPreferenceRow<Control: View>: View {
    let title: String
    let detail: String
    let isChanged: Bool
    let reset: () -> Void
    @ViewBuilder let control: Control

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                if isChanged {
                    Button(action: reset) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Reset to macOS default")
                    .accessibilityLabel("Reset \(title) to macOS default")
                }
                control
            }
        } label: {
            Text(title)
            Text(detail)
        }
    }
}
