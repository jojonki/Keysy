import AppKit
import Carbon.HIToolbox

/// macOS built-in window tiling (Window ▸ Move & Resize, macOS 15+).
///
/// The commands are triggered by pressing the matching menu item of the frontmost app through
/// Accessibility. Items are located by their keyboard-shortcut signature (🌐⌃ + key), which is
/// independent of the UI language. If an app has no such menu item, the shortcut keystroke is
/// synthesized as a fallback.
enum WindowAction: String, Codable, CaseIterable, Identifiable {
    case fill, center, left, right, top, bottom
    case leftRight, rightLeft, topBottom, bottomTop
    case leftQuarters, rightQuarters, topQuarters, bottomQuarters
    case returnToPrevious

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fill: return "Fill"
        case .center: return "Center"
        case .left: return "Left"
        case .right: return "Right"
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .leftRight: return "Left & Right"
        case .rightLeft: return "Right & Left"
        case .topBottom: return "Top & Bottom"
        case .bottomTop: return "Bottom & Top"
        case .leftQuarters: return "Left & Quarters"
        case .rightQuarters: return "Right & Quarters"
        case .topQuarters: return "Top & Quarters"
        case .bottomQuarters: return "Bottom & Quarters"
        case .returnToPrevious: return "Return to Previous Size"
        }
    }

    var display: String { "Window: \(title)" }

    /// The macOS default shortcut for this command (always includes 🌐⌃).
    var builtInShortcut: KeyCombo {
        let fnCtrl = CGEventFlags.maskSecondaryFn.rawValue | CGEventFlags.maskControl.rawValue
        let opt = CGEventFlags.maskAlternate.rawValue, shift = CGEventFlags.maskShift.rawValue
        switch self {
        case .fill: return KeyCombo(keyCode: kVK_ANSI_F, modifiers: fnCtrl)
        case .center: return KeyCombo(keyCode: kVK_ANSI_C, modifiers: fnCtrl)
        case .returnToPrevious: return KeyCombo(keyCode: kVK_ANSI_R, modifiers: fnCtrl)
        case .left: return KeyCombo(keyCode: kVK_LeftArrow, modifiers: fnCtrl)
        case .right: return KeyCombo(keyCode: kVK_RightArrow, modifiers: fnCtrl)
        case .top: return KeyCombo(keyCode: kVK_UpArrow, modifiers: fnCtrl)
        case .bottom: return KeyCombo(keyCode: kVK_DownArrow, modifiers: fnCtrl)
        case .leftRight: return KeyCombo(keyCode: kVK_LeftArrow, modifiers: fnCtrl | shift)
        case .rightLeft: return KeyCombo(keyCode: kVK_RightArrow, modifiers: fnCtrl | shift)
        case .topBottom: return KeyCombo(keyCode: kVK_UpArrow, modifiers: fnCtrl | shift)
        case .bottomTop: return KeyCombo(keyCode: kVK_DownArrow, modifiers: fnCtrl | shift)
        case .leftQuarters: return KeyCombo(keyCode: kVK_LeftArrow, modifiers: fnCtrl | shift | opt)
        case .rightQuarters: return KeyCombo(keyCode: kVK_RightArrow, modifiers: fnCtrl | shift | opt)
        case .topQuarters: return KeyCombo(keyCode: kVK_UpArrow, modifiers: fnCtrl | shift | opt)
        case .bottomQuarters: return KeyCombo(keyCode: kVK_DownArrow, modifiers: fnCtrl | shift | opt)
        }
    }

    /// Accessibility menu-item modifier mask (kAXMenuItemModifier*): Shift=1, Option=2, Control=4,
    /// NoCommand=8; bit 16 is used by macOS for fn/🌐.
    private var axModifiers: Int {
        let m = builtInShortcut.modifiers
        var ax = 8 | 4 | 16
        if m & CGEventFlags.maskShift.rawValue != 0 { ax |= 1 }
        if m & CGEventFlags.maskAlternate.rawValue != 0 { ax |= 2 }
        return ax
    }

    private var axCharacter: String? {
        switch self {
        case .fill: return "F"
        case .center: return "C"
        case .returnToPrevious: return "R"
        default: return nil
        }
    }

    // MARK: - Performing

    private static let queue = DispatchQueue(label: "Keysy.WindowAction")

    func perform() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier
        WindowAction.queue.async {
            if let item = self.findMenuItem(pid: pid),
               AXUIElementPerformAction(item, kAXPressAction as CFString) == .success { return }
            DispatchQueue.main.async { KeySender.tap(self.builtInShortcut) }
        }
    }

    private func findMenuItem(pid: pid_t) -> AXUIElement? {
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appEl, 1.0)
        guard let bar: AXUIElement = attr(appEl, kAXMenuBarAttribute) else { return nil }
        let menus: [AXUIElement] = attr(bar, kAXChildrenAttribute) ?? []
        // The Window menu is usually near the end; search from the right.
        for menu in menus.reversed() {
            if let hit = search(menu, depth: 0) { return hit }
        }
        return nil
    }

    private func search(_ el: AXUIElement, depth: Int) -> AXUIElement? {
        if matches(el) { return el }
        guard depth < 5, let kids: [AXUIElement] = attr(el, kAXChildrenAttribute) else { return nil }
        for k in kids { if let hit = search(k, depth: depth + 1) { return hit } }
        return nil
    }

    private func matches(_ el: AXUIElement) -> Bool {
        guard let mods: Int = attr(el, kAXMenuItemCmdModifiersAttribute), mods == axModifiers else { return false }
        if let ch = axCharacter {
            return (attr(el, kAXMenuItemCmdCharAttribute) as String?)?.uppercased() == ch
        }
        return (attr(el, kAXMenuItemCmdVirtualKeyAttribute) as Int?) == builtInShortcut.keyCode
    }

    private func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
        var v: AnyObject?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
        return v as? T
    }
}
