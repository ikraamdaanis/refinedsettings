import AppKit
import SwiftUI

extension View {
    /// Re-reads on showing and whenever the app comes forward, because System Settings can change these values too.
    @MainActor
    func refreshesSystemPreferences() -> some View {
        onAppear {
            SystemPreferenceStore.shared.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            SystemPreferenceStore.shared.refresh()
        }
    }
}
