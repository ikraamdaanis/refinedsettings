import ApplicationServices
import Foundation

/// Keeps a tap running exactly while its feature is on and macOS allows it. With the feature off there is no tap
/// and no timer.
@MainActor
final class EventTapSupervisor {
    private let isWanted: () -> Bool
    private let makeTap: @MainActor () -> EventTap
    private var tap: EventTap?
    private var watchdog: Task<Void, Never>?

    init(isWanted: @escaping () -> Bool, makeTap: @escaping @MainActor () -> EventTap) {
        self.isWanted = isWanted
        self.makeTap = makeTap
    }

    func sync() {
        guard isWanted() else {
            watchdog?.cancel()
            watchdog = nil
            removeTap()

            return
        }

        guard watchdog == nil else { return }

        watchdog = Task {
            while !Task.isCancelled {
                await checkAccess()
                // Quickly while waiting for a grant. Once running, this matches LinearMouse's watchdog interval.
                try? await Task.sleep(for: .seconds(tap == nil ? 2 : 10), tolerance: .seconds(1))
            }
        }
    }

    /// An active tap left running after Accessibility is revoked can freeze all input, so losing access removes it at once.
    private func checkAccess() async {
        let isAllowed = AXIsProcessTrusted() ? await Task.detached(priority: .utility) { EventTap.canCreateTap() }.value : false

        guard !Task.isCancelled else { return }

        guard isAllowed else {
            removeTap()

            return
        }

        if let tap {
            tap.enableIfNeeded()

            return
        }

        let newTap = makeTap()

        if newTap.start() {
            tap = newTap
        }
    }

    private func removeTap() {
        tap?.stop()
        tap = nil
    }
}
