import AppKit
import SwiftUI
import Combine
import ServiceManagement

// MARK: - Key recorder

/// Coordinates recording so only one field records at a time and remapping pauses meanwhile.
final class RecordingCenter: ObservableObject {
    static let shared = RecordingCenter()
    @Published private(set) var activeID: String?
    @Published var liveModifiers: UInt64 = 0
    private var monitor: Any?
    private var onCapture: ((KeyCombo) -> Void)?

    func begin(id: String, onCapture: @escaping (KeyCombo) -> Void) {
        end()
        activeID = id
        liveModifiers = 0
        self.onCapture = onCapture
        Remapper.shared.suspended = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] e in
            guard let self else { return e }
            let flags = KeyCombo.cgFlags(from: e.modifierFlags)
            if e.type == .flagsChanged {
                self.liveModifiers = flags
                return nil
            }
            let code = Int(e.keyCode)
            if code == 53 && flags == 0 { self.end(); return nil }   // plain Esc cancels
            guard !KeyCombo.modifierKeyCodes.contains(code) else { return nil }
            let combo = KeyCombo.normalized(keyCode: code, flags: flags)
            let cb = self.onCapture
            self.end()
            cb?(combo)
            return nil
        }
    }

    func end() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        onCapture = nil
        activeID = nil
        liveModifiers = 0
        Remapper.shared.suspended = false
    }
}

struct KeyRecorderField: View {
    let id: String
    let combo: KeyCombo?
    let placeholder: String
    /// Overrides the dimmed look used for an empty field (nil = dim when `combo` is nil).
    var dimmed: Bool? = nil
    let onCapture: (KeyCombo) -> Void
    @ObservedObject private var center = RecordingCenter.shared

    var body: some View {
        let recording = center.activeID == id
        Button {
            recording ? center.end() : center.begin(id: id, onCapture: onCapture)
        } label: {
            Text(label(recording: recording))
                .font(.system(.body, design: .rounded).weight(combo == nil && !recording ? .regular : .medium))
                .foregroundStyle(recording ? Color.accentColor : ((dimmed ?? (combo == nil)) ? .secondary : .primary))
                .frame(minWidth: 130)
                .padding(.vertical, 4).padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(recording ? Color.accentColor : Color.secondary.opacity(0.35),
                                      lineWidth: recording ? 2 : 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click, then type the key combination. Esc cancels.")
    }

    private func label(recording: Bool) -> String {
        if recording {
            let m = KeyCombo.modifierSymbols(center.liveModifiers)
            return m.isEmpty ? "Type keys…" : m + "…"
        }
        return combo?.display ?? placeholder
    }
}

// MARK: - Rules

struct RuleRow: View {
    @Binding var rule: Rule
    let duplicate: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $rule.enabled).labelsHidden().toggleStyle(.checkbox)
            KeyRecorderField(id: "\(rule.id)-from", combo: rule.from, placeholder: "Record trigger") {
                rule.from = $0
            }
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            KeyRecorderField(id: "\(rule.id)-to", combo: rule.to, placeholder: "Record output") {
                rule.to = $0
            }
            if duplicate {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .help("Another enabled rule uses the same trigger; the first one wins.")
            }
            Spacer(minLength: 0)
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless).help("Delete this remap")
        }
        .opacity(rule.enabled ? 1 : 0.5)
    }
}

struct RemapsView: View {
    @ObservedObject var store = RuleStore.shared
    @State private var trusted = AXIsProcessTrusted()
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Toggle("Enable key remapping", isOn: $store.enabled).toggleStyle(.switch)
                Spacer()
                if !trusted {
                    Label("Accessibility permission required", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button("Open Settings") { Permissions.openAccessibilitySettings() }
                }
            }
            HStack {
                Text("Trigger").frame(minWidth: 160, alignment: .leading).padding(.leading, 26)
                Text("Output").padding(.leading, 30)
            }
            .font(.caption).foregroundStyle(.secondary)
            if store.rules.isEmpty {
                Text("No remaps yet. Click “Add Remap”, then type the trigger and output keys.")
                    .foregroundStyle(.secondary).padding(.vertical, 12)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    let dups = store.duplicateTriggers
                    ForEach($store.rules) { $rule in
                        RuleRow(rule: $rule, duplicate: rule.from.map { dups.contains($0) } ?? false) {
                            RecordingCenter.shared.end()
                            store.rules.removeAll { $0.id == rule.id }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            HStack {
                Button { store.addEmpty() } label: { Label("Add Remap", systemImage: "plus") }
                Spacer()
            }
            Text("Click a field and type the keys. Pressing the trigger sends the output keys instead.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .onReceive(timer) { _ in trusted = AXIsProcessTrusted() }
    }
}

// MARK: - macOS built-in shortcuts

struct SystemFeatureRow: View {
    let feature: SystemFeature
    @ObservedObject var store = SystemShortcutStore.shared

    var body: some View {
        let state = store.state(feature)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .help(feature.englishTitle == feature.title ? "" : feature.englishTitle)
                Text("macOS default: \(feature.macDefaultDisplay)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            badge(state)
            KeyRecorderField(id: feature.id, combo: nil, placeholder: text(state),
                             dimmed: state == .macDefault) {
                store.set($0, for: feature)
            }
            Button { RecordingCenter.shared.end(); store.resetToDefault(feature) } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .help("Reset to the macOS default (\(feature.macDefaultDisplay))")
            .opacity(state == .macDefault ? 0 : 1).disabled(state == .macDefault)
        }
    }

    private func text(_ s: ShortcutState) -> String {
        switch s {
        case .macDefault: return feature.macDefaultDisplay
        case .custom(let d): return d
        case .off: return "Off"
        }
    }

    @ViewBuilder private func badge(_ s: ShortcutState) -> some View {
        switch s {
        case .macDefault:
            Text("Default").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
        case .custom:
            Text("Custom").font(.caption2.weight(.semibold)).foregroundStyle(Color.accentColor)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
        case .off:
            Text("Off").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Color.orange.opacity(0.15)))
        }
    }
}

struct SystemShortcutsView: View {
    @ObservedObject var store = SystemShortcutStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.needsAppRelaunch {
                HStack(alignment: .top) {
                    Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(.orange)
                    Text("Window shortcuts take effect in apps opened from now on. Quit and reopen apps that are already running (macOS reads these shortcuts only at app launch).")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Relaunch Finder") { store.relaunchFinder() }
                    Button { store.needsAppRelaunch = false } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                }
                .font(.callout)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
                .padding(.horizontal, 16).padding(.top, 8)
            }
            Form {
                ForEach(SystemFeature.Group.allCases) { group in
                    Section {
                        ForEach(SystemFeature.all.filter { $0.group == group }) { SystemFeatureRow(feature: $0) }
                    } header: {
                        Label(group.rawValue, systemImage: group.symbol)
                    }
                }
            }
            .formStyle(.grouped)
            Text("Click a shortcut and type new keys to change it in macOS itself (System Settings ▸ Keyboard ▸ Keyboard Shortcuts). “Default” = macOS's official shortcut; ↩︎ resets a row to it.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.bottom, 12)
        }
    }
}

struct GeneralView: View {
    @State private var autoUpdate = Updater.autoCheckEnabled
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                    catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                }
            HStack {
                Toggle("Check for updates automatically", isOn: $autoUpdate)
                    .onChange(of: autoUpdate) { _, v in Updater.autoCheckEnabled = v }
                Spacer()
                Button("Check Now") { Updater.shared.check(userInitiated: true) }
            }
            HStack {
                Text("Version \(Updater.currentVersion)").foregroundStyle(.secondary)
                Spacer()
                Link("GitHub", destination: Links.repository)
                Link("♥ Sponsor", destination: Links.sponsor)
            }
        }
        .formStyle(.grouped)
    }
}

struct SettingsView: View {
    @AppStorage("settingsTab") private var tab = "remaps"

    var body: some View {
        TabView(selection: $tab) {
            RemapsView().tabItem { Label("Key Remaps", systemImage: "keyboard") }.tag("remaps")
            SystemShortcutsView().tabItem { Label("macOS Shortcuts", systemImage: "apple.logo") }.tag("system")
            GeneralView().tabItem { Label("General", systemImage: "gearshape") }.tag("general")
        }
        .padding(12)
        .frame(minWidth: 620, minHeight: 520)
        .onDisappear { RecordingCenter.shared.end() }
    }
}

enum Permissions {
    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init() {
        let host = NSHostingController(rootView: SettingsView())
        let win = NSWindow(contentViewController: host)
        win.title = "Keysy Settings"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.setContentSize(NSSize(width: 640, height: 560))
        super.init(window: win)
        win.delegate = self
        win.center()
    }
    required init?(coder: NSCoder) { fatalError() }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { RecordingCenter.shared.end() }
}
