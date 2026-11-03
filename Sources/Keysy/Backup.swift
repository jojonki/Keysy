import AppKit
import UniformTypeIdentifiers

/// A macOS Features setting in a backup: a custom shortcut, or turned off.
enum FeatureSetting: Codable, Equatable {
    case shortcut(KeyCombo)
    case off

    // JSON: "off", or a key combo object {"keyCode": 18, "modifiers": 1310720}.
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self), s == "off" { self = .off; return }
        self = .shortcut(try c.decode(KeyCombo.self))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .off: try c.encode("off")
        case .shortcut(let k): try c.encode(k)
        }
    }
}

/// Everything you configured in Keysy, as a portable JSON file.
/// Key codes are physical key positions, so files move between Macs with the same keyboard layout type.
struct KeysyBackup: Codable {
    var format = "keysy-settings"
    var version = 1
    var exportedAt = Date()
    var appVersion = Updater.currentVersion
    var customShortcuts: [Rule]
    var windowLayouts: [String: KeyCombo]
    /// Only macOS features you changed; anything missing is the macOS default.
    var macOSFeatures: [String: FeatureSetting]

    static func current() -> KeysyBackup {
        KeysyBackup(customShortcuts: RuleStore.shared.rules,
                    windowLayouts: Dictionary(uniqueKeysWithValues: WindowShortcutStore.shared.shortcuts.map { ($0.key.rawValue, $0.value) }),
                    macOSFeatures: SystemShortcutStore.shared.exportSettings())
    }

    func apply() {
        RecordingCenter.shared.end()
        RuleStore.shared.rules = customShortcuts
        var w: [WindowCommand: KeyCombo] = [:]
        for (k, v) in windowLayouts { if let c = WindowCommand(rawValue: k) { w[c] = v } }
        WindowShortcutStore.shared.replaceAll(w)
        SystemShortcutStore.shared.importSettings(macOSFeatures)
    }

    var summary: String {
        "\(customShortcuts.count) custom shortcuts, \(windowLayouts.count) window layouts, \(macOSFeatures.count) changed macOS features"
    }
}

enum BackupIO {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    static func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let date = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        panel.nameFieldStringValue = "Keysy Settings \(date).json"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try encoder.encode(KeysyBackup.current()).write(to: url, options: .atomic)
        } catch {
            alert("Couldn't export settings", error.localizedDescription)
        }
    }

    static func importFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let backup: KeysyBackup
        do {
            backup = try decoder.decode(KeysyBackup.self, from: Data(contentsOf: url))
            guard backup.format == "keysy-settings" else { throw CocoaError(.fileReadCorruptFile) }
        } catch {
            alert("Couldn't read this file", "It isn't a Keysy settings file, or it is damaged.")
            return
        }
        let a = NSAlert()
        a.messageText = "Replace your current settings?"
        a.informativeText = "This file has \(backup.summary). Your current Custom Shortcuts, Window Layouts and macOS Features will be replaced with it."
        a.addButton(withTitle: "Replace")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        backup.apply()
    }

    private static func alert(_ title: String, _ text: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = text; a.runModal()
    }
}
