import AppKit
import Carbon.HIToolbox
import Combine

/// What a remap produces.
enum RemapTarget: Codable, Hashable {
    case keys(KeyCombo)
    case window(WindowAction)

    var display: String {
        switch self {
        case .keys(let k): return k.display
        case .window(let w): return w.display
        }
    }

    /// Text-only form for menus, marking window actions so they don't read as key names.
    var menuDisplay: String {
        if case .window(let w) = self { return "🪟 " + w.display }
        return display
    }
}

struct Rule: Codable, Identifiable, Hashable {
    var id = UUID()
    var enabled = true
    var from: KeyCombo?
    var to: RemapTarget?

    var isComplete: Bool { from != nil && to != nil }
}

final class RuleStore: ObservableObject {
    static let shared = RuleStore()
    static let changed = Notification.Name("KeysyRulesChanged")
    private static let key = "rules"

    @Published var rules: [Rule] {
        didSet { save() }
    }

    /// Global on/off switch.
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "enabled")
            NotificationCenter.default.post(name: RuleStore.changed, object: nil)
        }
    }

    private init() {
        enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true
        if let d = UserDefaults.standard.data(forKey: RuleStore.key),
           let r = try? JSONDecoder().decode([Rule].self, from: d) {
            rules = r
        } else {
            rules = RuleStore.defaultRules
            save()
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(rules) { UserDefaults.standard.set(d, forKey: RuleStore.key) }
        NotificationCenter.default.post(name: RuleStore.changed, object: nil)
    }

    /// Active lookup table: first enabled, complete rule wins for each trigger.
    var table: [KeyCombo: RemapTarget] {
        var t: [KeyCombo: RemapTarget] = [:]
        for r in rules where r.enabled {
            guard let f = r.from, let to = r.to, t[f] == nil else { continue }
            t[f] = to
        }
        return t
    }

    /// Triggers that appear on more than one enabled rule.
    var duplicateTriggers: Set<KeyCombo> {
        var seen: Set<KeyCombo> = [], dup: Set<KeyCombo> = []
        for r in rules where r.enabled { if let f = r.from, !seen.insert(f).inserted { dup.insert(f) } }
        return dup
    }

    func addEmpty() { rules.append(Rule()) }

    func addWindowPresets() {
        let ctrlCmd = CGEventFlags.maskControl.rawValue | CGEventFlags.maskCommand.rawValue
        let presets: [(Int, WindowAction)] = [(kVK_LeftArrow, .left), (kVK_RightArrow, .right),
                                              (kVK_UpArrow, .fill), (kVK_DownArrow, .center)]
        let existing = Set(rules.compactMap(\.from))
        for (code, action) in presets {
            let from = KeyCombo(keyCode: code, modifiers: ctrlCmd)
            if !existing.contains(from) { rules.append(Rule(from: from, to: .window(action))) }
        }
    }

    /// Start empty: every user sets up their own remaps.
    static var defaultRules: [Rule] { [] }
}
