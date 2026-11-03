import AppKit
import ApplicationServices

/// Window layouts Keysy performs itself on a global shortcut, in any app (via the Accessibility API).
enum WindowCommand: String, CaseIterable, Identifiable, Codable {
    case fill, center
    case left, right, top, bottom
    case topLeft, topRight, bottomLeft, bottomRight
    case leftRight, rightLeft, topBottom, bottomTop
    case restore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fill: return "Fill Screen"
        case .center: return "Center"
        case .left: return "Left Half"
        case .right: return "Right Half"
        case .top: return "Top Half"
        case .bottom: return "Bottom Half"
        case .topLeft: return "Top Left Quarter"
        case .topRight: return "Top Right Quarter"
        case .bottomLeft: return "Bottom Left Quarter"
        case .bottomRight: return "Bottom Right Quarter"
        case .leftRight: return "Left & Right (2 windows)"
        case .rightLeft: return "Right & Left (2 windows)"
        case .topBottom: return "Top & Bottom (2 windows)"
        case .bottomTop: return "Bottom & Top (2 windows)"
        case .restore: return "Restore Previous Size"
        }
    }

    var detail: String? {
        switch self {
        case .leftRight: return "Front window left, the window behind it right"
        case .rightLeft: return "Front window right, the window behind it left"
        case .topBottom: return "Front window top, the window behind it bottom"
        case .bottomTop: return "Front window bottom, the window behind it top"
        case .center: return "Keeps the size, moves to the middle"
        case .restore: return "Undo the last Keysy move of this window"
        default: return nil
        }
    }

    var section: String {
        switch self {
        case .fill, .center, .restore: return "General"
        case .left, .right, .top, .bottom: return "Halves"
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return "Quarters"
        case .leftRight, .rightLeft, .topBottom, .bottomTop: return "Arrange"
        }
    }

    /// Frame in AppKit coordinates within `a` (a screen's visible frame).
    private func rect(_ r: Region, in a: NSRect) -> NSRect {
        let hw = (a.width / 2).rounded(.down), hh = (a.height / 2).rounded(.down)
        switch r {
        case .full: return a
        case .left: return NSRect(x: a.minX, y: a.minY, width: hw, height: a.height)
        case .right: return NSRect(x: a.maxX - hw, y: a.minY, width: hw, height: a.height)
        case .top: return NSRect(x: a.minX, y: a.maxY - hh, width: a.width, height: hh)
        case .bottom: return NSRect(x: a.minX, y: a.minY, width: a.width, height: hh)
        case .topLeft: return NSRect(x: a.minX, y: a.maxY - hh, width: hw, height: hh)
        case .topRight: return NSRect(x: a.maxX - hw, y: a.maxY - hh, width: hw, height: hh)
        case .bottomLeft: return NSRect(x: a.minX, y: a.minY, width: hw, height: hh)
        case .bottomRight: return NSRect(x: a.maxX - hw, y: a.minY, width: hw, height: hh)
        }
    }

    private enum Region { case full, left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight }

    /// (front window region, window-behind region)
    private var regions: (Region, Region?)? {
        switch self {
        case .fill: return (.full, nil)
        case .left: return (.left, nil)
        case .right: return (.right, nil)
        case .top: return (.top, nil)
        case .bottom: return (.bottom, nil)
        case .topLeft: return (.topLeft, nil)
        case .topRight: return (.topRight, nil)
        case .bottomLeft: return (.bottomLeft, nil)
        case .bottomRight: return (.bottomRight, nil)
        case .leftRight: return (.left, .right)
        case .rightLeft: return (.right, .left)
        case .topBottom: return (.top, .bottom)
        case .bottomTop: return (.bottom, .top)
        case .center, .restore: return nil
        }
    }

    func perform() {
        guard AXIsProcessTrusted(), let win = WindowMover.focusedWindow(), let f = WindowMover.frame(of: win),
              let screen = WindowMover.screen(containing: f) else { return }
        let area = screen.visibleFrame
        switch self {
        case .restore:
            if let prev = WindowMover.previousFrame(of: win) { WindowMover.setFrame(win, to: prev, remember: false) }
        case .center:
            let w = min(f.width, area.width), h = min(f.height, area.height)
            WindowMover.setFrame(win, to: NSRect(x: (area.midX - w / 2).rounded(), y: (area.midY - h / 2).rounded(),
                                                 width: w, height: h))
        default:
            guard let (front, back) = regions else { return }
            WindowMover.setFrame(win, to: rect(front, in: area), anchorRight: front == .right || front == .topRight || front == .bottomRight)
            if let back, let other = WindowMover.windowBehindFront(excluding: win, on: screen) {
                WindowMover.setFrame(other, to: rect(back, in: area), anchorRight: back == .right)
            }
        }
    }
}

enum WindowMover {
    // AX uses a top-left origin on the primary screen; AppKit uses bottom-left.
    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }
    static func toAppKit(_ r: CGRect) -> NSRect { NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height) }
    static func toAX(_ r: NSRect) -> CGRect { CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height) }

    /// Its messaging timeout becomes the default, so a hung app can't block us for long.
    private static let systemWide: AXUIElement = {
        let el = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(el, 1.0)
        return el
    }()

    static func focusedWindow() -> AXUIElement? {
        _ = systemWide
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier),
                                            kAXFocusedWindowAttribute as CFString, &v) == .success,
              let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func frame(of w: AXUIElement) -> NSRect? {
        var p: CFTypeRef?, s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &s) == .success,
              let p, let s, CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &pos), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return toAppKit(CGRect(origin: pos, size: size))
    }

    static func screen(containing r: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSPoint(x: r.midX, y: r.midY)) } ?? NSScreen.main
    }

    // Frames before Keysy's last move, for "Restore Previous Size".
    private static var history: [(AXUIElement, NSRect)] = []

    static func previousFrame(of w: AXUIElement) -> NSRect? {
        guard let i = history.lastIndex(where: { CFEqual($0.0, w) }) else { return nil }
        return history.remove(at: i).1
    }

    static func setFrame(_ w: AXUIElement, to target: NSRect, anchorRight: Bool = false, remember: Bool = true) {
        if remember, let cur = frame(of: w) {
            history.removeAll { CFEqual($0.0, w) }
            history.append((w, cur))
            if history.count > 50 { history.removeFirst() }
        }
        var r = toAX(target)
        func setSize() { if let v = AXValueCreate(.cgSize, &r.size) { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, v) } }
        // Size, position, size again: some apps clamp the size based on position.
        setSize()
        if let v = AXValueCreate(.cgPoint, &r.origin) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, v) }
        setSize()
        // Apps with a larger minimum size: keep the right edge flush.
        if anchorRight, let actual = frame(of: w), abs(actual.width - target.width) > 1 {
            var o = toAX(NSRect(x: target.maxX - actual.width, y: target.minY, width: actual.width, height: actual.height)).origin
            if let v = AXValueCreate(.cgPoint, &o) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, v) }
        }
    }

    /// The next normal window below the focused one (z-order) on the same screen.
    static func windowBehindFront(excluding front: AXUIElement, on screen: NSScreen) -> AXUIElement? {
        guard let frontFrame = frame(of: front),
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let myPID = ProcessInfo.processInfo.processIdentifier
        var skippedFront = false
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != myPID,
                  let b = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let bw = b["Width"], let bh = b["Height"], bw > 50, bh > 50 else { continue }
            let bounds = toAppKit(CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: bw, height: bh))
            if !skippedFront, bounds.equalTo(frontFrame) || abs(bounds.minX - frontFrame.minX) + abs(bounds.minY - frontFrame.minY) < 2 {
                skippedFront = true; continue
            }
            guard screen.frame.intersects(bounds) else { continue }
            if let w = axWindow(pid: pid, matching: bounds), !CFEqual(w, front) { return w }
        }
        return nil
    }

    private static func axWindow(pid: pid_t, matching bounds: NSRect) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &v) == .success,
              let wins = v as? [AXUIElement] else { return nil }
        return wins.first { w in
            guard let f = frame(of: w) else { return false }
            return abs(f.minX - bounds.minX) < 2 && abs(f.minY - bounds.minY) < 2
                && abs(f.width - bounds.width) < 2 && abs(f.height - bounds.height) < 2
        }
    }
}

/// User-chosen global shortcuts for window commands. Nothing is assigned by default.
final class WindowShortcutStore: ObservableObject {
    static let shared = WindowShortcutStore()
    private static let key = "windowShortcuts"

    @Published private(set) var shortcuts: [WindowCommand: KeyCombo] = [:]

    private init() {
        if let d = UserDefaults.standard.data(forKey: Self.key),
           let s = try? JSONDecoder().decode([String: KeyCombo].self, from: d) {
            for (k, v) in s { if let c = WindowCommand(rawValue: k) { shortcuts[c] = v } }
        }
        LegacyAppShortcuts.migrate(into: self)
    }

    func set(_ combo: KeyCombo?, for c: WindowCommand) {
        shortcuts[c] = combo
        let raw = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
        if let d = try? JSONEncoder().encode(raw) { UserDefaults.standard.set(d, forKey: Self.key) }
        NotificationCenter.default.post(name: RuleStore.changed, object: nil)
    }

    var table: [KeyCombo: WindowCommand] {
        var t: [KeyCombo: WindowCommand] = [:]
        for c in WindowCommand.allCases { if let k = shortcuts[c], t[k] == nil { t[k] = c } }
        return t
    }
}

/// Earlier Keysy builds wrote window shortcuts into macOS App Shortcuts (NSUserKeyEquivalents).
/// Those only worked in apps with a Window menu after relaunch; move them to Keysy's global
/// shortcuts and remove them from macOS.
enum LegacyAppShortcuts {
    private static let names: [(String, WindowCommand)] = [
        ("Fill", .fill), ("Center", .center), ("Left", .left), ("Right", .right), ("Top", .top), ("Bottom", .bottom),
        ("Left & Right", .leftRight), ("Right & Left", .rightLeft), ("Top & Bottom", .topBottom),
        ("Bottom & Top", .bottomTop), ("Return to Previous Size", .restore),
        ("Left & Quarters", .left), ("Right & Quarters", .right), ("Top & Quarters", .top), ("Bottom & Quarters", .bottom),
    ]

    static func migrate(into store: WindowShortcutStore) {
        guard !UserDefaults.standard.bool(forKey: "legacyAppShortcutsMigrated") else { return }
        UserDefaults.standard.set(true, forKey: "legacyAppShortcutsMigrated")
        let key = "NSUserKeyEquivalents" as CFString
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard var eq = CFPreferencesCopyValue(key, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser,
                                              kCFPreferencesAnyHost) as? [String: Any] else { return }
        var changed = false
        for (name, cmd) in names {
            let variants = [name, "\u{1b}Window\u{1b}\(name)", "\u{1b}Window\u{1b}Move & Resize\u{1b}\(name)"]
            for v in variants {
                guard let s = eq[v] as? String else { continue }
                if store.shortcuts[cmd] == nil, let combo = parse(s) { store.set(combo, for: cmd) }
                eq[v] = nil; changed = true
            }
        }
        // Localized (e.g. Japanese) path variants written by the previous build.
        for k in eq.keys where k.hasPrefix("\u{1b}") && k.contains("\u{1b}") {
            let parts = k.split(separator: "\u{1b}")
            if parts.count >= 2, ["ウインドウ", "Window"].contains(String(parts[0])) { eq[k] = nil; changed = true }
        }
        UserDefaults.standard.removeObject(forKey: "systemShortcuts")
        UserDefaults.standard.removeObject(forKey: "systemShortcutOriginals")
        guard changed else { return }
        CFPreferencesSetValue(key, eq.isEmpty ? nil : eq as CFDictionary, kCFPreferencesAnyApplication,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    /// "@^\u{F702}" → ⌃⌘←
    private static func parse(_ s: String) -> KeyCombo? {
        var mods: UInt64 = 0, rest = Substring(s)
        let map: [Character: CGEventFlags] = ["@": .maskCommand, "^": .maskControl, "~": .maskAlternate, "$": .maskShift]
        while rest.count > 1, let c = rest.first, let f = map[c] { mods |= f.rawValue; rest = rest.dropFirst() }
        let arrows: [String: Int] = ["\u{F700}": 126, "\u{F701}": 125, "\u{F702}": 123, "\u{F703}": 124]
        guard let code = arrows[String(rest)] else { return nil }
        return KeyCombo(keyCode: code, modifiers: mods)
    }
}
