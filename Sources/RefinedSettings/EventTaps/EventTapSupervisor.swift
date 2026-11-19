import ApplicationServices
import Foundation

/// Keeps a tap running exactly while its feature is on and macOS allows it. With the feature off there is no tap
/// and no timer.
@MainActor
final class EventTapSupervisor {
    private let isWanted: () -> Bool
    private let makeTap: @MainActor () -> EventTap
    /// Told each time the tap starts or stops, for work that only makes sense while it runs.
    private let didChangeRunning: @MainActor (Bool) -> Void
    private var tap: EventTap?
    private var watchdog: Task<Void, Never>?

    var isRunning: Bool {
        tap != nil
    }

    init(
        isWanted: @escaping () -> Bool,
        makeTap: @escaping @MainActor () -> EventTap,
        didChangeRunning: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.isWanted = isWanted
        self.makeTap = makeTap
        self.didChangeRunning = didChangeRunning
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
            didChangeRunning(true)
        }
    }

    private func removeTap() {
        guard let tap else { return }

        tap.stop()
        self.tap = nil
        didChangeRunning(false)
    }
}
