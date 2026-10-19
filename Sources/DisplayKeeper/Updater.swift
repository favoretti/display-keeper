import AppKit
import Combine
import Sparkle

/// Sparkle, only when this build carries a feed URL and signing key in its Info.plist.
/// Under `swift run` there is no bundle Info.plist, so nothing is started.
@MainActor
final class UpdaterModel: NSObject, ObservableObject, SPUStandardUserDriverDelegate {
    private(set) var controller: SPUStandardUpdaterController?

    @Published private(set) var automaticallyChecks = false
    @Published private(set) var automaticallyDownloads = false
    @Published private(set) var allowsAutomaticUpdates = false
    @Published private(set) var canCheck = false
    @Published private(set) var lastCheck: Date?
    private var subscriptions: Set<AnyCancellable> = []

    static var isConfigured: Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        func has(_ key: String) -> Bool {
            (info[key] as? String)?.trimmingCharacters(in: .whitespaces).isEmpty == false
        }
        return Bundle.main.bundleIdentifier != nil && has("SUFeedURL") && has("SUPublicEDKey")
    }

    var isConfigured: Bool { controller != nil }

    override init() {
        super.init()
        guard Self.isConfigured else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        let updater = controller.updater
        updater.publisher(for: \.automaticallyChecksForUpdates).sink { [weak self] in self?.automaticallyChecks = $0 }.store(in: &subscriptions)
        updater.publisher(for: \.automaticallyDownloadsUpdates).sink { [weak self] in self?.automaticallyDownloads = $0 }.store(in: &subscriptions)
        updater.publisher(for: \.allowsAutomaticUpdates).sink { [weak self] in self?.allowsAutomaticUpdates = $0 }.store(in: &subscriptions)
        updater.publisher(for: \.canCheckForUpdates).sink { [weak self] in self?.canCheck = $0 }.store(in: &subscriptions)
        updater.publisher(for: \.lastUpdateCheckDate).sink { [weak self] in self?.lastCheck = $0 }.store(in: &subscriptions)
    }

    func setAutomaticallyChecks(_ on: Bool) { controller?.updater.automaticallyChecksForUpdates = on }
    func setAutomaticallyDownloads(_ on: Bool) { controller?.updater.automaticallyDownloadsUpdates = on }

    func checkForUpdates() {
        NSApp.activateApp()
        controller?.checkForUpdates(nil)
    }

    // A menu-bar app has no Dock icon to badge, so let Sparkle show scheduled updates itself, in front.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard handleShowingUpdate else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { NSApp.activateApp() } }
    }
}

extension NSApplication {
    func activateApp() {
        if #available(macOS 14, *) { activate() } else { activate(ignoringOtherApps: true) }
    }
}

enum AppInfo {
    static var version: String? { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String }
    static var build: String? { Bundle.main.infoDictionary?["CFBundleVersion"] as? String }

    static var versionDescription: String {
        guard let version, !version.hasPrefix("__") else { return "Development build" }
        if let build, !build.hasPrefix("__"), build != version { return "Version \(version) (\(build))" }
        return "Version \(version)"
    }

    /// The bundle icon, or the menu-bar symbol when running outside an app bundle.
    @MainActor static var icon: NSImage {
        if Bundle.main.bundleIdentifier != nil, let icon = NSApp.applicationIconImage { return icon }
        let config = NSImage.SymbolConfiguration(pointSize: 72, weight: .light)
            .applying(.init(paletteColors: [.controlAccentColor]))
        return NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) ?? NSImage(named: NSImage.applicationIconName)!
    }

    static let repository = URL(string: "https://github.com/favoretti/display-keeper")!
    static let issues = URL(string: "https://github.com/favoretti/display-keeper/issues")!
    static let releases = URL(string: "https://github.com/favoretti/display-keeper/releases")!
}
