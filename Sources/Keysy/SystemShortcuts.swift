import AppKit
import Carbon.HIToolbox

/// A macOS built-in feature whose keyboard shortcut Keysy can change.
///
/// Keysy does not trigger these itself: it writes the shortcut into macOS's own settings,
/// exactly where System Settings ▸ Keyboard ▸ Keyboard Shortcuts stores it.
/// (`com.apple.symbolichotkeys`). These are true system-wide shortcuts.
struct SystemFeature: Identifiable, Hashable {
    enum Group: String, CaseIterable, Identifiable {
        case screenshots = "Screenshots"
        case inputSources = "Input Sources"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .screenshots: return "camera.viewfinder"
            case .inputSources: return "globe"
            }
        }
    }

    enum Backend: Hashable {
        /// Symbolic hotkey id in com.apple.symbolichotkeys.
        case symbolicHotKey(Int)
    }

    let group: Group
    let backend: Backend
    let englishTitle: String
    /// macOS's factory shortcut; nil when macOS assigns none.
    let macDefault: KeyCombo?

    var id: String {
        switch backend {
        case .symbolicHotKey(let n): return "hotkey:\(n)"
        }
    }

    var title: String { englishTitle }

    // MARK: Catalog

    static let all: [SystemFeature] = {
        let fnCtrl = CGEventFlags.maskSecondaryFn.rawValue | CGEventFlags.maskControl.rawValue
        let cmd = CGEventFlags.maskCommand.rawValue, ctrl = CGEventFlags.maskControl.rawValue
        let opt = CGEventFlags.maskAlternate.rawValue, shift = CGEventFlags.maskShift.rawValue
        func hot(_ g: Group, _ id: Int, _ title: String, _ code: Int, _ mods: UInt64) -> SystemFeature {
            SystemFeature(group: g, backend: .symbolicHotKey(id), englishTitle: title,
                          macDefault: KeyCombo(keyCode: code, modifiers: mods))
        }
        return [
            hot(.screenshots, 28, "Save picture of screen as a file", kVK_ANSI_3, shift | cmd),
            hot(.screenshots, 29, "Copy picture of screen to the clipboard", kVK_ANSI_3, ctrl | shift | cmd),
            hot(.screenshots, 30, "Save picture of selected area as a file", kVK_ANSI_4, shift | cmd),
            hot(.screenshots, 31, "Copy picture of selected area to the clipboard", kVK_ANSI_4, ctrl | shift | cmd),
            hot(.screenshots, 184, "Screenshot and recording options", kVK_ANSI_5, shift | cmd),
            hot(.inputSources, 60, "Select the previous input source", kVK_Space, ctrl),
            hot(.inputSources, 61, "Select next source in Input menu", kVK_Space, ctrl | opt),
        ]
    }()

    var macDefaultDisplay: String {
        guard let d = macDefault else { return "None" }
        return d.display
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

    private init() {}

    private static let hotKeysDomain = "com.apple.symbolichotkeys" as CFString
    private static let hotKeysKey = "AppleSymbolicHotKeys" as CFString

    func state(_ f: SystemFeature) -> ShortcutState {
        switch f.backend {
        case .symbolicHotKey(let id):
            guard let entry = Self.hotKeys()[String(id)] as? [String: Any] else { return .macDefault }
            if !Self.isEnabled(entry) { return .off }
            guard let combo = Self.combo(fromHotKeyEntry: entry) else { return .macDefault }
            return combo == f.macDefault ? .macDefault : .custom(combo.display)
        }
    }

    func set(_ combo: KeyCombo, for f: SystemFeature) {
        objectWillChange.send()
        switch f.backend {
        case .symbolicHotKey(let id):
            var all = Self.hotKeys()
            all[String(id)] = Self.hotKeyEntry(for: combo)
            Self.writeHotKeys(all)
        }
    }

    /// Puts the feature back on macOS's official shortcut.
    func resetToDefault(_ f: SystemFeature) {
        objectWillChange.send()
        switch f.backend {
        case .symbolicHotKey(let id):
            var all = Self.hotKeys()
            all[String(id)] = f.macDefault.map(Self.hotKeyEntry(for:))
            Self.writeHotKeys(all)
        }
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

}
