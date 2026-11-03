import AppKit
import Carbon.HIToolbox

/// A macOS built-in feature whose keyboard shortcut Keysy can change.
///
/// Keysy does not trigger these itself: it writes the shortcut into macOS's own settings,
/// exactly where System Settings ▸ Keyboard ▸ Keyboard Shortcuts stores it.
/// - Menu commands (window tiling) → App Shortcuts (`NSUserKeyEquivalents`, All Applications)
/// - System hotkeys (screenshots, input sources) → `com.apple.symbolichotkeys`
struct SystemFeature: Identifiable, Hashable {
    enum Group: String, CaseIterable, Identifiable {
        case window = "Window"
        case screenshots = "Screenshots"
        case inputSources = "Input Sources"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .window: return "macwindow"
            case .screenshots: return "camera.viewfinder"
            case .inputSources: return "globe"
            }
        }
    }

    enum Backend: Hashable {
        /// AppKit menu command, identified by its key in AppKit's MenuCommands localization table.
        case menuCommand(String)
        /// Symbolic hotkey id in com.apple.symbolichotkeys.
        case symbolicHotKey(Int)
    }

    let group: Group
    let backend: Backend
    let englishTitle: String
    /// macOS's factory shortcut (for display).
    let macDefault: KeyCombo

    var id: String {
        switch backend {
        case .menuCommand(let k): return "menu:\(k)"
        case .symbolicHotKey(let n): return "hotkey:\(n)"
        }
    }

    var title: String {
        if case .menuCommand(let key) = backend { return MenuTitles.localized(key) }
        return englishTitle
    }

    // MARK: Catalog

    static let all: [SystemFeature] = {
        let fnCtrl = CGEventFlags.maskSecondaryFn.rawValue | CGEventFlags.maskControl.rawValue
        let cmd = CGEventFlags.maskCommand.rawValue, ctrl = CGEventFlags.maskControl.rawValue
        let opt = CGEventFlags.maskAlternate.rawValue, shift = CGEventFlags.maskShift.rawValue
        func menu(_ key: String, _ code: Int, _ mods: UInt64) -> SystemFeature {
            SystemFeature(group: .window, backend: .menuCommand(key), englishTitle: key,
                          macDefault: KeyCombo(keyCode: code, modifiers: mods))
        }
        func hot(_ g: Group, _ id: Int, _ title: String, _ code: Int, _ mods: UInt64) -> SystemFeature {
            SystemFeature(group: g, backend: .symbolicHotKey(id), englishTitle: title,
                          macDefault: KeyCombo(keyCode: code, modifiers: mods))
        }
        return [
            menu("Fill", kVK_ANSI_F, fnCtrl),
            menu("Center", kVK_ANSI_C, fnCtrl),
            menu("Left", kVK_LeftArrow, ctrl),
            menu("Right", kVK_RightArrow, ctrl),
            menu("Top", kVK_UpArrow, ctrl),
            menu("Bottom", kVK_DownArrow, ctrl),
            menu("Left & Right", kVK_LeftArrow, ctrl | shift),
            menu("Right & Left", kVK_RightArrow, ctrl | shift),
            menu("Top & Bottom", kVK_UpArrow, ctrl | shift),
            menu("Bottom & Top", kVK_DownArrow, ctrl | shift),
            menu("Left & Quarters", kVK_LeftArrow, ctrl | shift | opt),
            menu("Right & Quarters", kVK_RightArrow, ctrl | shift | opt),
            menu("Top & Quarters", kVK_UpArrow, ctrl | shift | opt),
            menu("Bottom & Quarters", kVK_DownArrow, ctrl | shift | opt),
            menu("Return to Previous Size", kVK_ANSI_R, fnCtrl),
            hot(.screenshots, 28, "Save picture of screen as a file", kVK_ANSI_3, shift | cmd),
            hot(.screenshots, 29, "Copy picture of screen to the clipboard", kVK_ANSI_3, ctrl | shift | cmd),
            hot(.screenshots, 30, "Save picture of selected area as a file", kVK_ANSI_4, shift | cmd),
            hot(.screenshots, 31, "Copy picture of selected area to the clipboard", kVK_ANSI_4, ctrl | shift | cmd),
            hot(.screenshots, 184, "Screenshot and recording options", kVK_ANSI_5, shift | cmd),
            hot(.inputSources, 60, "Select the previous input source", kVK_Space, ctrl),
            hot(.inputSources, 61, "Select next source in Input menu", kVK_Space, ctrl | opt),
        ]
    }()

    /// macOS's window-tiling defaults use 🌐 on arrows too; arrows always carry fn internally,
    /// so show it explicitly for clarity.
    var macDefaultDisplay: String {
        if group == .window && KeyCombo.arrowKeys.contains(macDefault.keyCode) { return "🌐" + macDefault.display }
        return macDefault.display
    }
}

/// Localized titles of AppKit's standard menu commands, read from AppKit's own localization table.
enum MenuTitles {
    private static let table: [String: [String: String]] = {
        let url = URL(fileURLWithPath: "/System/Library/Frameworks/AppKit.framework/Resources/MenuCommands.loctable")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return plist.compactMapValues { $0 as? [String: String] }
    }()

    private static let language: String? = {
        let langs = table.keys.filter { $0 != "LocProvenance" }
        return Bundle.preferredLocalizations(from: Array(langs), forPreferences: Locale.preferredLanguages).first
    }()

    static func localized(_ key: String) -> String {
        guard let lang = language, let s = table[lang]?[key] else { return key }
        return s
    }

    /// Menu path (AppKit table keys) of a window command: Window ▸ [Move & Resize ▸] item.
    static func path(_ key: String) -> [String] {
        ["Fill", "Center"].contains(key) ? ["Window", key] : ["Window", "Move & Resize", key]
    }

    /// App Shortcuts keys to register, as full menu paths ("\u{1b}Window\u{1b}Move & Resize\u{1b}Left") so
    /// unrelated items with the same title (e.g. View ▸ Left) are not affected.
    /// Both the user's language and English (apps without that localization show English menus).
    static func registrationKeys(_ key: String) -> [String] {
        let english = path(key).map { "\u{1b}" + $0 }.joined()
        let local = path(key).map { "\u{1b}" + localized($0) }.joined()
        return local == english ? [english] : [local, english]
    }

    /// Plain-title keys written by earlier Keysy versions (cleaned up on change/reset).
    static func legacyKeys(_ key: String) -> [String] {
        let l = localized(key)
        return l == key ? [key] : [l, key]
    }
}

// MARK: - Reading / writing macOS settings

/// State of one feature's shortcut, read live from macOS's settings.
enum ShortcutState: Equatable {
    case macDefault             // untouched: macOS's official shortcut
    case custom(String)         // changed (by Keysy or System Settings)
    case off                    // disabled in System Settings
}

final class SystemShortcutStore: ObservableObject {
    static let shared = SystemShortcutStore()

    /// Set after a window command changes: apps that are already running only pick it up after relaunch.
    @Published var needsAppRelaunch = false

    private init() { migrateLegacyKeys() }

    /// Earlier versions registered window commands by bare title, which also hit unrelated items
    /// such as View ▸ Left. Move those to full menu paths.
    private func migrateLegacyKeys() {
        var eq = Self.keyEquivalents()
        var changed = false
        for f in SystemFeature.all {
            guard case .menuCommand(let key) = f.backend else { continue }
            let value = MenuTitles.legacyKeys(key).lazy.compactMap { eq[$0] as? String }.first
            guard let value else { continue }
            for t in MenuTitles.legacyKeys(key) { eq[t] = nil }
            for t in MenuTitles.registrationKeys(key) where eq[t] == nil { eq[t] = value }
            changed = true
        }
        if changed { Self.writeKeyEquivalents(eq); needsAppRelaunch = true }
    }

    private static let hotKeysDomain = "com.apple.symbolichotkeys" as CFString
    private static let hotKeysKey = "AppleSymbolicHotKeys" as CFString
    private static let keyEquivalentsKey = "NSUserKeyEquivalents" as CFString

    func state(_ f: SystemFeature) -> ShortcutState {
        switch f.backend {
        case .symbolicHotKey(let id):
            guard let entry = Self.hotKeys()[String(id)] as? [String: Any] else { return .macDefault }
            if !Self.isEnabled(entry) { return .off }
            guard let combo = Self.combo(fromHotKeyEntry: entry) else { return .macDefault }
            return combo == f.macDefault ? .macDefault : .custom(combo.display)
        case .menuCommand(let key):
            let eq = Self.keyEquivalents()
            for t in MenuTitles.registrationKeys(key) + MenuTitles.legacyKeys(key) {
                if let s = eq[t] as? String { return .custom(Self.displayKeyEquivalent(s)) }
            }
            return .macDefault
        }
    }

    func set(_ combo: KeyCombo, for f: SystemFeature) {
        objectWillChange.send()
        switch f.backend {
        case .symbolicHotKey(let id):
            var all = Self.hotKeys()
            all[String(id)] = Self.hotKeyEntry(for: combo)
            Self.writeHotKeys(all)
        case .menuCommand(let key):
            var eq = Self.keyEquivalents()
            let s = Self.keyEquivalentString(for: combo)
            for t in MenuTitles.legacyKeys(key) { eq[t] = nil }
            for t in MenuTitles.registrationKeys(key) { eq[t] = s }
            Self.writeKeyEquivalents(eq)
            needsAppRelaunch = true
        }
    }

    /// Puts the feature back on macOS's official shortcut.
    func resetToDefault(_ f: SystemFeature) {
        objectWillChange.send()
        switch f.backend {
        case .symbolicHotKey(let id):
            var all = Self.hotKeys()
            all[String(id)] = Self.hotKeyEntry(for: f.macDefault)
            Self.writeHotKeys(all)
        case .menuCommand(let key):
            var eq = Self.keyEquivalents()
            for t in MenuTitles.registrationKeys(key) + MenuTitles.legacyKeys(key) { eq[t] = nil }
            Self.writeKeyEquivalents(eq)
            needsAppRelaunch = true
        }
    }

    /// Finder is always running, so offer to relaunch it (it has no unsaved documents).
    func relaunchFinder() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["Finder"]
        try? p.run()
    }

    // MARK: symbolic hotkeys

    private static func hotKeys() -> [String: Any] {
        CFPreferencesAppSynchronize(hotKeysDomain)
        return CFPreferencesCopyAppValue(hotKeysKey, hotKeysDomain) as? [String: Any] ?? [:]
    }

    private static func isEnabled(_ entry: [String: Any]) -> Bool {
        if let b = entry["enabled"] as? Bool { return b }
        if let n = entry["enabled"] as? Int { return n != 0 }
        return true
    }

    private static func writeHotKeys(_ all: [String: Any]) {
        CFPreferencesSetAppValue(hotKeysKey, all as CFDictionary, hotKeysDomain)
        CFPreferencesAppSynchronize(hotKeysDomain)
        // Ask macOS to reload keyboard shortcut settings (what System Settings does).
        let tool = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
        guard FileManager.default.isExecutableFile(atPath: tool) else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = ["-u"]
        try? p.run()
    }

    private static func hotKeyEntry(for c: KeyCombo) -> [String: Any] {
        var flags = c.modifiers
        if KeyCombo.implicitFnKeys.contains(c.keyCode) { flags |= CGEventFlags.maskSecondaryFn.rawValue }
        var ch = 65535
        if c.keyCode == kVK_Space { ch = 32 }
        else if let s = KeyCombo.character(c.keyCode)?.lowercased(), s.unicodeScalars.count == 1,
                let u = s.unicodeScalars.first, u.isASCII, u.value >= 32 { ch = Int(u.value) }
        return ["enabled": true,
                "value": ["type": "standard", "parameters": [ch, c.keyCode, Int(flags)]]]
    }

    private static func combo(fromHotKeyEntry e: [String: Any]) -> KeyCombo? {
        guard let v = e["value"] as? [String: Any], let p = v["parameters"] as? [Int], p.count == 3 else { return nil }
        return KeyCombo.normalized(keyCode: p[1], flags: UInt64(p[2]))
    }

    // MARK: App Shortcuts (NSUserKeyEquivalents, All Applications)

    private static func keyEquivalents() -> [String: Any] {
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return CFPreferencesCopyValue(keyEquivalentsKey, kCFPreferencesAnyApplication,
                                      kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String: Any] ?? [:]
    }

    private static func writeKeyEquivalents(_ eq: [String: Any]) {
        CFPreferencesSetValue(keyEquivalentsKey, eq.isEmpty ? nil : eq as CFDictionary,
                              kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    private static let specialEquivalents: [Int: String] = {
        var m: [Int: String] = [
            kVK_UpArrow: "\u{F700}", kVK_DownArrow: "\u{F701}", kVK_LeftArrow: "\u{F702}", kVK_RightArrow: "\u{F703}",
            kVK_Home: "\u{F729}", kVK_End: "\u{F72B}", kVK_PageUp: "\u{F72C}", kVK_PageDown: "\u{F72D}",
            kVK_ForwardDelete: "\u{F728}", kVK_Delete: "\u{8}", kVK_Return: "\r", kVK_Tab: "\t",
            kVK_Escape: "\u{1B}", kVK_Space: " ",
        ]
        for (i, code) in KeyCombo.fKeys.enumerated() { m[code] = String(UnicodeScalar(0xF704 + i)!) }
        return m
    }()

    /// Format used by App Shortcuts: @ ⌘, ^ ⌃, ~ ⌥, $ ⇧, then the key character.
    static func keyEquivalentString(for c: KeyCombo) -> String {
        var s = ""
        if c.modifiers & CGEventFlags.maskCommand.rawValue != 0 { s += "@" }
        if c.modifiers & CGEventFlags.maskControl.rawValue != 0 { s += "^" }
        if c.modifiers & CGEventFlags.maskAlternate.rawValue != 0 { s += "~" }
        if c.modifiers & CGEventFlags.maskShift.rawValue != 0 { s += "$" }
        return s + (specialEquivalents[c.keyCode] ?? KeyCombo.character(c.keyCode)?.lowercased() ?? "")
    }

    static func displayKeyEquivalent(_ s: String) -> String {
        var mods = "", rest = Substring(s)
        let map: [Character: String] = ["^": "⌃", "~": "⌥", "$": "⇧", "@": "⌘"]
        while let c = rest.first, let sym = map[c], rest.count > 1 { mods += sym; rest = rest.dropFirst() }
        let key = String(rest)
        let names: [String: String] = ["\u{F700}": "↑", "\u{F701}": "↓", "\u{F702}": "←", "\u{F703}": "→",
                                       "\u{F729}": "↖", "\u{F72B}": "↘", "\u{F72C}": "⇞", "\u{F72D}": "⇟",
                                       " ": "Space", "\t": "⇥", "\r": "↩", "\u{8}": "⌫", "\u{1B}": "⎋"]
        let order: [Character] = ["⌃", "⌥", "⇧", "⌘"]
        let sortedMods = String(mods.sorted { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! })
        return sortedMods + (names[key] ?? key.uppercased())
    }
}
