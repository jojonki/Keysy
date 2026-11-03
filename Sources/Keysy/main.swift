import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var settings: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu(); menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        Remapper.shared.start()
        NotificationCenter.default.addObserver(forName: RuleStore.changed, object: nil, queue: .main) { [weak self] _ in
            self?.updateIcon()
        }
        if RuleStore.shared.rules.isEmpty || !AXIsProcessTrusted() { openSettings() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { Updater.shared.checkIfDue() }
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["KEYSY_SNAPSHOT"] { snapshotSettings(to: path) }
        if ProcessInfo.processInfo.environment["KEYSY_BACKUP_TEST"] != nil {
            let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601
            let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
            let before = KeysyBackup.current()
            let data = try! e.encode(before)
            print(String(data: data, encoding: .utf8)!)
            try! d.decode(KeysyBackup.self, from: data).apply()
            let after = KeysyBackup.current()
            print("round-trip macOS equal:", before.macOSFeatures == after.macOSFeatures,
                  "rules equal:", before.customShortcuts == after.customShortcuts,
                  "windows equal:", before.windowLayouts == after.windowLayouts)
            exit(0)
        }
        #endif
    }

    #if DEBUG
    /// Debug aid: renders the settings window to a PNG.
    private func snapshotSettings(to path: String) {
        openSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard let view = self.settings?.window?.contentView?.superview,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }
    #endif

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings(); return true
    }

    /// The app icon, shrunk to menu bar size (dimmed via appearsDisabled while paused).
    private static let menuBarIcon: NSImage = {
        let img = (NSApp.applicationIconImage.copy() as? NSImage) ?? NSImage()
        img.size = NSSize(width: 18, height: 18)
        img.accessibilityDescription = "Keysy"
        return img
    }()

    private func updateIcon() {
        let on = RuleStore.shared.enabled
        statusItem.button?.image = Self.menuBarIcon
        statusItem.button?.appearsDisabled = !on
    }

    // Rebuild each time so it reflects the current rules.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let store = RuleStore.shared
        let pause = NSMenuItem(title: "Pause Keysy", action: #selector(toggleEnabled), keyEquivalent: "")
        pause.target = self; pause.state = store.enabled ? .off : .on
        menu.addItem(pause)
        if !AXIsProcessTrusted() {
            let warn = NSMenuItem(title: "⚠︎ Grant Accessibility Permission…", action: #selector(openAX), keyEquivalent: "")
            warn.target = self; menu.addItem(warn)
        }
        // Counts only: lists would grow without bound as shortcuts are added.
        menu.addItem(.separator())
        let shortcutsHeader = NSMenuItem(title: "Shortcuts", action: nil, keyEquivalent: ""); shortcutsHeader.isEnabled = false
        menu.addItem(shortcutsHeader)
        let custom = store.rules.filter { $0.enabled && $0.isComplete }.count
        let windows = WindowShortcutStore.shared.shortcuts.count
        let mac = SystemShortcutStore.shared.exportSettings().count
        add(menu, "Custom Shortcuts: \(custom) in use", #selector(openPage(_:)), page: .otherShortcuts)
        add(menu, "Window Layouts: \(windows) in use", #selector(openPage(_:)), page: .windowLayouts)
        add(menu, "macOS Features: \(mac) changed from default", #selector(openPage(_:)), page: .macOSFeatures)
        menu.addItem(.separator())
        add(menu, "Settings…", #selector(openSettings))
        add(menu, "Check for Updates…", #selector(checkUpdates))
        menu.addItem(.separator())
        add(menu, "Keysy on GitHub", #selector(openURL(_:)), url: Links.repository)
        add(menu, "Support the Developer ♥", #selector(openURL(_:)), url: Links.sponsor)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Keysy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
    }

    private func add(_ menu: NSMenu, _ title: String, _ sel: Selector, key: String = "", url: URL? = nil,
                     page: SettingsPage? = nil) {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self; i.representedObject = url ?? page?.rawValue
        if page != nil { i.indentationLevel = 1 }
        menu.addItem(i)
    }

    @objc private func toggleEnabled() { RuleStore.shared.enabled.toggle() }
    @objc private func openAX() { Permissions.openAccessibilitySettings() }
    @objc func openSettings() {
        if settings == nil { settings = SettingsWindowController() }
        settings?.present()
    }
    @objc private func openPage(_ sender: NSMenuItem) {
        if let p = sender.representedObject as? String { UserDefaults.standard.set(p, forKey: "settingsPage") }
        openSettings()
    }
    @objc private func checkUpdates() { Updater.shared.check(userInitiated: true) }
    @objc private func openURL(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.open(url) }
    }
}

enum Links {
    static let repository = URL(string: "https://github.com/jojonki/Keysy")!
    static let sponsor = URL(string: "https://github.com/sponsors/jojonki")!
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
