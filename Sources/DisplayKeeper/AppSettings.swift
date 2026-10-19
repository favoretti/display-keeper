import AppKit
import Combine
import DisplayKeeperCore
import ServiceManagement

/// User preferences, persisted in UserDefaults and applied to the running Keeper as they change.
/// The menu and the Settings window both go through this so they stay in sync.
@MainActor
final class AppSettings: ObservableObject {
    enum Key {
        static let paused = "paused"
        static let restoresWindows = "restoresWindows"
        static let settleDelay = "settleDelay"
        static let unlockDelay = "unlockDelay"
    }

    static let settleRange: ClosedRange<Double> = 1...30
    static let unlockRange: ClosedRange<Double> = 0...10

    private let keeper: Keeper
    private let defaults = UserDefaults.standard

    @Published var isPaused: Bool {
        didSet { keeper.isPaused = isPaused; defaults.set(isPaused, forKey: Key.paused) }
    }
    @Published var restoresWindows: Bool {
        didSet {
            keeper.restoresWindows = restoresWindows
            defaults.set(restoresWindows, forKey: Key.restoresWindows)
            if restoresWindows && !SystemWindows.isTrusted { SystemWindows.requestTrust() }
        }
    }
    @Published var settleDelay: Double {
        didSet { keeper.settleDelay = settleDelay; defaults.set(settleDelay, forKey: Key.settleDelay) }
    }
    @Published var unlockDelay: Double {
        didSet { keeper.unlockDelay = unlockDelay; defaults.set(unlockDelay, forKey: Key.unlockDelay) }
    }

    @Published private(set) var isTrusted = SystemWindows.isTrusted
    @Published private(set) var loginStatus = SMAppService.mainApp.status
    @Published var loginError: String?

    init(keeper: Keeper) {
        self.keeper = keeper
        defaults.register(defaults: [
            Key.paused: false, Key.restoresWindows: true, Key.settleDelay: 4.0, Key.unlockDelay: 1.0,
        ])
        isPaused = defaults.bool(forKey: Key.paused)
        restoresWindows = defaults.bool(forKey: Key.restoresWindows)
        settleDelay = defaults.double(forKey: Key.settleDelay).clamped(to: Self.settleRange)
        unlockDelay = defaults.double(forKey: Key.unlockDelay).clamped(to: Self.unlockRange)
        keeper.isPaused = isPaused
        keeper.restoresWindows = restoresWindows
        keeper.settleDelay = settleDelay
        keeper.unlockDelay = unlockDelay
    }

    var opensAtLogin: Bool { loginStatus == .enabled || loginStatus == .requiresApproval }

    func setOpensAtLogin(_ on: Bool) {
        loginError = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            loginError = error.localizedDescription
        }
        refresh()
    }

    /// Accessibility and login-item state can change in System Settings behind our back.
    func refresh() {
        if isTrusted != SystemWindows.isTrusted { isTrusted = SystemWindows.isTrusted }
        let status = SMAppService.mainApp.status
        if loginStatus != status { loginStatus = status }
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
