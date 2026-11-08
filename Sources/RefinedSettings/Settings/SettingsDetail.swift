import SwiftUI

/// Takes only the pane, so typing in the sidebar search doesn't rebuild the pane showing here.
struct SettingsDetail: View {
    let pane: SettingsPane

    var body: some View {
        switch pane {
        case .general:
            GeneralPane()
        case .links:
            LinksPane()
        case .mouseAndScrolling, .hiddenSettings:
            UnbuiltPane(pane: pane)
        }
    }
}
