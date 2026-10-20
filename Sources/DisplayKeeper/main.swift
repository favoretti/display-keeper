import AppKit
import DisplayKeeperCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let keeper = Keeper()
    lazy var settings = AppSettings(keeper: keeper)
    lazy var layouts = LayoutsModel(keeper: keeper)
    let updater = UpdaterModel()
    var statusItem: NSStatusItem!
    var lastOutcome = "Watching"

    private lazy var settingsWindow = SettingsWindowController(settings: settings, layouts: layouts, updater: updater)
    private lazy var aboutWindow = WindowPresenter(title: "About Display Keeper", autosaveName: "AboutWindow", content: AboutView())
    private lazy var helpWindow = WindowPresenter(title: "Display Keeper Help", autosaveName: "HelpWindow", resizable: true, content: HelpView())

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchOptions.applyAppearance()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "Display Keeper")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        installMainMenu()
        _ = settings
        keeper.onRestore = { [weak self] outcome in self?.record(outcome) }
        keeper.start()
        LaunchOptions.show.forEach(show)
    }

    func show(_ screen: LaunchOptions.Screen) {
        switch screen {
        case .settings: settingsWindow.show(.general)
        case .layouts: settingsWindow.show(.layouts)
        case .updates: settingsWindow.show(.updates)
        case .about: aboutWindow.show()
        case .help: helpWindow.show()
        }
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
        settings.refresh()
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

        let windows = item(settings.isTrusted || !settings.restoresWindows ? "Restore Windows" : "Restore Windows (needs Accessibility access…)", #selector(toggleWindows))
        windows.state = settings.restoresWindows && settings.isTrusted ? .on : .off
        menu.addItem(windows)
        let pause = item("Pause Automatic Restore", #selector(togglePause))
        pause.state = settings.isPaused ? .on : .off
        menu.addItem(pause)
        let login = item("Open at Login", #selector(toggleLogin))
        login.state = settings.opensAtLogin ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())

        menu.addItem(item("Settings…", #selector(showSettings), ","))
        let updates = item("Check for Updates…", #selector(checkForUpdates))
        updates.isEnabled = updater.isConfigured && updater.canCheck
        menu.addItem(updates)
        menu.addItem(item("Display Keeper Help", #selector(showHelp)))
        menu.addItem(item("About Display Keeper", #selector(showAbout)))
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

    /// Accessory apps still get a main menu while one of their windows is key; it carries the
    /// standard shortcuts (⌘W, ⌘C, ⌘,) for the Settings, Help and About windows.
    private func installMainMenu() {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(item("About Display Keeper", #selector(showAbout)))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Settings…", #selector(showSettings), ","))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Display Keeper", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(item("Quit Display Keeper", #selector(NSApplication.terminate(_:)), "q"))
        main.addItem(withTitle: "Display Keeper", action: nil, keyEquivalent: "").submenu = appMenu

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = window

        let help = NSMenu(title: "Help")
        help.addItem(item("Display Keeper Help", #selector(showHelp)))
        main.addItem(withTitle: "Help", action: nil, keyEquivalent: "").submenu = help
        NSApp.mainMenu = main
    }

    @objc func showSettings() { settingsWindow.show() }
    @objc func showHelp() { helpWindow.show() }
    @objc func showAbout() { aboutWindow.show() }
    @objc func checkForUpdates() { updater.checkForUpdates() }

    @objc func save() {
        do {
            let p = try layouts.saveCurrent()
            lastOutcome = "Saved \(p.placements.count) displays, \(p.windows.count) windows"
            if settings.restoresWindows && !settings.isTrusted {
                alert("Windows were not saved", "DisplayKeeper needs Accessibility access to read window positions. Grant it in System Settings → Privacy & Security → Accessibility, then save again.")
            }
        } catch { alert("Could not save layout", error) }
    }

    @objc func restore() {
        if case .failed(let why) = keeper.restore(force: true) { alert("Could not restore layout", why) }
    }

    @objc func forget() {
        try? layouts.forgetCurrent()
    }

    @objc func toggleWindows() {
        if settings.restoresWindows && !settings.isTrusted {
            SystemWindows.requestTrust()
            return
        }
        settings.restoresWindows.toggle()
    }

    @objc func togglePause() {
        settings.isPaused.toggle()
    }

    @objc func toggleLogin() {
        settings.setOpensAtLogin(!settings.opensAtLogin)
        if let error = settings.loginError { alert("Could not change login item", error) }
    }

    private func alert(_ title: String, _ detail: Any) {
        NSApp.activateApp()
        let a = NSAlert()
        a.messageText = title
        a.informativeText = String(describing: detail)
        a.runModal()
    }
}

/// Hidden launch arguments for development and screenshots:
/// `--show settings|layouts|updates|about|help` (repeatable) and `--appearance light|dark`.
enum LaunchOptions {
    enum Screen: String { case settings, layouts, updates, about, help }

    static var show: [Screen] { values(for: "--show").compactMap(Screen.init(rawValue:)) }

    @MainActor static func applyAppearance() {
        switch values(for: "--appearance").last {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
    }

    private static func values(for flag: String) -> [String] {
        let args = CommandLine.arguments
        return args.indices.dropLast().filter { args[$0] == flag }.map { args[$0 + 1] }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
