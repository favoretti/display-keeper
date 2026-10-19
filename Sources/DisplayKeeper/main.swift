import AppKit
import DisplayKeeperCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let keeper = Keeper()
    var statusItem: NSStatusItem!
    var lastOutcome = "Watching"

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "Display Keeper")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        keeper.isPaused = UserDefaults.standard.bool(forKey: "paused")
        keeper.restoresWindows = UserDefaults.standard.object(forKey: "restoresWindows") as? Bool ?? true
        keeper.onRestore = { [weak self] outcome in self?.record(outcome) }
        keeper.start()
    }

    func record(_ outcome: RestoreOutcome) {
        let time = Date().formatted(date: .omitted, time: .shortened)
        switch outcome {
        case .restored(let n): lastOutcome = "Restored \(n) display\(n == 1 ? "" : "s") at \(time)"
        case .windowsRestored(let n): lastOutcome = "Moved \(n) window\(n == 1 ? "" : "s") back at \(time)"
        case .failed(let why): lastOutcome = "Failed at \(time): \(why)"
        default: break
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let online = SystemDisplays.online()
        let profile = keeper.store.profile(for: online.map(\.placement.key))

        let header: String
        if keeper.isPaused { header = "Paused" }
        else if profile == nil { header = "No layout saved for these displays" }
        else if profile?.differences(from: online.map(\.placement))?.isEmpty == true { header = "Layout matches" }
        else { header = "Layout differs from saved" }
        menu.addItem(disabled(header))
        menu.addItem(disabled(lastOutcome))
        menu.addItem(.separator())

        for d in online {
            menu.addItem(disabled("\(d.placement.name) — \(d.placement.mode.description)"))
        }
        menu.addItem(.separator())

        if let profile { menu.addItem(disabled("Saved: \(profile.windows.count) windows, \(profile.savedAt.formatted(date: .abbreviated, time: .shortened))")) }
        menu.addItem(item(profile == nil ? "Save Current Layout" : "Save Current Layout (Replace)", #selector(save), "s"))
        let restore = item("Restore Saved Layout", #selector(restore), "r")
        restore.isEnabled = profile != nil
        menu.addItem(restore)
        if profile != nil { menu.addItem(item("Forget Layout for These Displays", #selector(forget))) }
        menu.addItem(.separator())

        let windows = item(SystemWindows.isTrusted || !keeper.restoresWindows ? "Restore Windows" : "Restore Windows (needs Accessibility access…)", #selector(toggleWindows))
        windows.state = keeper.restoresWindows && SystemWindows.isTrusted ? .on : .off
        menu.addItem(windows)
        let pause = item("Pause Automatic Restore", #selector(togglePause))
        pause.state = keeper.isPaused ? .on : .off
        menu.addItem(pause)
        let login = item("Open at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(item("Quit Display Keeper", #selector(NSApplication.terminate(_:)), "q"))
    }

    private func item(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = action == #selector(NSApplication.terminate(_:)) ? NSApp : self
        return i
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    @objc func save() {
        do {
            let p = try keeper.saveCurrent()
            lastOutcome = "Saved \(p.placements.count) displays, \(p.windows.count) windows"
        } catch { alert("Could not save layout", error) }
    }

    @objc func restore() {
        if case .failed(let why) = keeper.restore(force: true) { alert("Could not restore layout", why) }
    }

    @objc func forget() {
        let id = Profile.id(for: SystemDisplays.online().map(\.placement.key))
        try? keeper.store.remove(id: id)
    }

    @objc func toggleWindows() {
        if keeper.restoresWindows && !SystemWindows.isTrusted {
            SystemWindows.requestTrust()
            return
        }
        keeper.restoresWindows.toggle()
        UserDefaults.standard.set(keeper.restoresWindows, forKey: "restoresWindows")
        if keeper.restoresWindows && !SystemWindows.isTrusted { SystemWindows.requestTrust() }
    }

    @objc func togglePause() {
        keeper.isPaused.toggle()
        UserDefaults.standard.set(keeper.isPaused, forKey: "paused")
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { alert("Could not change login item", error) }
    }

    private func alert(_ title: String, _ detail: Any) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = String(describing: detail)
        a.runModal()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
