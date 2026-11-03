import AppKit

/// Marks events Keysy synthesizes so its own tap lets them through.
private let keysyEventTag: Int64 = 0x4B45_5953   // "KEYS"

enum KeySender {
    private static let source = CGEventSource(stateID: .privateState)

    static func post(_ combo: KeyCombo, down: Bool, autorepeat: Bool = false) {
        guard let e = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(combo.keyCode), keyDown: down) else { return }
        e.flags = combo.eventFlags
        e.setIntegerValueField(.eventSourceUserData, value: keysyEventTag)
        if autorepeat { e.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
        e.post(tap: .cghidEventTap)
    }
}

/// Global keyboard remapper built on a CGEventTap (requires Accessibility permission).
final class Remapper {
    static let shared = Remapper()

    private var tap: CFMachPort?
    private var table: [KeyCombo: KeyCombo] = [:]
    private var windowTable: [KeyCombo: WindowCommand] = [:]
    /// Physical key code currently held → what we emitted for it (so key-up mirrors key-down).
    private var held: [Int: KeyCombo] = [:]
    private var retryTimer: Timer?

    /// Temporarily pass every event through (e.g. while recording a shortcut).
    var suspended = false

    var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func start() {
        reload()
        NotificationCenter.default.addObserver(forName: RuleStore.changed, object: nil, queue: .main) { [weak self] _ in
            self?.reload()
        }
        installTap()
    }

    func reload() {
        let store = RuleStore.shared
        table = store.enabled ? store.table : [:]
        windowTable = store.enabled ? WindowShortcutStore.shared.table : [:]
    }

    private func installTap() {
        guard tap == nil else { return }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                           options: .defaultTap, eventsOfInterest: CGEventMask(mask),
                                           callback: keysyTapCallback, userInfo: refcon) else {
            // Not trusted yet: retry until the user grants Accessibility permission.
            if retryTimer == nil {
                retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                    guard AXIsProcessTrusted() else { return }
                    self?.retryTimer?.invalidate(); self?.retryTimer = nil
                    self?.installTap()
                }
            }
            return
        }
        tap = port
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        NotificationCenter.default.post(name: RuleStore.changed, object: nil)
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        case .keyDown, .keyUp:
            break
        default:
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == keysyEventTag || suspended {
            return Unmanaged.passUnretained(event)
        }
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))

        if type == .keyUp {
            guard let target = held.removeValue(forKey: code) else { return Unmanaged.passUnretained(event) }
            KeySender.post(target, down: false)
            return nil
        }

        let combo = KeyCombo.normalized(keyCode: code, flags: event.flags.rawValue)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if let cmd = windowTable[combo] {
            if !isRepeat { DispatchQueue.main.async { cmd.perform() } }
            return nil   // swallow (key-up of a plain key without a held entry passes, which is harmless)
        }
        guard let target = table[combo] ?? (isRepeat ? held[code] : nil) else {
            return Unmanaged.passUnretained(event)
        }
        held[code] = target
        KeySender.post(target, down: true, autorepeat: isRepeat)
        return nil
    }
}

private func keysyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<Remapper>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
}
