import AppKit
import Combine

struct Rule: Codable, Identifiable, Hashable {
    var id = UUID()
    var enabled = true
    var from: KeyCombo?
    var to: KeyCombo?

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
    var table: [KeyCombo: KeyCombo] {
        var t: [KeyCombo: KeyCombo] = [:]
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

    /// Start empty: every user sets up their own remaps.
    static var defaultRules: [Rule] { [] }
}
