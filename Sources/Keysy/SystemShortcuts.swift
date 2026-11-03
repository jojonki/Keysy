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

    /// Titles to register: the user's language and English (apps without that localization show English).
    static func registrationTitles(_ key: String) -> [String] {
        let l = localized(key)
        return l == key ? [key] : [l, key]
    }
}

// MARK: - Writing macOS settings

final class SystemShortcutStore: ObservableObject {
    static let shared = SystemShortcutStore()

    /// Features the user customized → the shortcut Keysy wrote.
    @Published private(set) var custom: [String: KeyCombo] = [:]
    @Published private(set) var lastError: String?

    private let customKey = "systemShortcuts"
    private let originalsKey = "systemShortcutOriginals"
    private static let hotKeysDomain = "com.apple.symbolichotkeys" as CFString
    private static let hotKeysKey = "AppleSymbolicHotKeys" as CFString
    private static let keyEquivalentsKey = "NSUserKeyEquivalents" as CFString

    private init() {
        if let d = UserDefaults.standard.data(forKey: customKey),
           let c = try? JSONDecoder().decode([String: KeyCombo].self, from: d) { custom = c }
    }

    func isCustom(_ f: SystemFeature) -> Bool { custom[f.id] != nil }

    /// What macOS currently uses for a feature that Keysy has not customized.
    func currentMacDisplay(_ f: SystemFeature) -> String {
        switch f.backend {
        case .symbolicHotKey(let id):
            guard let entry = Self.hotKeys()[String(id)] as? [String: Any] else { return f.macDefaultDisplay }
            if (entry["enabled"] as? Bool) == false || (entry["enabled"] as? Int) == 0 { return "Off" }
            if let combo = Self.combo(fromHotKeyEntry: entry) { return combo.display }
            return f.macDefaultDisplay
        case .menuCommand(let key):
            let eq = Self.keyEquivalents()
            for t in MenuTitles.registrationTitles(key) {
                if let s = eq[t] as? String { return Self.displayKeyEquivalent(s) }
            }
            return f.macDefaultDisplay
        }
    }

    func set(_ combo: KeyCombo, for f: SystemFeature) {
        switch f.backend {
        case .symbolicHotKey(let id):
            var all = Self.hotKeys()
            rememberOriginal(f, value: all[String(id)])
            all[String(id)] = Self.hotKeyEntry(for: combo)
            Self.writeHotKeys(all)
        case .menuCommand(let key):
            var eq = Self.keyEquivalents()
            let s = Self.keyEquivalentString(for: combo)
            for t in MenuTitles.registrationTitles(key) {
                rememberOriginal(f, value: eq[t], suffix: t)
                eq[t] = s
            }
            Self.writeKeyEquivalents(eq)
        }
        custom[f.id] = combo
        persist()
    }

    /// Restores whatever macOS had before Keysy changed it.
    func reset(_ f: SystemFeature) {
        guard custom[f.id] != nil else { return }
        switch f.backend {
        case .symbolicHotKey(let id):
            var all = Self.hotKeys()
            all[String(id)] = takeOriginal(f)
            Self.writeHotKeys(all)
        case .menuCommand(let key):
            var eq = Self.keyEquivalents()
            for t in MenuTitles.registrationTitles(key) { eq[t] = takeOriginal(f, suffix: t) }
            Self.writeKeyEquivalents(eq)
        }
        custom[f.id] = nil
        persist()
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(custom) { UserDefaults.standard.set(d, forKey: customKey) }
    }

    // Originals are stored once (the first time Keysy overrides a setting) so reset is exact.
    private func originalID(_ f: SystemFeature, _ suffix: String) -> String { suffix.isEmpty ? f.id : "\(f.id)|\(suffix)" }

    private func rememberOriginal(_ f: SystemFeature, value: Any?, suffix: String = "") {
        var o = UserDefaults.standard.dictionary(forKey: originalsKey) ?? [:]
        let k = originalID(f, suffix)
        guard o[k] == nil else { return }
        o[k] = value ?? "__absent__"
        UserDefaults.standard.set(o, forKey: originalsKey)
    }

    private func takeOriginal(_ f: SystemFeature, suffix: String = "") -> Any? {
        var o = UserDefaults.standard.dictionary(forKey: originalsKey) ?? [:]
        let k = originalID(f, suffix)
        let v = o.removeValue(forKey: k)
        UserDefaults.standard.set(o, forKey: originalsKey)
        if let s = v as? String, s == "__absent__" { return nil }
        return v
    }

    // MARK: symbolic hotkeys

    private static func hotKeys() -> [String: Any] {
        CFPreferencesAppSynchronize(hotKeysDomain)
        return CFPreferencesCopyAppValue(hotKeysKey, hotKeysDomain) as? [String: Any] ?? [:]
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
        let names: [String: String] = ["\u{F700}": "↑", "\u{F701}": "↓", "\u{F702}": "←", "\u{F703}": "→", " ": "Space", "\t": "⇥", "\r": "↩"]
        let order: [Character] = ["⌃", "⌥", "⇧", "⌘"]
        let sortedMods = String(mods.sorted { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! })
        return sortedMods + (names[key] ?? key.uppercased())
    }
}

#if DEBUG
extension SystemShortcutStore {
    /// Debug aid: round-trips a menu command and a symbolic hotkey through set/reset.
    static func selfTest() {
        let s = shared
        let opt = CGEventFlags.maskAlternate.rawValue, ctrl = CGEventFlags.maskControl.rawValue
        for f in SystemFeature.all where f.englishTitle == "Left & Right" || f.backend == .symbolicHotKey(184) {
            let before = s.currentMacDisplay(f)
            s.set(KeyCombo(keyCode: kVK_RightArrow, modifiers: ctrl | opt), for: f)
            let eq = keyEquivalents(), hk = hotKeys()["184"] ?? "-"
            print("[\(f.title)] before=\(before) custom=\(s.custom[f.id]!.display)")
            print("   NSUserKeyEquivalents=\(eq)")
            if f.group != .window { print("   hotkey184=\(hk)") }
            s.reset(f)
            print("   after reset: \(s.currentMacDisplay(f)) custom=\(s.custom[f.id].map(\.display) ?? "nil")")
        }
        print("NSUserKeyEquivalents final=\(keyEquivalents())")
        print("hotkey184 final=\(hotKeys()["184"] ?? "-")")
    }
}
#endif
