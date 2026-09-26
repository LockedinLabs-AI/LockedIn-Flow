import AppKit
import CoreGraphics
import VoiceCore

/// What starts/stops a dictation.
enum ActivationTrigger: String, CaseIterable, Identifiable {
    case keyboard
    case mouse

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .keyboard: return "Keyboard shortcut"
        case .mouse: return "Mouse button"
        }
    }
}

/// Global mouse-button trigger (middle / back / forward) via a listen-only
/// CGEvent tap — we never consume the click, so normal behavior continues.
final class MouseTrigger {
    static let shared = MouseTrigger()

    /// 2 = middle (wheel), 3 = back, 4 = forward
    var buttonNumber = 2
    var isEnabled = false
    var onTrigger: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    func apply() {
        stop()
        guard isEnabled else { return }
        let mask: CGEventMask = 1 << CGEventType.otherMouseDown.rawValue
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: { _, _, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let trigger = Unmanaged<MouseTrigger>.fromOpaque(userInfo).takeUnretainedValue()
                    let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
                    if button == trigger.buttonNumber {
                        DispatchQueue.main.async { trigger.onTrigger?() }
                    }
                    return Unmanaged.passUnretained(event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            FlowLog.error("mouse trigger: could not create event tap")
            return
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }
}
