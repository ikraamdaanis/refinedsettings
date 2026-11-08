# Mouse & Scrolling module: research notes

Research date: 2026-11-08. Target: Refined Settings, SwiftPM, Swift 6.x, AppKit + SwiftUI, deployment target macOS 13, dev machine macOS 26.5.2 (25F84) on Apple Silicon.

Sources are linked inline and collected at the end. Anything marked **unverified** could not be confirmed from source code, Apple headers, or a first-hand report.

---

## 1. Summary of recommendations

1. **One active tap on its own thread.** Create a single `CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap, ...)` for `scrollWheel`, `otherMouseDown` and `otherMouseUp` only. Attach it to a dedicated `Thread` that runs its own `CFRunLoop`, not the main run loop. This is what LinearMouse does today (`EventThread.swift`, PR #1148). Never include `mouseMoved`/`*Dragged` in v1, since they fire constantly. LinearMouse moved motion events into a second tap that is switched off unless a feature needs it (PR #1412). Don't include keyboard events either: modifiers can be read from `event.flags` on the scroll or button event.
2. **Find the device per event from the embedded IOHIDEvent's sender ID.** Use `IOHIDEventGetSenderID(CGEventCopyIOHIDEvent(event))`, a private SPI that LinearMouse, Scroll Reverser and Mac Mouse Fix all use. Look the sender ID up in a snapshot built off the hot path. Classify a device as a trackpad when `HIDScrollAccelerationType == "HIDTrackpadScrollAcceleration"`, when it conforms to Digitizer/TouchPad usage, or when the `AppleMultitouchTrackpadHIDEventDriver` class is present. The Magic Mouse is a **mouse**, even though its events are continuous with phases like a trackpad. `scrollWheelEventIsContinuous` and the scroll and momentum phases are only a fallback heuristic for events that carry no HID event, and they get the Magic Mouse and Logitech smooth scrolling wrong.
3. **To reverse, negate every representation of the delta**: `DeltaAxis1/2` (lines), `PointDeltaAxis1/2`, `FixedPtDeltaAxis1/2` **and** the embedded IOHIDEvent's `ScrollX/ScrollY` floats. WebKit (Safari, and every WKWebView app) reads the IOHIDEvent to decide the momentum direction. Without that last step, trackpad and Magic Mouse scrolling "snaps back" (Scroll Reverser #136, fixed by lujjjh). Reverse momentum-phase events too.
4. **Linear scrolling** applies only to discrete wheel events (`isContinuous == 0`, no phases). Set `isContinuous = 0`, `DeltaAxis1 = signum * lines` (and the same for axis 2), zero the other axis, and let macOS recompute the point deltas. Drop momentum-phase events for that device instead of rewriting them (LinearMouse returns `nil`). Leave trackpads and the Magic Mouse alone by default.
5. **Back/forward**: on `otherMouseDown` with `mouseEventButtonNumber` 3 or 4, post ⌘[ or ⌘] (key codes 0x21 and 0x1E) to `.cgSessionEventTap`, and swallow both the down and the matching up (`return nil`). Tag synthetic events through `eventSourceUserData` so the tap can ignore them. Keep the alternative in mind: several tools simulate a navigation swipe instead because ⌘[ "only works in a small number of apps" (SensibleSideButtons). But synthesized gestures broke on macOS 27 for Mac Mouse Fix, so ⌘[ is the safer v1 default. Consider passing buttons 4/5 through unchanged for apps that already handle them, like Chromium browsers.
6. **Pointer acceleration off and pointer speed**: set per-service HID properties with `IOHIDServiceClientSetProperty`. `IOHIDServiceClientSetProperty`, `IOHIDServiceClientCopyProperty` and `IOHIDEventSystemClientCreateSimpleClient` are in the public SDK headers on this machine. On macOS 14+, set `HIDUseLinearScalingMouseAcceleration = 1` (`kIOHIDUseLinearScalingMouseAccelerationKey`, public). In linear mode, the `HIDMouseAcceleration` IOFixed value behaves as the "tracking speed" multiplier. On macOS 13, LinearMouse writes acceleration `-1` (IOFixed `-65536`), which disables acceleration and sensitivity. Restore the original values on quit or disable, and re-apply when a device is added or when WindowServer rewrites the properties. Pointer speed has little or no effect on Apple trackpads and the Magic Mouse on Sequoia/Tahoe (LinearMouse #1004, #1003).
7. **Permissions**: an active tap needs **Accessibility**. In TCC terms that is `kTCCServicePostEvent`, a service shown under Accessibility, now called "Device Control and Data Access" on macOS 27. Input Monitoring is not needed for a mouse/scroll active tap. Check with `AXIsProcessTrusted()` plus `IOHIDCheckAccess(kIOHIDRequestTypePostEvent)`, since both AX and CG preflight can report stale grants. While the onboarding UI is visible, poll every 1 s, using the `com.apple.accessibility.api` distributed notification only as a hint. After a fresh grant, plan for one app relaunch, as LinearMouse does. While running, add a watchdog that probes with a throwaway active tap every ~10 s, because revoking Accessibility while an active tap exists can hang **all** system input (Apple forums thread 844416, reproduced on Sequoia, Tahoe and 27).
8. **Signing**: always sign dev builds with the **same** Apple Development identity. An ad-hoc designated requirement is a bare `cdhash` (verified locally), so each rebuild is a new identity to TCC. This Mac has **two** Apple Development identities, and `build.sh` picks "the first", so pin one explicitly with `LINKGUIDE_SIGN_IDENTITY` or a SHA-1.
9. **Swift 6**: write the C callback as a file-scope (or `nonisolated static`) function that captures nothing. Pass the owner as `Unmanaged.passUnretained(self).toOpaque()` and keep the owner alive for the tap's lifetime. The owner is a non-actor `final class ...: @unchecked Sendable` whose mutable state is touched only on the tap thread. Settings and device snapshots cross threads through `OSAllocatedUnfairLock`, which is available on macOS 13. `Mutex` needs macOS 15, so it is out.
10. **Licensing**: copy from LinearMouse (MIT) and Scroll Reverser (Apache-2.0) with notices. Only *learn from* Mos (CC BY-NC 4.0), UnnaturalScrollWheels (GPL-3.0), SensibleSideButtons (GPL-2.0) and Mac Mouse Fix (custom MMF License). LinearMouse itself contains adapted third-party code (PermissionFlow, Mac Mouse Fix v2 (MIT), libinput, yabai, and an Apple-BSD header from WebKit). If we copy one of those parts, we carry its notice too.

---

## 2. LinearMouse internals (question 1)

Repo: https://github.com/linearmouse/linearmouse (main branch, latest release v0.12.0 on 2026-10-03, with betas up to v0.13.0-beta.6 on 2026-11-06). Every source file carries the header `// MIT License` and `// Copyright (c) 2021-2026 LinearMouse`.

### 2.1 Tap setup

File: [`LinearMouse/EventTap/EventTap.swift`](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/EventTap/EventTap.swift)

- Location `.cghidEventTap`, placement defaults to `.headInsertEventTap`, options `.defaultTap`, run loop source added in `.commonModes`:

```swift
guard let tap = CGEvent.tapCreate(
    tap: .cghidEventTap,
    place: place,
    options: .defaultTap,
    eventsOfInterest: eventsOfInterest,
    callback: callbackInvoker,
    userInfo: Unmanaged.passUnretained(contextHolder).toOpaque()
) else {
    throw EventTapError.failedToCreate
}
```

- The callback is a `static let callbackInvoker: CGEventTapCallBack = { proxy, type, event, refcon in ... }` closure that captures nothing. It recovers a `ContextHolder` (callback plus `Control`) with `Unmanaged<ContextHolder>.fromOpaque(refcon).takeUnretainedValue()`. The holder's lifetime is tied to the returned `ObservationToken` through `withExtendedLifetime(contextHolder) {}` in the teardown block.
- **Return-value ownership:** an unchanged event is returned with `passUnretained`. A different event (a copy) is returned with `passRetained`:

```swift
if event === originalEvent {
    return Unmanaged.passUnretained(event)
}
return Unmanaged.passRetained(event)
```

- **Timeouts:** on `.tapDisabledByTimeout` it calls `CGEvent.tapEnable(tap:enable: control.isEnabled)` straight from the callback. `.tapDisabledByUserInput` is passed through without re-enabling. A **5 s health-check `Timer`** on the same run loop re-enables a tap that is silently disabled, and reports `onInvalidated` when `CFMachPortIsValid` turns false:

```swift
if control.isEnabled, !CGEvent.tapIsEnabled(tap: tap) {
    os_log("EventTap found disabled, re-enabling", log: log, type: .error)
    CGEvent.tapEnable(tap: tap, enable: true)
}
```

- **Teardown:** on the tap's run loop it disables the tap, removes the source, then calls `CFMachPortInvalidate`. Mos documents why the invalidate matters (see 3.1).

File: [`LinearMouse/EventTap/EventThread.swift`](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/EventTap/EventThread.swift)

- This is a dedicated `Thread` named `com.linearmouse.event-thread` with `qualityOfService = .userInteractive`. It adds a dummy `Port()` to keep the run loop alive, then calls `CFRunLoopRun()`. Work is handed over with `CFRunLoopPerformBlock` plus `CFRunLoopWakeUp`, and there is a `performAndWait` using a semaphore. The doc comment reads: "All event transformer state access (transform, tick, deactivate) must happen on this thread."
- PR [#1148](https://github.com/linearmouse/linearmouse/pull/1148) "Keep mouse event handling off the main thread" explains the reasoning: centralising mutable event state on one background thread avoids "spreading locks and cross-thread state management across individual transformers."

File: [`LinearMouse/EventTap/GlobalEventTap.swift`](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/EventTap/GlobalEventTap.swift)

- There are two taps: one for everything except motion, and one for `[.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]`. The motion tap starts disabled and is only enabled when a feature needs it (PR #1412, "Reduce CPU overhead from pointer motion events").
- The event mask is `EventType.all` ([`EventType.swift`](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/EventTap/EventType.swift)): `scrollWheel`, left/right/other down, up and dragged, plus `keyDown`, `keyUp` and `flagsChanged`.
- Startup goes through [`EventTapRecovery.swift`](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/EventTap/EventTapRecovery.swift): retries at 0.5, 1 and 2 s, then shows a "restart" UI.
- [`GlobalEventTapWatchdog.swift`](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/EventTap/GlobalEventTapWatchdog.swift) probes every 10 s by creating (and immediately invalidating) a real active tap on a utility queue. If the probe fails, it restarts the app. The comment reads: "permission APIs can report a cached grant after access has been revoked."
- [`AppDelegate.swift`](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/AppDelegate.swift) stops the tap on `sessionDidResignActive` and `willSleep`, and starts it again on `sessionDidBecomeActive` and `didWake`.

### 2.2 Transformer pipeline

Files: [`EventTransformer.swift`](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/EventTransformer/EventTransformer.swift), [`EventTransformerManager.swift`](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/EventTransformer/EventTransformerManager.swift)

- `protocol EventTransformer { func transform(_ event: CGEvent, in context: EventTransformerContext) -> CGEvent? }`. `[EventTransformer]` conforms too and folds the event through each stage. A `nil` from any stage swallows the event.
- The manager resolves a **route** for each event: `DeviceManager.shared.deviceFromCGEvent(cgEvent)` plus the target pid (or the pid of the window under the pointer) plus the display. It looks the route up in an LRU cache keyed by `(deviceID, deviceMatcher, process, screen)`. On a cache miss, it matches the config scheme and builds the stage array in this order:
  `ScrollGestureTransformer` → `ReverseScrollingTransformer` → (switch buttons, auto scroll, redirects) → `ButtonMappingTransformer` → Logitech hi-res normaliser → `SmoothedScrollingTransformer` **or** `LinearScrollingHorizontal/VerticalTransformer` → `ScrollingAccelerationSpeedAdjustmentTransformer` → click debouncing → modifier actions → `UniversalBackForwardTransformer` → pointer redirects.
- Synthetic events are tagged by writing a magic value into `.eventSourceUserData` ([`CGEvent+LinearMouseSynthetic.swift`](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/Utilities/CGEvent+LinearMouseSynthetic.swift), `0x534D_4F4F_5448`). Every transformer starts with `if event.isLinearMouseSyntheticEvent { return event }`.
- Synthesized follow-up events are posted to **`.cgSessionEventTap`**, which is downstream of the HID-level tap, so they never re-enter it: `transform(event) { $0.post(tap: .cgSessionEventTap) }`.

### 2.3 Telling a trackpad from a mouse

Files: [`Device/DeviceManager.swift`](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/Device/DeviceManager.swift), [`Device/Device.swift`](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/Device/Device.swift), [`Device/EventDeviceSnapshot.swift`](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/Device/EventDeviceSnapshot.swift)

- Per event:

```swift
func deviceFromCGEvent(_ cgEvent: CGEvent) -> Device? {
    guard ![.flagsChanged, .keyDown, .keyUp].contains(cgEvent.type),
          let ioHIDEvent = CGEventCopyIOHIDEvent(cgEvent) else {
        return eventDeviceSnapshot.device(for: nil)
    }
    return eventDeviceSnapshot.device(for: IOHIDEventGetSenderID(ioHIDEvent))
}
```

- `EventDeviceSnapshot` is a lock-protected `[UInt64: Device]` published from the main thread. If the sender is unknown, it falls back to the **last active device** (marked active from the HID event-system callbacks).
- Category:

```swift
private static func detectCategory(for device: PointerDevice) -> Category {
    if let vendorID = device.vendorID, let productID = device.productID,
       isAppleMagicMouse(vendorID: vendorID, productID: productID) {
        return .mouse
    }
    if device.confirmsTo(kHIDPage_Digitizer, kHIDUsage_Dig_TouchPad) {
        return .trackpad
    }
    return .mouse
}
```

  The constants are Apple vendor IDs `0x004C` and `0x05AC`; Magic Mouse PIDs `0x0269`, `0x030D`; Magic Trackpad `0x0265`, `0x030E`; built-in trackpads `0x0273`, `0x0276`, `0x0278`, `0x0340`. My MacBook's internal keyboard/trackpad is `0x0342` (from `hidutil list`), which is **not** in that list. LinearMouse still classifies it through the Digitizer/TouchPad usage check, so only the "pointer speed limitation" notice misses it.
- LinearMouse does **not** use the scroll phase or `isContinuous` to pick the device. `isContinuous` is only used to decide how to read the deltas (`deltaYSignum` uses the point delta when the event is continuous).
- Device discovery: [`Modules/PointerKit/Sources/PointerKit/PointerDeviceManager.swift`](https://github.com/linearmouse/linearmouse/blob/main/Modules/PointerKit/Sources/PointerKit/PointerDeviceManager.swift) uses private `IOHIDEventSystemClientCreate`, `IOHIDEventSystemClientSetMatchingMultiple` (GenericDesktop Mouse and Pointer usages), `IOHIDEventSystemClientRegisterDeviceMatchingBlock`, `IOHIDEventSystemClientRegisterEventBlock`, and `IOHIDEventSystemClientScheduleWithDispatchQueue(.main)`. The SPI declarations live in [`PointerKitC/include/IOKitSPIMac.h`](https://github.com/linearmouse/linearmouse/blob/main/Modules/PointerKit/Sources/PointerKitC/include/IOKitSPIMac.h), which carries an **Apple BSD licence header** (from WebKit).
- The private CoreGraphics and IOKit symbols are declared in [`LinearMouse-Bridging-Header.h`](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/LinearMouse-Bridging-Header.h): `CGEventCopyIOHIDEvent`, `IOHIDEventGetSenderID`, `IOHIDEventGetType`, `IOHIDEventGetFloatValue` and `IOHIDEventSetFloatValue`, with `kIOHIDEventFieldScrollX = (6 << 16) | 0` and `kIOHIDEventFieldScrollY = (6 << 16) | 1`, all under `CF_IMPLICIT_BRIDGING_ENABLED`.

### 2.4 Reverse scrolling

Files: [`ReverseScrollingTransformer.swift`](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/EventTransformer/ReverseScrollingTransformer.swift), [`EventView/ScrollWheelEventView.swift`](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/EventView/ScrollWheelEventView.swift)

- It builds a 2x4 matrix per event, `[DeltaAxis, FixedPtDeltaAxis, PointDeltaAxis, IOHIDEvent ScrollX/Y]` for each axis, and multiplies it by `diag(±1, ±1)`. The integer line delta is rounded and clamped to at least 1 in magnitude, so a fractional result never becomes 0:

```swift
let normalizedDeltaXY = sign(deltaXY) * max(_simd_round_d2(abs(deltaXY)), [1, 1])
```

- It applies to every scroll event, including scroll-phase and momentum-phase events. The "which device" question is settled by the route, not inside the transformer.

### 2.5 Linear scrolling

Files: [`LinearScrollingVerticalTransformer.swift`](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/EventTransformer/LinearScrollingVerticalTransformer.swift) and its horizontal twin.

```swift
guard view.momentumPhase == .none else {
    return nil
}
...
case let .line(value):
    view.continuous = false
    view.deltaY = Int64(normalizedUnits * value)
    view.deltaX = 0
case let .pixel(value):
    view.continuous = true
    view.deltaYPt = pixelValue
    view.deltaYFixedPt = pixelValue
    view.deltaXPt = 0
    view.deltaXFixedPt = 0
```

- **Line mode** writes only `scrollWheelEventDeltaAxis1` (the integer line count) and sets `isContinuous = 0`. **Pixel mode** sets `isContinuous = 1` and writes `PointDeltaAxis` plus `FixedPtDeltaAxis`. Momentum events are swallowed. For Logitech hi-res wheels it first normalises raw units (`LogitechHighResolutionWheelScrollCounter`).
- Scroll Reverser's comment explains why writing the line delta alone works. When you set `DeltaAxis`, macOS internally recomputes `PointDeltaAxis` (an "8x multiplier") and `FixedPtDeltaAxis` (1x). So you must write the point fields **after** the line field if you want to keep smooth deltas ([MouseTap.m](https://github.com/pilotmoon/Scroll-Reverser/blob/master/MouseTap.m)).

### 2.6 Side buttons and back/forward

File: [`UniversalBackForwardTransformer.swift`](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/EventTransformer/UniversalBackForwardTransformer.swift)

- LinearMouse does **not** send ⌘[ by default. For target bundle IDs matching `com.apple.*`, `com.binarynights.ForkLift*`, `org.mozilla.firefox` and `com.operasoftware.Opera`, it converts `otherMouseDown` of buttons 3/4 into a synthesized **navigation swipe gesture** (`GestureEvent(navigationSwipeSource:direction:)` in [`Modules/GestureKit`](https://github.com/linearmouse/linearmouse/blob/main/Modules/GestureKit/Sources/GestureKit/GestureEvent+NavigationSwipe.swift)) posted to `.cgSessionEventTap`, and swallows the `otherMouseUp`. In every other app, the raw button event passes through, because those apps already handle buttons 4 and 5.

```swift
switch event.type {
case .otherMouseDown:
    break
case .otherMouseUp:
    return nil
default:
    return event
}
```

- A user mapping to a key press (for example ⌘[) goes through `KeySimulator.press(keys:tap: .cgSessionEventTap)` ([`ButtonActionExecutor.swift`](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/EventTransformer/ButtonActionExecutor.swift)). v0.12.0 changed simulated key events to use the HID system state source "to keep input state intact" (PR #1370). The Zoom-shortcut fixes for non-US layouts (PR #1406) show that key-code to character mapping matters.
- Some mice send horizontal scroll (wheel tilt) rather than buttons 4/5; LinearMouse's answer is an explicit mapping ([#1428](https://github.com/linearmouse/linearmouse/issues/1428)).

### 2.7 Pointer acceleration and speed

Files: [`Modules/PointerKit/Sources/PointerKit/PointerDevice.swift`](https://github.com/linearmouse/linearmouse/blob/main/Modules/PointerKit/Sources/PointerKit/PointerDevice.swift), [`IOHIDServiceClient+Property.swift`](https://github.com/linearmouse/linearmouse/blob/main/Modules/PointerKit/Sources/PointerKit/Extensions/IOHIDServiceClient%2BProperty.swift), [`Device/PointerSchemeApplication.swift`](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/Device/PointerSchemeApplication.swift)

- It writes per-service properties with `IOHIDServiceClientSetProperty(client, key, value)`. IOFixed values are `Double * 65536`.
- **Acceleration:** the key is `HIDPointerAccelerationType` if the service reports one (for example `HIDMouseAcceleration` or `HIDTrackpadAcceleration`), and otherwise falls back to `HIDMouseAcceleration`. The range is clamped to 0...40, and `-1` means "acceleration and sensitivity disabled". The fallback default is `0.6875`.
- **Disable acceleration (macOS 14+):** write `HIDUseLinearScalingMouseAcceleration = 1`. The comment reads: "This feature was introduced in macOS Sonoma. In the earlier versions of macOS, this value would be nil." The SDK header documents the key as "WindowServer sets this to true when the user wants linear tracking. Only has an effect if this device uses HIDMouseAcceleration style acceleration" (`IOKit/hid/IOHIDEventServiceKeys.h`). On macOS 13 and earlier, LinearMouse writes acceleration `-1` instead.
- **Speed:** written as `HIDPointerResolution` (IOFixed DPI, clamped 10...1995, lower = faster, fallback 400). Speed in 0...1 maps through `1 / resolution` normalised to `1/1200 ... 1/40`. After changing the resolution, it re-applies the acceleration value "to make resolution take effect".
- **When acceleration is disabled, speed is not applied** (`let speedChanged = !disabled && ...`). The UI then shows a "Tracking speed (0–40)" slider bound to the acceleration value, on macOS 14+ only ([`PointerSettings.swift`](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/UI/PointerSettings/PointerSettings.swift)). In linear mode, `HIDMouseAcceleration` acts as a linear gain, which matches a MacRumors observation that with the Sonoma toggle off, Tracking speed "change[s] the conversion ratio from native DPI to actual DPI".
- It observes property changes for `HIDMouseAcceleration`, `HIDTrackpadAcceleration`, `HIDPointerResolution` and `HIDUseLinearScalingMouseAcceleration`, and re-applies on change, because System Settings or WindowServer can overwrite them. It restores the initial values on teardown.
- The pointer-speed approach credits Mac Mouse Fix v2 (MIT at that revision), see [`ThirdPartyNotices/MacMouseFix.txt`](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/ThirdPartyNotices/MacMouseFix.txt).

### 2.8 Permission handling

File: [`AccessibilityPermission.swift`](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/AccessibilityPermission.swift)

```swift
var enabled: Bool {
    // AX and CG preflight can retain stale grants after a permission is revoked.
    // IOHIDCheckAccess also detects removal of the entry (unknown).
    accessibility && hidPostEvent == kIOHIDAccessTypeGranted
}
```

- `IOHIDCheckAccess` "performs blocking IPC to tccd. Never call it on the event thread."
- The onboarding window polls every 1 s ([`AccessibilityPermissionWindow.swift`](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/UI/AccessibilityPermissionWindow.swift)). On a new grant it calls `Application.restart()` once: "A newly granted AX permission can precede event access in the current process."
- It deliberately does **not** call the request APIs: "Request APIs would also leave a separate system consent alert open alongside our floating guide." It opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` instead.
- macOS 27 renamed the pane: `macOSMajorVersion >= 27 ? "Device Control and Data Access" : "Accessibility"` (PR [#1442](https://github.com/linearmouse/linearmouse/pull/1442)).
- Entitlements: not sandboxed (only `device.bluetooth` and `files.user-selected.read-only`).

---

## 3. Other open-source tools: tricks and pitfalls (question 2)

| Tool | Licence | Tap | Device detection |
| --- | --- | --- | --- |
| LinearMouse | MIT | `.cghidEventTap`, head insert, own thread | IOHIDEvent sender ID → device snapshot |
| Scroll Reverser 2.x | Apache-2.0 | `kCGSessionEventTap`, tail append, main run loop | IOHIDEvent sender ID → IORegistry / HID event system properties |
| Mos | **CC BY-NC 4.0** | `.cgAnnotatedSessionEventTap`, tail append, main run loop | phases / scroll count heuristic (sampled every 3rd event) |
| UnnaturalScrollWheels | **GPL-3.0** | `.cghidEventTap`, tail append, background thread | `isContinuous` (or phases / scroll count) |
| SensibleSideButtons | **GPL-2.0** | `kCGHIDEventTap`, head insert | n/a (buttons only) |
| Mac Mouse Fix 3 | **MMF License** (custom; derived apps must be free and keep MMF's monetisation unless substantially new) | n/a here | IOHIDEvent from CGEvent, "HIDEventGetSendingDevice" |

### 3.1 Mos (https://github.com/Caldis/Mos)

- [`Mos/Utils/Interceptor.swift`](https://github.com/Caldis/Mos/blob/master/Mos/Utils/Interceptor.swift):
  - **Zombie taps:** "CoreGraphics internally holds a reference to the CFMachPort; releasing ours doesn't destroy it. Without `CFMachPortInvalidate`, WindowServer keeps the (disabled) tap registered until the process exits." Recreating the tap after every wake piled these up and slowed system-wide input (Mos #970). Always call `CFMachPortInvalidate`.
  - **Self-lock guard:** if the main thread is blocked (for example by a TCC prompt), the active tap stops responding, the system disables it, and input recovers. A keeper timer that blindly re-enables it freezes input again. Mos caps auto-restarts at 3 per 60 s (`autoRestartLimit = 3`, `autoRestartWindow = 60`).
  - It checks `AXIsProcessTrusted()` every 5 s and stops the tap when access is gone, "to avoid a zombie tap swallowing system events".
- [`ScrollEvent.swift`](https://github.com/Caldis/Mos/blob/master/Mos/ScrollCore/ScrollEvent.swift) treats an event as trackpad when the momentum phase, scroll phase or `scrollWheelEventScrollCount` is non-zero. `ScrollCore.swift` notes that this "can't distinguish the Magic Mouse, because its scroll characteristics match the built-in trackpad". There's a **Logitech Options+ special case**: if the event's source PID is the Logi Options process, it is treated as a mouse even though it has phases. Options+ smooth scrolling posts continuous, phased events from its own process.
- Issues: [#1058](https://github.com/Caldis/Mos/issues/1058) scroll direction inverted on unfocused windows alongside Logi Options+; [#958](https://github.com/Caldis/Mos/issues/958) choppy scrolling or inverted direction after wake on 26.4/26.5 until the app restarts; [#1040](https://github.com/Caldis/Mos/issues/1040) wheel dead after every macOS update until Mos restarts (on 26 and 27); [#826](https://github.com/Caldis/Mos/issues/826) Mos 3.5 broken on 26.2, fixed by reinstalling 4.0 and **re-authorising**; [#655](https://github.com/Caldis/Mos/issues/655) reverse scroll ignored in iPhone Mirroring.

### 3.2 Scroll Reverser (https://github.com/pilotmoon/Scroll-Reverser)

- v2.0 (2026-10-19) dropped the gesture-event tap it used to detect trackpad touches. In 1.x, macOS would stop delivering gesture events after sleep, a display change or a lid close, so the trackpad was mistaken for a mouse and reversed ([#130](https://github.com/pilotmoon/Scroll-Reverser/issues/130), [#193](https://github.com/pilotmoon/Scroll-Reverser/issues/193)). The release notes say: "Only needs Accessibility permission. Input Monitoring permission is no longer required."
- [`ScrollSource.m`](https://github.com/pilotmoon/Scroll-Reverser/blob/master/ScrollSource.m) explains:
  - "The sender of a HID event is the registry entry ID of the HID event service." It is looked up with `IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(senderID))` and cached per sender ("Registry entry IDs are not reused within a boot").
  - "The sender ID is not one of them [identity properties]: it changes on every reconnect and every Universal Control session." For persistent per-device settings it keys on `Product`, `Transport`, `VendorID`, `ProductID`, `SerialNumber` and `HIDScrollAccelerationType`.
  - "Services created in user space, such as the ones Universal Control creates to mirror the other Mac's devices, are not in the IORegistry." Those are found through `IOHIDEventSystemClientCopyServices`. "A new virtual service can send events before the HID event system lists it", so unidentified senders are retried at most every 250 ms.
  - Trackpad test: `HIDScrollAccelerationType == HIDTrackpadScrollAcceleration`, or the service's parent conforms to `AppleMultitouchTrackpadHIDEventDriver`.
  - Events without an IOHIDEvent (posted by apps) are identified by source PID. They default to "Unchanged", because there is no way to know their natural direction.
- [`MouseTap.m`](https://github.com/pilotmoon/Scroll-Reverser/blob/master/MouseTap.m) uses `[NSEvent isDirectionInvertedFromDevice]` to learn whether the system already applied natural scrolling, so the setting can be expressed as "natural/classic" rather than "reverse". It writes the IOHIDEvent `ScrollX/Y` floats as well as the CG fields. For tap-disabled notifications: "Tap-disabled notifications are control messages, not NSEvents. Converting them first throws an exception". So handle `tapDisabledBy*` before `NSEvent(cgEvent:)`.
- **Safari / WebKit momentum snap-back** ([#136](https://github.com/pilotmoon/Scroll-Reverser/issues/136), macOS 12.2+). With trackpads and the Magic Mouse, the reversed scroll "snaps back". lujjjh found that WebKit reads the direction from the embedded IOHIDEvent: "if we convert CGEvent to IOHIDEvent and fix its scrollY field, everything will work fine." Both tools do this now.
- Debug logging is written to a custom buffer because NSLog "would slow down event processing too much" (README).
- iPhone Mirroring takes gestures and lower-level input, so reversal "can't fix" ([#184](https://github.com/pilotmoon/Scroll-Reverser/issues/184)).

### 3.3 UnnaturalScrollWheels (https://github.com/ther0n/UnnaturalScrollWheels)

- [`ScrollInterceptor.swift`](https://github.com/ther0n/UnnaturalScrollWheels/blob/main/UnnaturalScrollWheels/ScrollInterceptor.swift): the tap runs `CFRunLoopRun()` on a `DispatchQueue.global(qos: .userInteractive)` thread. It re-enables on both `tapDisabledBy*` types. On `didWakeNotification` it re-enables immediately and again after 1 s ("The HID subsystem can lag behind wake"). If `tapIsEnabled` stays false, it rebuilds the tap ("the tap was invalidated during standby").
- Its comment on `isContinuous`: "Usually 0 if scroll wheel unless Logitech Options or similar interferes."
- It only writes `scrollWheelEventDeltaAxis1/2`, and relies on macOS recomputing the point deltas.

### 3.4 SensibleSideButtons (https://github.com/archagon/sensible-side-buttons)

- README: "Third-party apps can bind them to ⌘+[ and ⌘+], but this only works in a small number of apps and feels janky." The tool simulates 3-finger swipes instead (`CGEventPost(kCGHIDEventTap, ...)` of gesture events). It runs a `kCGHIDEventTap` / `kCGHeadInsertEventTap` / `kCGEventTapOptionDefault` tap on `kCGEventOtherMouseDown|Up`, maps button numbers **3 → back** and **4 → forward**, triggers on down or up (a user option), and returns `NULL` for both ([`AppDelegate.m`](https://github.com/archagon/sensible-side-buttons/blob/master/SensibleSideButtons/AppDelegate.m)).

### 3.5 Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix), learn only

- The licence is the custom "MMF License". You must make derivation apparent, may not charge, and must keep MMF's licensing/trial/payment code active, unless the work is a "substantial" derivative. **Don't copy code.**
- Ventura: `IOHIDDeviceRegisterInputValueCallback()` broke in betas. MMF used it to map CGEvents to devices, and moved to extracting IOHIDEvents from CGEvents ("CGEventHIDEventBridge", [#297](https://github.com/noah-nuebling/mac-mouse-fix/issues/297)).
- Conflicts with Logi Options+ enabled under Accessibility ([#1239](https://github.com/noah-nuebling/mac-mouse-fix/issues/1239), [#1141](https://github.com/noah-nuebling/mac-mouse-fix/issues/1141)).
- macOS 27: simulated 3-finger swipe gestures stopped working; fixed in [3.1.0](https://github.com/noah-nuebling/mac-mouse-fix/releases/tag/3.1.0), "Gestures ... which rely on simulating 3 finger trackpad swipes work again under macOS 27". Synthesized gestures are an OS-fragile technique.

### 3.6 Consolidated pitfalls

- **Momentum reversal glitches:** fix the IOHIDEvent ScrollX/Y floats (WebKit). For linear mode, drop momentum events from wheel devices rather than rewriting them.
- **Magic Mouse looks like a trackpad:** it sends continuous, phased, momentum events. Use device identity, not event heuristics. LinearMouse's author advises turning linear scrolling off for the Magic Mouse ([SR #136 comment](https://github.com/pilotmoon/Scroll-Reverser/issues/136)).
- **Trackpad and mouse at once:** classify every event by its own sender. Don't flip global state on "last active device" (LinearMouse's 2022 approach flipped `swipescrolldirection` when the active device changed, and lagged). LinearMouse still keeps a last-active fallback for events without a sender.
- **Logitech:** Options+ smooth scrolling turns wheel events into continuous, phased events, some posted from the Options+ process (Mos special-cases its PID). Options+ under Accessibility can override other tools (MMF #1239, Mos #1058). A Logitech receiver merges several devices behind one sender (LinearMouse docs: "A receiver passes on the events of all of its devices together").
- **Karabiner-Elements "Modify events":** it virtualises the mouse, so events come from Karabiner's virtual device and properties written to the physical device do nothing ([LinearMouse #1004 comment](https://github.com/linearmouse/linearmouse/issues/1004)).
- **Apps that bypass or ignore tap changes:** iPhone Mirroring (gestures), Universal Control (on the receiving Mac, events don't pass the local tap, [LinearMouse #106](https://github.com/linearmouse/linearmouse/issues/106)), Screen Sharing and remote desktop (events posted by an app, with no HID sender). Games that read raw HID / GameController mice are probably unaffected by CGEvent edits (**unverified**). Rhino/Grasshopper ask for a per-app pass-through ([LinearMouse #1502](https://github.com/linearmouse/linearmouse/issues/1502)).
- **Sleep/wake and display changes:** re-check and re-enable taps after wake (UnnaturalScrollWheels, Scroll Reverser 1.9.1, LinearMouse lifecycle).

---

## 4. Permissions (question 3)

### 4.1 Which TCC service

- An **active** tap (`.defaultTap`) needs **PostEvent** access, which System Settings shows under **Privacy & Security > Accessibility** (renamed "Device Control and Data Access" on macOS 27). Quinn (Apple DTS): "`PostEvent` access is shown as System Settings > Privacy & Security > Accessibility" ([forum 735204](https://developer.apple.com/forums/thread/735204)). There is first-hand MDM evidence on macOS 27.0.1: with Accessibility allowed but no PostEvent in the PPPC profile, the log reads "Evaluated composed authorization from kTCCServicePostEvent to parent service kTCCServiceAccessibility: Auth:Denied" and `CGEvent.tapCreate(.cghidEventTap, .defaultTap)` returns nil ([LinearMouse #1436](https://github.com/linearmouse/linearmouse/issues/1436)).
- **Input Monitoring** (ListenEvent) is for listen-only access, in particular to keyboard events and to `IOHIDManagerOpen` / `IOHIDDeviceOpen` (SDK `IOHIDLib.h`: "Request to listen to event through IOHIDManager/IOHIDDevice API"). A mouse/scroll active tap doesn't need it (Scroll Reverser 2.0 and LinearMouse only check Accessibility/PostEvent). Whether a *listen-only* tap on mouse events needs any permission at all is **unverified**.
- The SDK header for `CGEventTapCreate` still says "Taps may only be placed at `kCGHIDEventTap` by a process running as the root user". That is outdated: LinearMouse and SensibleSideButtons create `.cghidEventTap` taps as a normal user with Accessibility.
- If we also post ⌘[ keystrokes, that is event synthesis, which is covered by the same PostEvent grant.

### 4.2 The preflight and request functions (SDK `CGEvent.h`, macOS 10.15+)

| Function | Header text |
| --- | --- |
| `CGPreflightListenEventAccess()` | "Checks whether the current process already has event listening access" |
| `CGRequestListenEventAccess()` | "Requests event listening access if absent, potentially prompting" |
| `CGPreflightPostEventAccess()` | "Checks whether the current process already has event synthesizing access" |
| `CGRequestPostEventAccess()` | "Requests event synthesizing access if absent, potentially prompting" |

- Quinn: "If you're using just using `CGEventTap`, there's `CGPreflightListenEventAccess`, `CGRequestListenEventAccess`, `CGPreflightPostEventAccess`, and `CGRequestPostEventAccess`. You only need the Accessibility privilege if you're doing other stuff with Accessibility APIs." ([forum 744440](https://developer.apple.com/forums/thread/744440))
- `IOHIDCheckAccess(kIOHIDRequestTypePostEvent)` (IOKit, public, 10.15+) returns `Granted`, `Denied` or `Unknown`. LinearMouse relies on it because "AX and CG preflight can retain stale grants". It does blocking IPC, so keep it off the tap thread.

### 4.3 Detecting a grant without polling forever

There is no supported notification. What works:

- `DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.accessibility.api"), ...)` fires when the toggle changes. It has no `userInfo`, and it is **not** posted when the app is removed from the list rather than switched off ([forum 735204](https://developer.apple.com/forums/thread/735204)). TCC may not be updated yet when it arrives, so re-check after ~0.5–1 s (the delay is **unverified**). Treat it as a hint.
- Poll `AXIsProcessTrusted()` (cheap, no prompt) every ~1 s **only while** the permission UI is open or the app is in a "waiting for permission" state. LinearMouse and lan-mouse do this; Scroll Reverser polls at 0.333 s for 2.5 s after each click. Stop polling once it is granted.
- After a fresh grant, confirm with a **probe tap** (create an active tap, check it isn't nil, `CFMachPortInvalidate` it). If the probe still fails, relaunch once. LinearMouse: "Restart once after a newly observed accessibility grant, allowing event permissions to take effect even when the current process still reports denied access." Quinn on stale state: "I think the best option there is to accept the quit and relaunch."
- `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` or `CGRequestPostEventAccess()` shows the system alert. LinearMouse avoids it in favour of its own guide plus opening Settings. Whether `tapCreate` itself triggers the alert is **unverified**.

### 4.4 What happens to an existing tap on revocation

- Revoking or deleting the Accessibility record while an active tap exists can make **local keyboard and mouse input stop system-wide**, even with a pass-through callback and no `tapDisabledBy*` callback first. Reported on Sequoia, Tahoe and 27, with WindowServer re-checking PostEvent/ListenEvent and getting denied/unknown ([forum 844416](https://developer.apple.com/forums/thread/844416), FB24619068; Quinn treated it as a bug and asked for a sysdiagnose). An older report says clicks stay blocked until restart ([forum 735204](https://developer.apple.com/forums/thread/735204)).
- `AXIsProcessTrusted()` can keep returning `true` after removal. So use the probe-tap watchdog (LinearMouse, every 10 s, with "Event access probe failed; restarting") plus the `IOHIDCheckAccess` check, and tear down the tap immediately on failure. Mos does `AXIsProcessTrusted()` every 5 s and stops the tap. None of this is guaranteed to prevent the hang; it limits how long it lasts. Document the hang for users ("quit Refined Settings before removing it from Accessibility").

### 4.5 TCC and the code signature

- TCC stores a code requirement (csreq) with each grant. Apple TN3127: the default designated requirement (DR) ensures that "A privilege, like microphone access, acquired by an existing version of your app is still available to a new version", and an Apple Development identity "gets a different DR than a distribution build signed with your Developer ID". It also warns that "the system fails to remember your choices during development" when DRs don't match ([TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)).
- **Ad-hoc** signing gives a cdhash-only DR, so every rebuild is a different identity. I verified this on this Mac: `codesign -s - t; codesign -d -r- t` prints `designated => cdhash H"fc4d385a..."`. The old grant still shows as "on" in System Settings but no longer applies. Fix it by removing and re-adding the app (or the user runs `tccutil reset Accessibility <bundle-id>`; LinearMouse's [ACCESSIBILITY.md](https://github.com/linearmouse/linearmouse/blob/main/ACCESSIBILITY.md) documents exactly this "common macOS bug").
- **Apple Development** signing gives a DR of `identifier "<bundle id>" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: ..." and certificate 1[field.1.2.840.113635.100.6.2.1]`. That form is standard Xcode/codesign behaviour; I didn't sign with the user's identity to print it. It stays stable across rebuilds **as long as the same identity (CN) and bundle ID are used**.
- `security find-identity -v -p codesigning` on this Mac lists **two** Apple Development identities (two different Apple IDs). `build.sh` takes the first match. If the order ever flips, the DR changes and the grant is lost, so pin the identity.
- Keep a stable bundle ID and install path (`/Applications/...`). `build.sh` already does this, and it already kills only the exact process name (`pkill -x`), which is the allowed form.

---

## 5. Swift 6 strict concurrency and performance (question 4)

### 5.1 Callback shape

- `CGEventTapCallBack` is `@convention(c) (CGEventTapProxy, CGEventType, CGEvent, UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>?`. You can pass a **file-scope function** or a **closure literal that captures nothing**. Context goes through `userInfo`.
- Isolation: "An inline closure inside a `@MainActor` method can be inferred main-isolated", and Swift 6's dynamic isolation checks then trap when the tap thread calls it ([hyperwhisper PR #1385](https://github.com/ray-amjad/hyperwhisper-app/pull/1385)). Define the callback at file scope in a type that isn't `@MainActor`. The package is `swift-tools-version:6.0`, so the default isolation is nonisolated. If the package later adopts SE-0466 `defaultIsolation(MainActor.self)` (tools 6.2), mark the callback and the handler `nonisolated` explicitly.
- Re-enabling a tap is a synchronous WindowServer round trip. That PR found it blocked the main thread in `mach_msg` for more than 10 s. That's one more reason to keep the tap and its re-enable calls on the tap thread.

Suggested shape (our code, not copied):

```swift
import CoreGraphics
import Foundation
import os

/// Owns the event tap. All mutable state is confined to `EventTapThread`; settings arrive through locks.
final class MouseEventTap: @unchecked Sendable {
    private let settings: OSAllocatedUnfairLock<MouseSettingsSnapshot>
    private let devices: OSAllocatedUnfairLock<[UInt64: InputDeviceCategory]>
    private var machPort: CFMachPort?

    init(
        settings: OSAllocatedUnfairLock<MouseSettingsSnapshot>,
        devices: OSAllocatedUnfairLock<[UInt64: InputDeviceCategory]>
    ) {
        self.settings = settings
        self.devices = devices
    }

    /// Call on the tap thread only.
    func install(on runLoop: CFRunLoop) -> Bool {
        let mask = [CGEventType.scrollWheel, .otherMouseDown, .otherMouseUp]
            .reduce(CGEventMask(0)) { mask, eventType in mask | (1 << eventType.rawValue) }
        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: mouseEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        machPort = port

        return true
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let machPort { CGEvent.tapEnable(tap: machPort, enable: true) }

            return Unmanaged.passUnretained(event)
        }

        // Read snapshots, classify, mutate fields, or return nil to swallow.
        return Unmanaged.passUnretained(event)
    }
}

private func mouseEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }

    let tap = Unmanaged<MouseEventTap>.fromOpaque(userInfo).takeUnretainedValue()

    return tap.handle(type: type, event: event)
}
```

- **Lifetime:** `passUnretained` means the owner (`MouseEventTap`) must outlive the mach port. Tear down in this order: disable, remove the source, `CFMachPortInvalidate`, then release. Do it on the tap thread, as LinearMouse does with `withExtendedLifetime`.
- **Thread:** use a `Thread` subclass or a closure that sets `qualityOfService = .userInteractive`, adds a dummy port, signals readiness and calls `CFRunLoopRun()`. Send work with `CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { ... }` plus `CFRunLoopWakeUp` (LinearMouse `EventThread`). Stop with `CFRunLoopStop` after invalidating the tap. Don't use Swift concurrency `Task`s for per-event work: ordering isn't guaranteed and hops are expensive.
- **Cross-thread state:** use `OSAllocatedUnfairLock` (Apple's `os` module, macOS 13+) holding an immutable `Sendable` settings struct, replaced wholesale when the user changes a setting. The device map is published the same way (LinearMouse `EventDeviceSnapshot` uses `NSLock`). `Synchronization.Mutex` needs macOS 15, so not with a macOS 13 target.
- **Private SPI from SwiftPM:** add a small C target (for example `Sources/CGEventSPI/include/CGEventSPI.h`) that declares `CGEventCopyIOHIDEvent`, `IOHIDEventGetSenderID`, `IOHIDEventGetType`, `IOHIDEventGetFloatValue` and `IOHIDEventSetFloatValue` under `CF_IMPLICIT_BRIDGING_ENABLED`, plus `linkerSettings: [.linkedFramework("IOKit")]`. This mirrors LinearMouse's bridging header. Write our own declarations; the PointerKit SPI header carries Apple's BSD notice. Modifying the IOHIDEvent "copy" changes the event that is delivered (this is how both tools fix WebKit), so the copy shares the embedded object. That is observed behaviour, not documented.

### 5.2 Performance

- The system disables a tap whose callback is too slow (`tapDisabledByTimeout`). The exact timeout isn't documented (**unverified**; often quoted as about 1 s).
- In the callback: no AppKit, no `NSWorkspace`, no `os_log` at default level per event (Scroll Reverser: NSLog "would slow down event processing too much"), no TCC/IPC calls (`IOHIDCheckAccess`), no allocation-heavy work, no main-thread hops that wait.
- Cache sender-to-category lookups. If a lookup misses, do the IORegistry query once per sender with a 250 ms negative cache (Scroll Reverser). Or pass the event through unchanged and let the main-side catalog fill in the entry.
- Leave motion events out of the mask.
- Keep a health timer every 5 s with throttled restarts (Mos: at most 3 in 60 s), and re-check after `NSWorkspace.didWakeNotification` (immediately and again after ~1 s).

### 5.3 Secure Input

- Secure Event Input (password fields, some terminals) stops keyboard events reaching taps. Mouse and scroll taps are believed to keep working (**unverified**), which is one more reason not to tap keyboard events. Posting ⌘[ while Secure Input is on might not reach the app (**unverified**).

---

## 6. OS changes 2024–2026 (question 5)

| macOS | Change / report | Source |
| --- | --- | --- |
| 13 Ventura (beta) | `IOHIDDeviceRegisterInputValueCallback` broken; MMF switched to IOHIDEvent-from-CGEvent | [MMF #297](https://github.com/noah-nuebling/mac-mouse-fix/issues/297) |
| 14 Sonoma | New "Pointer acceleration" switch (Mouse > Advanced), backed by `com.apple.mouse.linear` and per-device `HIDUseLinearScalingMouseAcceleration` | [macos-defaults](https://macos-defaults.netlify.app/mouse/linear.html), LinearMouse `Device.swift` |
| 14.6.1 | MMF 2.2.4 scrolling stopped working (cause not established) | [MMF #1080](https://github.com/noah-nuebling/mac-mouse-fix/issues/1080), [#1109](https://github.com/noah-nuebling/mac-mouse-fix/issues/1109) |
| 15 Sequoia | Pointer speed changes through LinearMouse much weaker or ignored; CursorSense FAQ: "Magic Trackpad does not support sensitivity changes in macOS Sequoia or later" | [LinearMouse #806](https://github.com/linearmouse/linearmouse/issues/806), [#1004](https://github.com/linearmouse/linearmouse/issues/1004) |
| 15 | iPhone Mirroring ignores reversed scroll | [SR #184](https://github.com/pilotmoon/Scroll-Reverser/issues/184), [Mos #655](https://github.com/Caldis/Mos/issues/655) |
| 15.4.1 | Lid close / display hot-plug made SR 1.x misclassify the trackpad (gesture tap) | [SR #193](https://github.com/pilotmoon/Scroll-Reverser/issues/193) |
| 26 Tahoe | `HIDPointerResolution` writes ignored for built-in/Magic trackpad and Magic Mouse; "Unable to serialize CFObject ... CFNull" log (LinearMouse later fixed null HID property writes, PR #1397) | [LinearMouse #1004](https://github.com/linearmouse/linearmouse/issues/1004), [#1003](https://github.com/linearmouse/linearmouse/issues/1003), v0.12.0 notes |
| 26.2–26.6 | Mos regressions: needed new version plus re-authorisation; choppy after wake | [Mos #826](https://github.com/Caldis/Mos/issues/826), [#958](https://github.com/Caldis/Mos/issues/958) |
| 15 / 26 / 27 | Revoking Accessibility with an active tap hangs system input | [forum 844416](https://developer.apple.com/forums/thread/844416) |
| 27 (shipped by Sept 2026, users call it "Golden Gate") | Accessibility pane renamed "Device Control and Data Access"; PostEvent evaluated as its own composed service (MDM); synthesized 3-finger swipes broke for MMF until 3.1.0; Xcode 27 SDK raises the SwiftPM deployment floor to macOS 12 | [LinearMouse PR #1442](https://github.com/linearmouse/linearmouse/pull/1442), [#1436](https://github.com/linearmouse/linearmouse/issues/1436), [MMF 3.1.0](https://github.com/noah-nuebling/mac-mouse-fix/releases/tag/3.1.0), [LinearMouse PR #1387](https://github.com/linearmouse/linearmouse/pull/1387) |

I found no Apple announcement of an event-tap API change for 14, 15, 26 or 27. The breakages above come from third-party reports. macOS 27 is out, so test on it even though the dev machine runs 26.5.2.

---

## 7. System settings for comparison (question 6)

Read on this Mac (26.5.2) with `defaults read -g`, `hidutil property --get` and `ioreg` (read-only):

| Key (NSGlobalDomain) | Value here | What it is | Evidence |
| --- | --- | --- | --- |
| `com.apple.swipescrolldirection` | `1` | "Natural scrolling". **One global value**: toggling it in Mouse settings also changes Trackpad settings | [UnnaturalScrollWheels README](https://github.com/ther0n/UnnaturalScrollWheels) |
| `com.apple.mouse.scaling` | `0.875` | Mouse "Tracking speed". Maps to the HID property `HIDMouseAcceleration` = 57344 = 0.875 x 65536 (seen in `ioreg`) | local `ioreg` |
| `com.apple.mouse.linear` | `0` | Sonoma+ "Pointer acceleration" switch (1 = acceleration **off** / linear). Maps to `HIDUseLinearScalingMouseAcceleration = 0` in `ioreg`. macos-defaults: "introduced in macOS 14", "A restart of your Mac is required" when set by `defaults` | [macos-defaults](https://macos-defaults.netlify.app/mouse/linear.html), local `ioreg` |
| `com.apple.scrollwheel.scaling` | *(not set; default)* | Mouse "Scrolling speed". The HID value `HIDMouseScrollAcceleration` / `HIDScrollAcceleration` = 20480 = 0.3125 | local `ioreg` |
| `com.apple.trackpad.scaling` | *(not set; default)* | Trackpad tracking speed. `HIDTrackpadAcceleration` = 45056 = 0.6875 (same as LinearMouse's fallback) | local `ioreg` |

Notes:

- These are user preferences that WindowServer pushes into per-service HID properties at login and when a device is added. Writing the plist with `defaults write` doesn't apply live, and macos-defaults says a restart is needed. Setting HID properties directly (section 2.7) applies at once but is overwritten when the user moves the System Settings slider, so observe and re-apply.
- There is **no** per-device scroll direction in macOS. That is why per-device (mouse vs trackpad) reversing needs a tap. The Magic Mouse's own preferences live in `com.apple.AppleMultitouchMouse` / `com.apple.driver.AppleBluetoothMultitouch.mouse` (`MouseMomentumScroll`, `MouseButtonMode` and so on), and none of them is a direction key.
- Built-in trackpad properties seen here: `HIDScrollAccelerationType = "HIDTrackpadScrollAcceleration"`, `HIDPointerAccelerationType = "HIDTrackpadAcceleration"`, `HIDPointerResolution = 26214400` (400 DPI as IOFixed). These are the values to key classification on.
- `com.apple.mouse.scaling -1` is an old trick to disable acceleration; it makes the pointer very slow ([iBoysoft](https://iboysoft.com/wiki/macos-mouse-acceleration.html)). Don't use it.

---

## 8. Licence obligations (question 7)

LinearMouse [LICENSE](https://github.com/linearmouse/linearmouse/blob/main/LICENSE) is MIT, "Copyright (c) 2021-2024 LinearMouse" in the LICENSE file. Source headers say "Copyright (c) 2021-2026 LinearMouse".

- What the licence requires: "The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software." That covers source we copy or adapt **and** binaries we ship that contain it.
- Where to put it:
  1. At the top of each adapted file, keep a short header naming the origin and pointing to the notice file:
     `// Portions adapted from LinearMouse (https://github.com/linearmouse/linearmouse)`
     `// Copyright (c) 2021-2026 LinearMouse. MIT License, see ThirdPartyNotices/LinearMouse.txt`
  2. In the repo, add `ThirdPartyNotices/LinearMouse.txt` with the full MIT text verbatim, the copyright line, the upstream commit SHA and the list of adapted files. This mirrors how LinearMouse records its own borrowings in [`ThirdPartyNotices/README.md`](https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/ThirdPartyNotices/README.md).
  3. In the shipped app, add an "Acknowledgements" screen or bundle the notices file in `Contents/Resources` so binary distributions include the notice.
- Suggested credit line for About / README: "Mouse & Scrolling builds on LinearMouse by Jiahao Lu and contributors (MIT License)." The name comes from the `Created by Jiahao Lu` file header in PointerKitC and the GitHub handle lujjjh. Or, safer: "...builds on LinearMouse (github.com/linearmouse/linearmouse), Copyright (c) 2021-2026 LinearMouse, used under the MIT License."
- Be careful with nested notices inside LinearMouse:
  - `Modules/PointerKit/.../IOKitSPIMac.h` is under Apple's 2-clause BSD licence. Keep that header verbatim if we copy it, or write our own declarations instead (recommended).
  - The pointer-speed approach came from Mac Mouse Fix v2 (MIT at that revision). We'd be adapting LinearMouse's code, not MMF's, but LinearMouse keeps the MMF notice, so carry it if we copy `PointerDevice` logic closely.
  - PermissionFlow (MIT; the drag-to-authorize guide), libinput (MIT), yabai (MIT) and Firefox (behaviour only, no code) are only relevant if we take those features.
- Scroll Reverser is **Apache-2.0**. We may copy its code if we keep the licence, state changes, and include any NOTICE file. It's a good reference for sender-to-device identification.
- Don't copy from Mos (CC BY-NC 4.0, non-commercial), UnnaturalScrollWheels (GPL-3.0), SensibleSideButtons (GPL-2.0) or Mac Mouse Fix (MMF License). Ideas and the API usage patterns described here are fine.

---

## 9. Recommended architecture

### 9.1 Types

| Type | Isolation / thread | Job |
| --- | --- | --- |
| `MouseScrollingSettings` | value type, `Sendable`, `Codable` | User settings: per category `{ reverseVertical, reverseHorizontal }`, `linearScrolling: { isEnabled, linesPerNotch }` (mouse only by default), `backForward: { isEnabled }`, `middleClick: MiddleClickAction`, `pointer: { disableAcceleration, speed }`. In v2 keyed by device identity |
| `MouseSettingsSnapshot` | `Sendable` | Flattened, precomputed view for the hot path (for example a `reverse` multiplier per category and axis) |
| `InputDeviceCategory` | enum `mouse`, `trackpad`, `unknown` | Classification result |
| `InputDeviceIdentity` | `Sendable`, `Hashable` | `(vendorID, productID, serial?, transport, product?)` following Scroll Reverser; the v2 per-device key. Never the sender ID |
| `InputDeviceCatalog` | `@MainActor` (or a utility queue) | Discovers HID services (`IOServiceAddMatchingNotification` on `IOHIDEventService` for add/remove, plus `IOHIDEventSystemClientCreateSimpleClient` / `IOHIDEventSystemClientCopyServices` for properties). Builds `[senderID (registry ID): (identity, category)]` and publishes it into the lock |
| `EventTapThread` | own `Thread` + `CFRunLoop` | Hosts the tap, its health timer and re-enable calls |
| `MouseEventTap` | confined to `EventTapThread`, `@unchecked Sendable` | Callback; applies `ScrollRewriter` and `ButtonRemapper` |
| `ScrollRewriter` | pure functions on `CGEvent` | `reverse(_:vertical:horizontal:)` (all 4 representations including IOHIDEvent), `applyLinear(_:lines:)`; unit-testable |
| `ButtonRemapper` | tap thread | Buttons 3/4 → post ⌘[ / ⌘] and swallow down+up; button 2 → configured action; tracks "swallowed down" per button so the matching up is swallowed even if settings changed between them |
| `SyntheticEventMarker` | constants | `eventSourceUserData` tag; the tap ignores tagged events |
| `PointerSettingsApplier` | `@MainActor` / utility queue | Writes HID properties per mouse service, records originals, restores on stop, re-applies on device add and on property change |
| `AccessibilityGate` | `@MainActor` | State machine `unknown → denied → waiting → granted → running`, plus `revoked`; polls only while waiting; probe-tap watchdog while running; asks the coordinator to stop the tap before anything else on revocation |
| `MouseModuleCoordinator` | `@MainActor` | Wires everything; reacts to settings, permission, sleep/wake and session active/resign |

### 9.2 Data flow

```
HID device
  -> WindowServer HID tap point
  -> [MouseEventTap callback on EventTapThread]
       1. tapDisabledBy* -> re-enable, pass through
       2. tagged synthetic -> pass through
       3. scrollWheel:
            hid = CGEventCopyIOHIDEvent(event)
            category = hid.map { devicesLock[IOHIDEventGetSenderID($0)] } ?? heuristic(event)
            settings = settingsLock.snapshot
            if category == .mouse, linear enabled, !continuous: rewrite line deltas; drop momentum
            if reverse for category: negate DeltaAxis, PointDelta, FixedPt, IOHID ScrollX/Y
       4. otherMouseDown/Up:
            button 3/4 + back/forward on -> post ⌘[/⌘] (tagged, .cgSessionEventTap) on down; return nil on down and up
            button 2 + action != passThrough -> perform; return nil on down and up
       return event
  -> rest of the system

Main thread:
  Settings UI -> MouseScrollingSettings -> snapshot -> settingsLock
  InputDeviceCatalog -> device map -> devicesLock
  PointerSettingsApplier -> IOHIDServiceClientSetProperty (never on the tap thread)
  AccessibilityGate -> start/stop EventTapThread
```

Heuristic for events with no IOHIDEvent or an unknown sender: `isContinuous == 0` and no phases means a mouse wheel. Phased or momentum means trackpad-like, so leave it unchanged unless the user opted in. The source PID (`eventSourceUnixProcessID`) identifies app-posted events (Logi Options+, remote desktop); default those to unchanged.

### 9.3 Pointer settings specifics

- Don't touch services whose category is trackpad. Pointer settings in v1 are for mice.
- macOS 14+: "acceleration off" = `HIDUseLinearScalingMouseAcceleration = 1`, and "speed" = `HIDMouseAcceleration` IOFixed gain (0...40, as in LinearMouse's "Tracking speed"). Acceleration on with speed = `HIDUseLinearScalingMouseAcceleration = 0` plus `HIDPointerResolution` for sensitivity and `HIDMouseAcceleration` for the curve.
- macOS 13: "acceleration off" = `HIDMouseAcceleration` (or the reported `HIDPointerAccelerationType` key) = `-1`. Speed is then not adjustable in LinearMouse; whether `HIDPointerResolution` still applies at -1 is **unverified**. Hide or disable the speed control on 13 when acceleration is off, or test it.
- Whether a *simple* event-system client may set these properties is **unverified**. LinearMouse uses the private `IOHIDEventSystemClientCreate`. Test early; fall back to declaring the private constructor.
- Never write `NSNull` or missing values. LinearMouse's `hidPropertyValue` guard avoids the "Unable to serialize CFObject ... CFNull" error seen on Tahoe.
- Record originals per service on first sight and restore on disable, quit and `applicationWillTerminate`. After a crash, values stay until WindowServer re-applies preferences on device reconnect or login (**unverified**).
- Show a notice that Apple trackpads and the Magic Mouse may ignore pointer speed on Sequoia+ (LinearMouse shows "Due to system limitations, this device may not support adjusting Pointer Speed on newer versions of macOS.").

### 9.4 Back/forward and middle click details

- Key codes: `kVK_ANSI_LeftBracket = 0x21`, `kVK_ANSI_RightBracket = 0x1E` (Carbon `Events.h`). On non-US layouts the physical key at those codes may not type `[`/`]`, and menu shortcuts match on characters. Consider resolving the key code for "[" and "]" from the current layout with `UCKeyTranslate`, or accept the limitation in v1 (LinearMouse needed fixes for non-US layouts, PR #1406).
- Post with a `CGEventSource(stateID: .hidSystemState)` (LinearMouse PR #1370). Set `.flags = .maskCommand` on both key down and key up, tag both, and post to `.cgSessionEventTap`.
- ⌘[ means "outdent" in many editors (VS Code, Xcode's text editor). Chromium browsers and VS Code already handle buttons 4/5 natively. Offer a per-app exception list, or a mode that passes buttons 4/5 through for apps known to handle them (the inverse of LinearMouse's `includes` list).
- Middle-click actions for v1: pass through, ⌘+left click (open link in new tab), Mission Control (launch `/System/Applications/Mission Control.app` through `NSWorkspace` on the main thread; hop with `DispatchQueue.main.async`, never wait), or a custom shortcut. Swallow both the down and the up when remapped.

---

## 10. Edge cases to test

Scrolling and classification

1. Built-in trackpad and a USB wheel mouse used alternately within a second: the reverse setting follows each event, not a "last device".
2. A Magic Mouse (continuous, phases, momentum) is classed as a mouse, momentum reverses without snap-back in Safari, and linear mode doesn't break it (disable linear for continuous devices).
3. Magic Trackpad over Bluetooth and over USB-C (different sender, same identity), and reconnect after sleep (new sender ID).
4. Safari, a WKWebView app (Mail, App Store), Chrome, Xcode and Finder: momentum direction after a reversed flick, rubber-band bounce at the edges.
5. Linear mode: one notch = N lines in TextEdit, Safari and Terminal; no momentum after the wheel stops; direction change on the first notch (LinearMouse #1146 reports a first reversed tick on some mice, not reproduced by its author).
6. Shift+wheel (macOS turns it into horizontal axis 2): the horizontal reverse setting applies, and linear mode applies to axis 2.
7. Logitech mouse with Options+ installed (smooth scrolling on and off), and Options+ enabled under Accessibility.
8. Logitech receiver with two devices behind it.
9. Karabiner-Elements with "Modify events" on for the mouse.
10. Universal Control (the other Mac's devices) and Screen Sharing / remote desktop (app-posted events).
11. iPhone Mirroring window (expected: unchanged).
12. Mice with a hi-res wheel (Logitech MX) that send fractional or large deltas: no zero-delta events after rounding.
13. Mice that tilt the wheel for back/forward (horizontal scroll), not buttons 4/5.

Buttons

14. Buttons 4/5 in Safari, Finder, Xcode, Chrome, VS Code, Slack and the System Settings window: back/forward works, nothing "outdents".
15. Holding button 4 and changing settings before release: no stray `otherMouseUp` reaches apps.
16. Non-US keyboard layouts (German, French, Dvorak) with ⌘[.
17. Middle click remapped while a modifier is held; middle click in Chrome tab strips and Safari favourites.

Tap lifecycle and permissions

18. First launch with no permission, then grant: detected within ~1 s, the tap starts or the app relaunches once, and no polling continues afterwards.
19. Permission removed with "−" rather than toggled off while the tap runs: the watchdog notices, and input doesn't stay frozen (document the risk if it does).
20. Rebuild with the same Apple Development identity (grant kept), with the other identity (grant lost), and ad-hoc (grant lost but still shown as "on").
21. A slow main thread (for example a modal sheet) doesn't affect scrolling, because the tap runs on its own thread.
22. A forced timeout (sleep in the callback in a debug build): the tap re-enables, and restarts are throttled.
23. Sleep/wake, lid close, display hot-plug, fast user switching (session resign/active) and screen lock: the tap is healthy afterwards.
24. Disable or quit the module: the tap is invalidated (no zombie tap), and pointer HID properties are restored.
25. Secure Input on (a password field focused): scrolling still reversed; ⌘[ behaviour noted.
26. The System Settings Tracking speed slider moved while our pointer settings are active: our values are re-applied, or the change is detected.
27. macOS 13 (no `HIDUseLinearScalingMouseAcceleration`), 14, 15, 26 and 27 ("Device Control and Data Access" wording in onboarding).
28. MDM-managed Mac where Accessibility is allowed but PostEvent is not: show a clear error instead of retrying forever.

---

## Sources

LinearMouse (MIT)
- Repo and licence: https://github.com/linearmouse/linearmouse, https://github.com/linearmouse/linearmouse/blob/main/LICENSE
- EventTap.swift: https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/EventTap/EventTap.swift
- EventThread.swift: https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/EventTap/EventThread.swift
- GlobalEventTap.swift: https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/EventTap/GlobalEventTap.swift
- GlobalEventTapWatchdog.swift: https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/EventTap/GlobalEventTapWatchdog.swift
- EventTapRecovery.swift: https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/EventTap/EventTapRecovery.swift
- EventType.swift: https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/EventTap/EventType.swift
- EventTransformer.swift: https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/EventTransformer/EventTransformer.swift
- EventTransformerManager.swift: https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/EventTransformer/EventTransformerManager.swift
- ReverseScrollingTransformer.swift: https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/EventTransformer/ReverseScrollingTransformer.swift
- LinearScrollingVerticalTransformer.swift: https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/EventTransformer/LinearScrollingVerticalTransformer.swift
- UniversalBackForwardTransformer.swift: https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/EventTransformer/UniversalBackForwardTransformer.swift
- ButtonActionExecutor.swift: https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/EventTransformer/ButtonActionExecutor.swift
- ScrollWheelEventView.swift: https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/EventView/ScrollWheelEventView.swift
- CGEvent+LinearMouseSynthetic.swift: https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/Utilities/CGEvent%2BLinearMouseSynthetic.swift
- DeviceManager.swift: https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/Device/DeviceManager.swift
- Device.swift: https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/Device/Device.swift
- EventDeviceSnapshot.swift: https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/Device/EventDeviceSnapshot.swift
- PointerSchemeApplication.swift: https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/Device/PointerSchemeApplication.swift
- PointerKit PointerDevice.swift: https://github.com/linearmouse/linearmouse/blob/main/Modules/PointerKit/Sources/PointerKit/PointerDevice.swift
- PointerKit PointerDeviceManager.swift: https://github.com/linearmouse/linearmouse/blob/main/Modules/PointerKit/Sources/PointerKit/PointerDeviceManager.swift
- IOKitSPIMac.h: https://github.com/linearmouse/linearmouse/blob/main/Modules/PointerKit/Sources/PointerKitC/include/IOKitSPIMac.h
- Bridging header: https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/LinearMouse-Bridging-Header.h
- AccessibilityPermission.swift: https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/AccessibilityPermission.swift
- AccessibilityPermissionWindow.swift: https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/UI/AccessibilityPermissionWindow.swift
- PointerSettings.swift: https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/UI/PointerSettings/PointerSettings.swift
- ACCESSIBILITY.md: https://github.com/linearmouse/linearmouse/blob/main/ACCESSIBILITY.md
- Third-party notices: https://github.com/linearmouse/linearmouse/blob/main/LinearMouse/ThirdPartyNotices/README.md
- PRs: #1148 https://github.com/linearmouse/linearmouse/pull/1148, #1412 https://github.com/linearmouse/linearmouse/pull/1412, #1442 https://github.com/linearmouse/linearmouse/pull/1442, #1387 https://github.com/linearmouse/linearmouse/pull/1387, #1494 https://github.com/linearmouse/linearmouse/pull/1494
- Issues: #1004 https://github.com/linearmouse/linearmouse/issues/1004, #1003 https://github.com/linearmouse/linearmouse/issues/1003, #806 https://github.com/linearmouse/linearmouse/issues/806, #1436 https://github.com/linearmouse/linearmouse/issues/1436, #1428 https://github.com/linearmouse/linearmouse/issues/1428, #1146 https://github.com/linearmouse/linearmouse/issues/1146, #106 https://github.com/linearmouse/linearmouse/issues/106, #1502 https://github.com/linearmouse/linearmouse/issues/1502
- Releases: https://github.com/linearmouse/linearmouse/releases

Scroll Reverser (Apache-2.0)
- MouseTap.m: https://github.com/pilotmoon/Scroll-Reverser/blob/master/MouseTap.m
- ScrollSource.m: https://github.com/pilotmoon/Scroll-Reverser/blob/master/ScrollSource.m
- PermissionsManager.m: https://github.com/pilotmoon/Scroll-Reverser/blob/master/PermissionsManager.m
- README: https://github.com/pilotmoon/Scroll-Reverser/blob/master/README.md
- v2.0 release: https://github.com/pilotmoon/Scroll-Reverser/releases/tag/v2.0
- Issues: #136 https://github.com/pilotmoon/Scroll-Reverser/issues/136, #130 https://github.com/pilotmoon/Scroll-Reverser/issues/130, #193 https://github.com/pilotmoon/Scroll-Reverser/issues/193, #184 https://github.com/pilotmoon/Scroll-Reverser/issues/184, #149 https://github.com/pilotmoon/Scroll-Reverser/issues/149

Mos (CC BY-NC 4.0)
- Interceptor.swift: https://github.com/Caldis/Mos/blob/master/Mos/Utils/Interceptor.swift
- ScrollEvent.swift: https://github.com/Caldis/Mos/blob/master/Mos/ScrollCore/ScrollEvent.swift
- ScrollCore.swift: https://github.com/Caldis/Mos/blob/master/Mos/ScrollCore/ScrollCore.swift
- Issues: #1058 https://github.com/Caldis/Mos/issues/1058, #958 https://github.com/Caldis/Mos/issues/958, #1040 https://github.com/Caldis/Mos/issues/1040, #826 https://github.com/Caldis/Mos/issues/826, #655 https://github.com/Caldis/Mos/issues/655

UnnaturalScrollWheels (GPL-3.0)
- ScrollInterceptor.swift: https://github.com/ther0n/UnnaturalScrollWheels/blob/main/UnnaturalScrollWheels/ScrollInterceptor.swift
- README: https://github.com/ther0n/UnnaturalScrollWheels

SensibleSideButtons (GPL-2.0)
- AppDelegate.m: https://github.com/archagon/sensible-side-buttons/blob/master/SensibleSideButtons/AppDelegate.m
- README: https://github.com/archagon/sensible-side-buttons

Mac Mouse Fix (MMF License)
- Licence: https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License
- Issues: #297 https://github.com/noah-nuebling/mac-mouse-fix/issues/297, #1239 https://github.com/noah-nuebling/mac-mouse-fix/issues/1239, #1141 https://github.com/noah-nuebling/mac-mouse-fix/issues/1141, #1080 https://github.com/noah-nuebling/mac-mouse-fix/issues/1080, #1109 https://github.com/noah-nuebling/mac-mouse-fix/issues/1109, #2030 https://github.com/noah-nuebling/mac-mouse-fix/issues/2030
- 3.1.0 release: https://github.com/noah-nuebling/mac-mouse-fix/releases/tag/3.1.0

Apple
- Forums 744440 (Quinn on CGPreflight/Request functions): https://developer.apple.com/forums/thread/744440
- Forums 735204 (revocation, PostEvent shown under Accessibility, relaunch advice): https://developer.apple.com/forums/thread/735204
- Forums 844416 (system-wide input hang on revocation, Sequoia/Tahoe/27): https://developer.apple.com/forums/thread/844416
- TN3127 Inside Code Signing: Requirements: https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements
- SDK headers on this Mac (Command Line Tools SDK): `CoreGraphics/CGEvent.h` (tap creation, preflight/request functions), `CoreGraphics/CGEventTypes.h` (tap locations, scroll fields), `IOKit/hidsystem/IOHIDLib.h` (`IOHIDCheckAccess`), `IOKit/hidsystem/IOHIDServiceClient.h` and `IOHIDEventSystemClient.h` (public property API), `IOKit/hid/IOHIDEventServiceKeys.h` (`kIOHIDUseLinearScalingMouseAccelerationKey`)

Other
- hyperwhisper PR #1385 (tap on its own thread, Swift 6 isolation of callbacks): https://github.com/ray-amjad/hyperwhisper-app/pull/1385
- CGEvent taps and code signing, silent disable race: https://danielraffel.me/til/2026/02/19/cgevent-taps-and-code-signing-the-silent-disable-race/
- macos-defaults, `com.apple.mouse.linear`: https://macos-defaults.netlify.app/mouse/linear.html
- MacRumors, tracking speed with acceleration off: https://forums.macrumors.com/threads/how-is-mac-dpi-scaled-to-tracking-speed-setting-when-mouse-advanced-pointer-acceleration-is-turned-off.2455764
- iBoysoft, `com.apple.mouse.scaling -1`: https://iboysoft.com/wiki/macos-mouse-acceleration.html
- lan-mouse, AX polling: https://docs.rs/crate/lan-mouse-gtk/0.3.0/source/src/macos_privacy.rs
- PermissionFlow (MIT, used by LinearMouse): https://github.com/jaywcjlove/PermissionFlow

Local verification on this Mac (read-only, nothing changed): `defaults read -g` for the keys in section 7; `hidutil list`; `ioreg -r -c IOHIDEventService -l`; `security find-identity -v -p codesigning`; ad-hoc signing a throwaway binary in the scratchpad to print its designated requirement.
