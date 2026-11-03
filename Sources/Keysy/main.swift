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

    private func updateIcon() {
        let on = RuleStore.shared.enabled
        statusItem.button?.image = NSImage(systemSymbolName: on ? "keyboard" : "keyboard.badge.ellipsis",
                                           accessibilityDescription: "Keysy")
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
        func header(_ t: String) {
            menu.addItem(.separator())
            let h = NSMenuItem(title: t, action: nil, keyEquivalent: ""); h.isEnabled = false
            h.attributedTitle = NSAttributedString(string: t, attributes: [.font: NSFont.boldSystemFont(ofSize: 12)])
            menu.addItem(h)
        }
        func line(_ t: String) {
            let i = NSMenuItem(title: t, action: nil, keyEquivalent: ""); i.isEnabled = false; menu.addItem(i)
        }
        header("Shortcut → Other Shortcuts")
        let remaps = store.rules.filter { $0.enabled && $0.isComplete }
        if remaps.isEmpty { line("None") }
        for r in remaps.prefix(20) { line("\(r.from!.display)  →  \(r.to!.display)") }
        header("Shortcut → Window Layouts")
        let wins = WindowCommand.allCases.compactMap { c in WindowShortcutStore.shared.shortcuts[c].map { (c, $0) } }
        if wins.isEmpty { line("None") }
        for (c, k) in wins { line("\(k.display)  →  \(c.title)") }
        menu.addItem(.separator())
        add(menu, "Settings…", #selector(openSettings), key: ",")
        add(menu, "Check for Updates…", #selector(checkUpdates))
        menu.addItem(.separator())
        add(menu, "Keysy on GitHub", #selector(openURL(_:)), url: Links.repository)
        add(menu, "Support the Developer ♥", #selector(openURL(_:)), url: Links.sponsor)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Keysy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func add(_ menu: NSMenu, _ title: String, _ sel: Selector, key: String = "", url: URL? = nil) {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self; i.representedObject = url
        menu.addItem(i)
    }

    @objc private func toggleEnabled() { RuleStore.shared.enabled.toggle() }
    @objc private func openAX() { Permissions.openAccessibilitySettings() }
    @objc func openSettings() {
        if settings == nil { settings = SettingsWindowController() }
        settings?.present()
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
