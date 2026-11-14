import AppKit
import SwiftUI

/// Lights up each button and wheel as macOS receives it from a press over the Settings window, and ticks off the ones
/// that have worked. A button that never lights up isn't reaching macOS at all.
struct MouseButtonTester: View {
    private enum Control: Hashable {
        case button(Int)
        case scrollWheel
        case sidewaysScroll
    }

    /// How long a wheel stays lit after its last movement, since a wheel has no release to wait for.
    private static let wheelGlow: Duration = .milliseconds(350)

    @Binding var extraButtons: [Int]
    @State private var litControls = Set<Control>()
    @State private var testedControls = Set<Control>()
    @State private var wheelGlowEnds: [Control: ContinuousClock.Instant] = [:]
    @State private var monitor: Any?

    private var controls: [Control] {
        (0...MouseButtonSetting.forwardButton).map(Control.button)
            + extraButtons.map(Control.button)
            + [.scrollWheel, .sidewaysScroll]
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], spacing: 6) {
            ForEach(controls, id: \.self) { control in
                chip(for: control)
            }
        }
        .padding(.vertical, 2)
        .onAppear(perform: startListening)
        .onDisappear(perform: stopListening)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            setTesting(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            setTesting(false)
        }
    }

    private func chip(for control: Control) -> some View {
        let isLit = litControls.contains(control)
        let isTested = testedControls.contains(control)

        return HStack(spacing: 5) {
            Image(systemName: isTested ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(isLit ? Color.white : isTested ? Color.green : Color.secondary)
            Text(title(of: control))
                .lineLimit(1)
                .foregroundStyle(isLit ? Color.white : isTested ? Color.primary : Color.secondary)
        }
        .font(.callout)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(isLit ? Color.accentColor : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        .animation(.easeOut(duration: 0.12), value: isLit)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isTested ? "Working" : "Not pressed yet")
    }

    private func title(of control: Control) -> String {
        switch control {
        case .button(let number): MouseButtonSetting.name(of: number)
        case .scrollWheel: "Scroll Wheel"
        case .sidewaysScroll: "Side Scroll"
        }
    }

    private func startListening() {
        defer { setTesting(NSApp.isActive) }

        guard monitor == nil else { return }

        let eventTypes: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .scrollWheel]
        // Local monitors run on the main thread, and only see events meant for this app's windows.
        monitor = NSEvent.addLocalMonitorForEvents(matching: eventTypes) { event in
            MainActor.assumeIsolated { record(event) }

            return event
        }
    }

    private func stopListening() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }

        monitor = nil
        setTesting(false)
    }

    /// While the tester is showing in the app in front, buttons skip their new actions, so the tester sees what the
    /// mouse really sends.
    private func setTesting(_ isAppActive: Bool) {
        let isTesting = isAppActive && monitor != nil
        ButtonRemapper.isTesting.withLock { value in value = isTesting }
    }

    private func record(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            press(.button(event.buttonNumber))
            noteExtraButton(event.buttonNumber)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            litControls.remove(.button(event.buttonNumber))
        case .scrollWheel:
            recordScroll(event)
        default:
            break
        }
    }

    /// Only wheels count. A trackpad or Magic Mouse scroll comes with phases, and a wheel's doesn't.
    private func recordScroll(_ event: NSEvent) {
        guard event.phase.isEmpty, event.momentumPhase.isEmpty else { return }
        guard event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 else { return }

        let control: Control = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? .sidewaysScroll : .scrollWheel
        let glowEnd = ContinuousClock.now + Self.wheelGlow
        wheelGlowEnds[control] = glowEnd
        press(control)

        Task {
            try? await Task.sleep(until: glowEnd, clock: .continuous)

            // A later movement keeps it lit for longer.
            guard wheelGlowEnds[control] == glowEnd else { return }

            litControls.remove(control)
        }
    }

    private func press(_ control: Control) {
        litControls.insert(control)
        testedControls.insert(control)
    }

    private func noteExtraButton(_ button: Int) {
        guard button > MouseButtonSetting.forwardButton, !extraButtons.contains(button) else { return }

        MouseButtonSetting.rememberExtraButton(button)
        extraButtons = MouseButtonSetting.extraButtons
    }
}
