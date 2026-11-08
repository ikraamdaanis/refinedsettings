import SwiftUI

/// Mouse & Scrolling and Hidden Settings have their place in the sidebar, but no settings yet.
struct UnbuiltPane: View {
    let pane: SettingsPane

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: pane)
            }
            Section {
                Text("These settings aren't available yet.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
