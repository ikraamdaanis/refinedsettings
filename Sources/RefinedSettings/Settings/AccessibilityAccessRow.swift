import SwiftUI

/// Says why a feature needs Accessibility access and what happens when you allow it.
struct AccessibilityAccessRow: View {
    let reason: String

    var body: some View {
        LabeledContent {
            Button("Allow Access…") {
                SafariProfiles.requestAccess()
            }
        } label: {
            Text("Accessibility access needed")
            Text("\(reason) macOS will ask you to turn on Refined Settings in Privacy & Security.")
        }
    }
}
