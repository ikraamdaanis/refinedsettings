import SwiftUI

/// Appears once a setting has changed that this app only reads when it starts.
struct AppRestartRow: View {
    let app: RestartableApp
    let detail: String
    @ObservedObject private var store = SystemPreferenceStore.shared

    var body: some View {
        if store.needsRestart(app) {
            LabeledContent {
                Button("Restart \(app.name)") {
                    store.restart(app)
                }
            } label: {
                Text("Restart \(app.name) to apply")
                Text(detail)
            }
        }
    }
}
