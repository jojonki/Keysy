import AppKit

/// Lightweight self-updater backed by GitHub Releases.
/// Publish a release whose tag is e.g. `v0.2.0` and attach `Keysy.zip` (containing Keysy.app).
final class Updater {
    static let shared = Updater()

    /// GitHub "owner/repo" hosting the releases.
    static let repo = "jojonki/Keysy"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
    static var autoCheckEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoUpdate") }
    }

    private struct Release: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        let tag_name: String
        let body: String?
        let assets: [Asset]
    }

    private var busy = false

    /// Called on launch; checks at most once a day.
    func checkIfDue() {
        guard Updater.autoCheckEnabled else { return }
        let last = UserDefaults.standard.double(forKey: "lastUpdateCheck")
        guard Date().timeIntervalSince1970 - last > 86_400 else { return }
        check(userInitiated: false)
    }

    func check(userInitiated: Bool) {
        guard !busy else { return }
        busy = true
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Updater.repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                self.busy = false
                guard err == nil, let data, (resp as? HTTPURLResponse)?.statusCode == 200,
                      let rel = try? JSONDecoder().decode(Release.self, from: data) else {
                    if userInitiated { self.alert("Couldn't check for updates", "No release information is available from GitHub (\(Updater.repo)).") }
                    return
                }
                let latest = rel.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                guard Updater.isNewer(latest, than: Updater.currentVersion) else {
                    if userInitiated { self.alert("You're up to date", "Keysy \(Updater.currentVersion) is the latest version.") }
                    return
                }
                guard let asset = rel.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }) else {
                    if userInitiated { self.alert("Update \(latest) found", "The release has no .zip asset to install.") }
                    return
                }
                self.offer(version: latest, notes: rel.body ?? "", asset: asset.browser_download_url)
            }
        }.resume()
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private func offer(version: String, notes: String, asset: URL) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Keysy \(version) is available"
        a.informativeText = "You have \(Updater.currentVersion). Install the update and relaunch?\n\n" + String(notes.prefix(600))
        a.addButton(withTitle: "Install & Relaunch")
        a.addButton(withTitle: "Later")
        if a.runModal() == .alertFirstButtonReturn { install(from: asset) }
    }

    private func install(from url: URL) {
        URLSession.shared.downloadTask(with: url) { tmp, _, err in
            guard let tmp, err == nil else {
                DispatchQueue.main.async { self.alert("Download failed", err?.localizedDescription ?? "Unknown error") }
                return
            }
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("keysy-update-\(UUID().uuidString)")
            let zip = work.appendingPathComponent("update.zip")
            do {
                try fm.createDirectory(at: work, withIntermediateDirectories: true)
                try fm.moveItem(at: tmp, to: zip)
                let unzip = Process()
                unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                unzip.arguments = ["-xk", zip.path, work.path]
                try unzip.run(); unzip.waitUntilExit()
                guard unzip.terminationStatus == 0,
                      let newApp = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
                        .first(where: { $0.pathExtension == "app" }) else { throw CocoaError(.fileReadCorruptFile) }
                try self.swapAndRelaunch(newApp: newApp, work: work)
            } catch {
                DispatchQueue.main.async { self.alert("Update failed", error.localizedDescription) }
            }
        }.resume()
    }

    private func swapAndRelaunch(newApp: URL, work: URL) throws {
        let dest = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: dest.deletingLastPathComponent().path) else {
            throw NSError(domain: "Keysy", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Keysy's folder isn't writable. Move Keysy.app to /Applications or ~/Applications."])
        }
        let script = """
        while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done
        rm -rf "\(dest.path)"
        mv "\(newApp.path)" "\(dest.path)"
        xattr -dr com.apple.quarantine "\(dest.path)" 2>/dev/null
        open "\(dest.path)"
        rm -rf "\(work.path)"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        try p.run()
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = title; a.informativeText = text; a.runModal()
    }
}
