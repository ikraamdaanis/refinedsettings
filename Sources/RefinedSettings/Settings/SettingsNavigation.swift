import AppKit
import SwiftUI

/// The selected pane and its back/forward history, as System Settings keeps them.
@MainActor
final class SettingsNavigation: ObservableObject {
    @Published private(set) var pane: SettingsPane = .general {
        didSet {
            window?.title = pane.title
        }
    }
    /// General's banner is its title, so the toolbar shows General's name only once the banner is out of view.
    @Published var isHeaderVisible = true
    @Published private var backHistory: [SettingsPane] = []
    @Published private var forwardHistory: [SettingsPane] = []

    weak var window: NSWindow?

    var canGoBack: Bool { !backHistory.isEmpty }
    var canGoForward: Bool { !forwardHistory.isEmpty }

    /// Ignores the deselection a sidebar can send, so a pane is always showing.
    var sidebarSelection: Binding<SettingsPane?> {
        Binding(
            get: { self.pane },
            set: { newPane in
                if let newPane {
                    self.select(newPane)
                }
            }
        )
    }

    func goBack() {
        guard let previousPane = backHistory.popLast() else { return }

        forwardHistory.append(pane)
        pane = previousPane
    }

    func goForward() {
        guard let nextPane = forwardHistory.popLast() else { return }

        backHistory.append(pane)
        pane = nextPane
    }

    func select(_ newPane: SettingsPane) {
        guard newPane != pane else { return }

        backHistory.append(pane)
        forwardHistory = []
        pane = newPane
    }
}
