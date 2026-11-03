import AppKit
import Carbon.HIToolbox

/// A key plus modifiers. `modifiers` holds CGEventFlags bits (command, control, option, shift, fn).
struct KeyCombo: Codable, Hashable {
    var keyCode: Int
    var modifiers: UInt64

    static let relevantMask: UInt64 = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskControl.rawValue
        | CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskShift.rawValue | CGEventFlags.maskSecondaryFn.rawValue

    /// Keys for which macOS always sets the fn flag (arrows, F-keys, Home/End…), so fn carries no meaning there.
    static let implicitFnKeys: Set<Int> = {
        var s: Set<Int> = [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Home, kVK_End,
                           kVK_PageUp, kVK_PageDown, kVK_ForwardDelete, kVK_Help]
        s.formUnion(fKeys)
        return s
    }()
    static let arrowKeys: Set<Int> = [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow]
    static let fKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
    /// Key codes of modifier keys themselves (never recorded as the main key).
    static let modifierKeyCodes: Set<Int> = [kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift, kVK_Option,
                                             kVK_RightOption, kVK_Control, kVK_RightControl, kVK_CapsLock, kVK_Function]

    /// Normalizes raw event flags into the comparable modifier set for `keyCode`.
    static func normalized(keyCode: Int, flags: UInt64) -> KeyCombo {
        var m = flags & relevantMask
        if implicitFnKeys.contains(keyCode) { m &= ~CGEventFlags.maskSecondaryFn.rawValue }
        return KeyCombo(keyCode: keyCode, modifiers: m)
    }

    static func cgFlags(from f: NSEvent.ModifierFlags) -> UInt64 {
        var m: UInt64 = 0
        if f.contains(.command) { m |= CGEventFlags.maskCommand.rawValue }
        if f.contains(.control) { m |= CGEventFlags.maskControl.rawValue }
        if f.contains(.option) { m |= CGEventFlags.maskAlternate.rawValue }
        if f.contains(.shift) { m |= CGEventFlags.maskShift.rawValue }
        if f.contains(.function) { m |= CGEventFlags.maskSecondaryFn.rawValue }
        return m
    }

    /// Flags to put on a synthesized event for this combo (adds the implicit bits real hardware sets).
    var eventFlags: CGEventFlags {
        var f = CGEventFlags(rawValue: modifiers)
        if KeyCombo.implicitFnKeys.contains(keyCode) { f.insert(.maskSecondaryFn) }
        if KeyCombo.arrowKeys.contains(keyCode) { f.insert(.maskNumericPad) }
        return f
    }

    static func modifierSymbols(_ m: UInt64) -> String {
        var s = ""
        if m & CGEventFlags.maskSecondaryFn.rawValue != 0 { s += "🌐" }
        if m & CGEventFlags.maskControl.rawValue != 0 { s += "⌃" }
        if m & CGEventFlags.maskAlternate.rawValue != 0 { s += "⌥" }
        if m & CGEventFlags.maskShift.rawValue != 0 { s += "⇧" }
        if m & CGEventFlags.maskCommand.rawValue != 0 { s += "⌘" }
        return s
    }

    var display: String { KeyCombo.modifierSymbols(modifiers) + KeyCombo.keyName(keyCode) }

    private static let specialKeyNames: [Int: String] = {
        var names: [Int: String] = [
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Return: "↩", kVK_Space: "Space", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_Escape: "⎋", kVK_ANSI_KeypadEnter: "⌤", kVK_Home: "↖", kVK_End: "↘",
            kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_Help: "Help",
            kVK_JIS_Eisu: "英数", kVK_JIS_Kana: "かな",
        ]
        for (i, code) in fKeys.enumerated() { names[code] = "F\(i + 1)" }
        return names
    }()

    static func keyName(_ code: Int) -> String {
        if let s = specialKeyNames[code] { return s }
        // Translate through the current keyboard layout.
        if let src = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
           let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
            var dead: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var len = 0
            let ok = data.withUnsafeBytes { raw -> Bool in
                guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return false }
                return UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                                      UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                      &dead, 4, &len, &chars) == noErr
            }
            if ok, len > 0 {
                let s = String(utf16CodeUnits: chars, count: len).uppercased()
                if !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
            }
        }
        return "Key\(code)"
    }
}
