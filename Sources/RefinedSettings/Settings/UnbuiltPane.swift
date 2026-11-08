import SwiftUI

/// Hidden Settings has its place in the sidebar, but no settings yet.
struct UnbuiltPane: View {
    let pane: SettingsPane

    var body: some View {
        Form {
            Section {
                PaneSummary(pane: pane)
            }
            Section {
                Text("Nothing to change here yet. These options are coming in a future update, each with a reset button to put things back.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .paneFormStyle()
    }
}
