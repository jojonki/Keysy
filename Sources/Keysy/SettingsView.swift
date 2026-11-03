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
    let onCapture: (KeyCombo) -> Void
    @ObservedObject private var center = RecordingCenter.shared

    var body: some View {
        let recording = center.activeID == id
        Button {
            recording ? center.end() : center.begin(id: id, onCapture: onCapture)
        } label: {
            Text(label(recording: recording))
                .font(.system(.body, design: .rounded).weight(combo == nil && !recording ? .regular : .medium))
                .foregroundStyle(recording ? Color.accentColor : (combo == nil ? .secondary : .primary))
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
            targetEditor
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

    @ViewBuilder private var targetEditor: some View {
        switch rule.to {
        case .window(let action):
            Text(action.display)
                .frame(minWidth: 130).padding(.vertical, 4).padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.12)))
            targetMenu
        default:
            KeyRecorderField(id: "\(rule.id)-to", combo: currentKeys, placeholder: "Record output") {
                rule.to = .keys($0)
            }
            targetMenu
        }
    }

    private var currentKeys: KeyCombo? {
        if case .keys(let k) = rule.to { return k }
        return nil
    }

    private var targetMenu: some View {
        Menu {
            Button("Keystroke (record keys)") { rule.to = currentKeys.map { .keys($0) } }
            Divider()
            Section("macOS Window Tiling") {
                ForEach(WindowAction.allCases) { a in
                    Button(a.title) { rule.to = .window(a) }
                }
            }
        } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Choose a keystroke or a macOS window action as the output")
    }
}

struct SettingsView: View {
    @ObservedObject var store = RuleStore.shared
    @State private var trusted = AXIsProcessTrusted()
    @State private var autoUpdate = Updater.autoCheckEnabled
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Toggle("Enable Keysy", isOn: $store.enabled).toggleStyle(.switch)
                Spacer()
                if !trusted {
                    Label("Accessibility permission required", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button("Open Settings") { Permissions.openAccessibilitySettings() }
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Trigger").frame(minWidth: 160, alignment: .leading).padding(.leading, 26)
                        Text("Output").padding(.leading, 30)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    if store.rules.isEmpty {
                        Text("No remaps yet. Click “Add Remap” and type the keys you want.")
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
                    .frame(minHeight: 120, maxHeight: 360)
                    HStack {
                        Button { store.addEmpty() } label: { Label("Add Remap", systemImage: "plus") }
                        Button("Add Window Tiling Presets") { store.addWindowPresets() }
                            .help("Adds ⌃⌘←/→/↑/↓ → macOS Left / Right / Fill / Center")
                        Spacer()
                    }
                }
                .padding(6)
            } label: { Text("Key Remaps").font(.headline) }

            Text("Click a field and type the keys. Window actions use macOS's built-in tiling (Window ▸ Move & Resize).")
                .font(.caption).foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
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
                .padding(6)
            } label: { Text("General").font(.headline) }
        }
        .padding(20)
        .frame(minWidth: 600)
        .onReceive(timer) { _ in trusted = AXIsProcessTrusted() }
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
