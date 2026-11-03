import AppKit
import SwiftUI
import Combine
import ServiceManagement
import Carbon.HIToolbox

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
    @State private var showPicker = false

    var body: some View {
        HStack(spacing: 4) { field }
    }

    @ViewBuilder private var field: some View {
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
        // Alternative to typing: some shortcuts are taken by macOS before Keysy can see them.
        Button { center.end(); showPicker = true } label: { Image(systemName: "chevron.down.circle") }
            .buttonStyle(.borderless)
            .help("Choose the keys from a list instead of typing them")
            .popover(isPresented: $showPicker, arrowEdge: .bottom) {
                KeyPicker(initial: combo) { picked in showPicker = false; onCapture(picked) }
                    onCancel: { showPicker = false }
            }
    }

    private func label(recording: Bool) -> String {
        if recording {
            let m = KeyCombo.modifierSymbols(center.liveModifiers)
            return m.isEmpty ? "Type keys…" : m + "…"
        }
        return combo?.display ?? placeholder
    }
}

// MARK: - Key picker (choose instead of type)

struct KeyPicker: View {
    let onSet: (KeyCombo) -> Void
    let onCancel: () -> Void
    @State private var mods: UInt64
    @State private var keyCode: Int?

    init(initial: KeyCombo?, onSet: @escaping (KeyCombo) -> Void, onCancel: @escaping () -> Void) {
        self.onSet = onSet; self.onCancel = onCancel
        _mods = State(initialValue: initial?.modifiers ?? 0)
        _keyCode = State(initialValue: initial?.keyCode)
    }

    private static let modifierButtons: [(String, String, CGEventFlags)] = [
        ("⌃", "Control", .maskControl), ("⌥", "Option", .maskAlternate), ("⇧", "Shift", .maskShift),
        ("⌘", "Command", .maskCommand), ("🌐", "Fn / Globe", .maskSecondaryFn),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose keys").font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                Text("Modifiers").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(Self.modifierButtons, id: \.1) { sym, name, flag in
                        let on = mods & flag.rawValue != 0
                        Button { mods ^= flag.rawValue } label: {
                            VStack(spacing: 1) {
                                Text(sym).font(.title3)
                                Text(name).font(.caption2)
                            }
                            .frame(width: 64, height: 44)
                            .background(RoundedRectangle(cornerRadius: 6).fill(on ? Color.accentColor : Color.secondary.opacity(0.12)))
                            .foregroundStyle(on ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Key").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $keyCode) {
                    Text("Choose a key…").tag(Int?.none)
                    ForEach(KeyCatalog.groups, id: \.name) { g in
                        Section(g.name) {
                            ForEach(g.codes, id: \.self) { c in Text(KeyCombo.keyName(c)).tag(Int?.some(c)) }
                        }
                    }
                }
                .labelsHidden().frame(width: 220)
            }
            HStack {
                Text(preview).font(.system(.title3, design: .rounded).weight(.medium))
                    .foregroundStyle(keyCode == nil ? .secondary : .primary)
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Set") { if let k = keyCode { onSet(KeyCombo.normalized(keyCode: k, flags: mods)) } }
                    .keyboardShortcut(.defaultAction).disabled(keyCode == nil)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private var preview: String {
        guard let k = keyCode else { return KeyCombo.modifierSymbols(mods) + "…" }
        return KeyCombo.normalized(keyCode: k, flags: mods).display
    }
}

/// Keys offered in the picker, grouped. Uses physical key codes; names follow the current layout.
enum KeyCatalog {
    struct Group { let name: String; let codes: [Int] }
    static let groups: [Group] = [
        Group(name: "Letters", codes: [kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G,
                                       kVK_ANSI_H, kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N,
                                       kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U,
                                       kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X, kVK_ANSI_Y, kVK_ANSI_Z]),
        Group(name: "Numbers", codes: [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                                       kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0]),
        Group(name: "Arrows & Navigation", codes: [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
                                                   kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown]),
        Group(name: "Special", codes: [kVK_Space, kVK_Tab, kVK_Return, kVK_Escape, kVK_Delete, kVK_ForwardDelete,
                                       kVK_ANSI_KeypadEnter, kVK_JIS_Eisu, kVK_JIS_Kana]),
        Group(name: "Symbols", codes: [kVK_ANSI_Minus, kVK_ANSI_Equal, kVK_ANSI_LeftBracket, kVK_ANSI_RightBracket,
                                       kVK_ANSI_Backslash, kVK_ANSI_Semicolon, kVK_ANSI_Quote, kVK_ANSI_Comma,
                                       kVK_ANSI_Period, kVK_ANSI_Slash, kVK_ANSI_Grave, kVK_JIS_Yen, kVK_JIS_Underscore]),
        Group(name: "Function Keys", codes: KeyCombo.fKeys),
        Group(name: "Keypad", codes: [kVK_ANSI_Keypad0, kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3,
                                      kVK_ANSI_Keypad4, kVK_ANSI_Keypad5, kVK_ANSI_Keypad6, kVK_ANSI_Keypad7,
                                      kVK_ANSI_Keypad8, kVK_ANSI_Keypad9, kVK_ANSI_KeypadPlus, kVK_ANSI_KeypadMinus,
                                      kVK_ANSI_KeypadMultiply, kVK_ANSI_KeypadDivide, kVK_ANSI_KeypadEquals,
                                      kVK_ANSI_KeypadDecimal, kVK_ANSI_KeypadClear, kVK_JIS_KeypadComma]),
        Group(name: "Other Keyboards", codes: [kVK_ISO_Section, kVK_Help]),
    ]
}

// MARK: - Rules

// MARK: - Shared pieces

/// Title, one-line summary and where the setting lives — same layout on every tab.
struct TabHeader: View {
    enum Scope { case keysy, macOS }
    let title: String
    let summary: String
    let scope: Scope?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title).font(.title3.weight(.semibold))
                switch scope {
                case .keysy:
                    Label("Handled by Keysy — works while Keysy is running", systemImage: "bolt.fill")
                        .font(.caption).foregroundStyle(Color.accentColor)
                case .macOS:
                    Label("Saved in macOS — works even when Keysy is quit", systemImage: "apple.logo")
                        .font(.caption).foregroundStyle(.secondary)
                case nil:
                    EmptyView()
                }
            }
            Text(summary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AccessibilityBanner: View {
    @State private var trusted = AXIsProcessTrusted()
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if !trusted {
                HStack {
                    Label("Keysy needs Accessibility permission for this tab.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Open System Settings") { Permissions.openAccessibilitySettings() }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
            }
        }
        .onReceive(timer) { _ in trusted = AXIsProcessTrusted() }
    }
}

struct RuleRow: View {
    @Binding var rule: Rule
    let duplicate: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $rule.enabled).labelsHidden().toggleStyle(.checkbox)
            KeyRecorderField(id: "\(rule.id)-from", combo: rule.from, placeholder: "Type keys") {
                rule.from = $0
            }
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            KeyRecorderField(id: "\(rule.id)-to", combo: rule.to, placeholder: "Type keys") {
                rule.to = $0
            }
            if duplicate {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .help("Another row uses the same shortcut; only the first one is used.")
            }
            Spacer(minLength: 0)
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless).help("Delete this row")
        }
        .opacity(rule.enabled ? 1 : 0.5)
    }
}

struct RemapsView: View {
    @ObservedObject var store = RuleStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TabHeader(title: "Custom Shortcuts",
                      summary: "Press a shortcut, and Keysy sends a different shortcut instead (e.g. ⌘9 → ⌃⇧⇥).",
                      scope: .keysy)
            AccessibilityBanner()
            HStack {
                Text("Shortcut").frame(minWidth: 146, alignment: .leading).padding(.leading, 26)
                Text("Sends").padding(.leading, 30)
            }
            .font(.caption).foregroundStyle(.secondary)
            if store.rules.isEmpty {
                Text("Nothing yet. Click Add, then click each field and type the keys.")
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
                Button { store.addEmpty() } label: { Label("Add", systemImage: "plus") }
                Spacer()
            }
        }
        .padding(16)
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

struct WindowCommandRow: View {
    let command: WindowCommand
    @ObservedObject var store = WindowShortcutStore.shared

    var body: some View {
        let combo = store.shortcuts[command]
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                if let d = command.detail { Text(d).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            KeyRecorderField(id: "window-\(command.rawValue)", combo: combo, placeholder: "Not set") {
                store.set($0, for: command)
            }
            Button { RecordingCenter.shared.end(); store.set(nil, for: command) } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless).help("Remove this shortcut")
            .opacity(combo == nil ? 0 : 1).disabled(combo == nil)
        }
    }
}

struct WindowCommandsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                TabHeader(title: "Window Layouts",
                          summary: "Press a shortcut to move the front window. Works in every app. Nothing is assigned until you set it.",
                          scope: .keysy)
                AccessibilityBanner()
            }
            .padding([.horizontal, .top], 16)
            Form {
                ForEach(WindowCommand.sections, id: \.self) { sec in
                    Section(sec) {
                        ForEach(WindowCommand.allCases.filter { $0.section == sec }) { WindowCommandRow(command: $0) }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

struct SystemShortcutsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TabHeader(title: "macOS Features",
                      summary: "Choose the shortcut for a macOS feature. Your keys replace the macOS ones (same as System Settings ▸ Keyboard ▸ Keyboard Shortcuts). ↩︎ puts a row back to the macOS default.",
                      scope: .macOS)
                .padding([.horizontal, .top], 16)
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
        }
    }
}

struct TransferView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TabHeader(title: "Import & Export",
                      summary: "Save all your settings to a file and load them on another Mac.", scope: nil)
                .padding([.horizontal, .top], 16)
            Form {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Export Settings…")
                            Text("Custom Shortcuts, Window Layouts, and the macOS Features you changed.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Export…") { BackupIO.export() }
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Import Settings…")
                            Text("Replaces your current settings with the ones in the file. You'll be asked first.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Import…") { BackupIO.importFromFile() }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

struct GeneralView: View {
    @State private var autoUpdate = Updater.autoCheckEnabled
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    @ObservedObject var rules = RuleStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
        TabHeader(title: "Startup & Updates", summary: "Start Keysy at login and keep it up to date.", scope: nil)
            .padding([.horizontal, .top], 16)
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
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case otherShortcuts, windowLayouts, macOSFeatures, startup, transfer
    var id: String { rawValue }
    var title: String {
        switch self {
        case .otherShortcuts: return "Custom Shortcuts"
        case .windowLayouts: return "Window Layouts"
        case .macOSFeatures: return "macOS Features"
        case .startup: return "Startup & Updates"
        case .transfer: return "Import & Export"
        }
    }
    var symbol: String {
        switch self {
        case .otherShortcuts: return "keyboard"
        case .windowLayouts: return "macwindow"
        case .macOSFeatures: return "apple.logo"
        case .startup: return "gearshape"
        case .transfer: return "arrow.up.arrow.down.circle"
        }
    }
    static let shortcutPages: [SettingsPage] = [.otherShortcuts, .windowLayouts, .macOSFeatures]
}

struct SidebarHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            .selectionDisabled()
            .allowsHitTesting(false)
    }
}

struct SettingsView: View {
    @AppStorage("settingsPage") private var page = SettingsPage.otherShortcuts.rawValue
    @ObservedObject private var rules = RuleStore.shared

    private var selection: Binding<SettingsPage?> {
        Binding(get: { SettingsPage(rawValue: page) ?? .otherShortcuts }, set: { if let p = $0 { page = p.rawValue } })
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                // Plain header rows (not Section headers), so the groups can't be collapsed.
                SidebarHeader(title: "Shortcuts")
                ForEach(SettingsPage.shortcutPages) { p in Label(p.title, systemImage: p.symbol).tag(p) }
                SidebarHeader(title: "Keysy").padding(.top, 10)
                ForEach([SettingsPage.startup, .transfer]) { p in Label(p.title, systemImage: p.symbol).tag(p) }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    Toggle("Pause Keysy", isOn: Binding(get: { !rules.enabled }, set: { rules.enabled = !$0 }))
                        .toggleStyle(.switch).controlSize(.small)
                        .help("Stops Custom Shortcuts and Window Layouts. macOS Features keep working (they live in macOS).")
                        .padding(.horizontal, 12).padding(.bottom, 10).padding(.top, 4)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            Group {
                switch SettingsPage(rawValue: page) ?? .otherShortcuts {
                case .otherShortcuts: RemapsView()
                case .windowLayouts: WindowCommandsView()
                case .macOSFeatures: SystemShortcutsView()
                case .startup: GeneralView()
                case .transfer: TransferView()
                }
            }
            // Fill the window; long lists scroll instead of stretching the layout.
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 820, minHeight: 560)
        .onChange(of: page) { _, _ in RecordingCenter.shared.end() }
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
        let hosting = NSHostingView(rootView: SettingsView())
        hosting.sizingOptions = []   // fixed window size; lists scroll instead of growing the window
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.title = "Keysy Settings"
        win.toolbarStyle = .unified
        win.toolbar = NSToolbar(identifier: "KeysySettings")   // sidebar layout expects a toolbar area
        win.contentView = hosting
        win.contentMinSize = NSSize(width: 820, height: 520)
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
