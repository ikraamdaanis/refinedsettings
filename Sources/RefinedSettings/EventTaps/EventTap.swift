import CoreGraphics
import Foundation

private func handleTapEvent(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }

    let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()

    return tap.handle(type, event) ? Unmanaged.passUnretained(event) : nil
}

/// An active event tap on its own thread, for the given event types. `shouldKeepEvent` runs on that thread and
/// returns false to swallow the event. `port` is set once before the thread starts.
final class EventTap: @unchecked Sendable {
    private let location: CGEventTapLocation
    private let eventTypes: [CGEventType]
    private let threadName: String
    private let shouldKeepEvent: @Sendable (CGEventType, CGEvent) -> Bool
    private var port: CFMachPort?
    /// Guards `runLoop` and `isStopped`, which the tap thread and the thread that stops it both use.
    private let lock = NSLock()
    private var runLoop: CFRunLoop?
    private var isStopped = false

    init(
        location: CGEventTapLocation,
        eventTypes: [CGEventType],
        threadName: String,
        shouldKeepEvent: @escaping @Sendable (CGEventType, CGEvent) -> Bool
    ) {
        self.location = location
        self.eventTypes = eventTypes
        self.threadName = threadName
        self.shouldKeepEvent = shouldKeepEvent
    }

    /// Whether macOS will currently allow a tap. Permission APIs can report a stale grant, so this makes a real one.
    static func canCreateTap() -> Bool {
        guard let probe = makePort(location: .cghidEventTap, eventTypes: [.scrollWheel], userInfo: nil) else { return false }

        CGEvent.tapEnable(tap: probe, enable: false)
        CFMachPortInvalidate(probe)

        return true
    }

    private static func makePort(location: CGEventTapLocation, eventTypes: [CGEventType], userInfo: UnsafeMutableRawPointer?) -> CFMachPort? {
        let mask = eventTypes.reduce(CGEventMask(0)) { combined, eventType in combined | CGEventMask(1) << eventType.rawValue }

        return CGEvent.tapCreate(
            tap: location,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: handleTapEvent,
            userInfo: userInfo
        )
    }

    /// False when macOS refuses the tap, which is what happens without Accessibility access.
    func start() -> Bool {
        guard let newPort = Self.makePort(location: location, eventTypes: eventTypes, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }

        port = newPort
        let thread = Thread { [self] in runTapLoop() }
        thread.name = threadName
        thread.qualityOfService = .userInteractive
        thread.start()

        return true
    }

    /// Invalidating the port takes its source off the run loop, but the loop goes on waiting, so it is stopped as
    /// well. Otherwise every stopped tap would leave its thread, and this object, behind.
    func stop() {
        guard let port else { return }

        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        let runLoop = lock.withLock {
            isStopped = true

            return self.runLoop
        }

        guard let runLoop else { return }

        // Queued on the loop, because CFRunLoopStop does nothing to a loop that hasn't started running yet.
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
            CFRunLoopStop(runLoop)
        }
        CFRunLoopWakeUp(runLoop)
    }

    /// macOS can switch a tap off without saying so, for example around sleep.
    func enableIfNeeded() {
        guard let port, !CGEvent.tapIsEnabled(tap: port) else { return }

        CGEvent.tapEnable(tap: port, enable: true)
    }

    private func runTapLoop() {
        // No source means the port is already invalid: the tap was stopped before this thread got going.
        guard let port, let source = CFMachPortCreateRunLoopSource(nil, port, 0) else { return }

        let currentRunLoop: CFRunLoop = CFRunLoopGetCurrent()
        let wasStopped = lock.withLock {
            runLoop = currentRunLoop

            return isStopped
        }

        guard !wasStopped else { return }

        CFRunLoopAddSource(currentRunLoop, source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        // The callback holds this object unretained, so it has to outlive the loop.
        withExtendedLifetime(self) {
            CFRunLoopRun()
        }
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout {
            enableIfNeeded()

            return true
        }

        return eventTypes.contains(type) ? shouldKeepEvent(type, event) : true
    }
}
