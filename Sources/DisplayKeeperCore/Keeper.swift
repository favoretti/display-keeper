import AppKit
import CoreGraphics
import Foundation
import os

public enum RestoreOutcome: Equatable, Sendable {
    case alreadyCorrect
    case noProfile
    case restored(count: Int)
    case windowsRestored(count: Int)
    case paused
    case failed(String)
}

/// Watches for display reconfiguration, wake and unlock, and restores the saved layout.
@MainActor
public final class Keeper {
    public let store: ProfileStore
    public var isPaused = false
    public var restoresWindows = true
    public var onRestore: ((RestoreOutcome) -> Void)?
    /// Unified log, so a menu-bar launch leaves a trace: `log show --predicate 'subsystem == "io.github.favoretti.DisplayKeeper"'`.
    public var log: (String) -> Void = { message in
        Keeper.logger.notice("\(message, privacy: .public)")
        if isatty(STDOUT_FILENO) != 0 { print("\(Date()) \(message)") }
    }
    static let logger = Logger(subsystem: "io.github.favoretti.DisplayKeeper", category: "restore")

    /// Wake fires a burst of callbacks while monitors come up; act once it has been quiet.
    public var settleDelay: TimeInterval = 4
    public private(set) var lastOutcome: (RestoreOutcome, Date)?
    /// By unlock the monitors are usually up already.
    public var unlockDelay: TimeInterval = 1

    private var pending: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    /// After we apply a layout, the resulting callbacks must not trigger another pass.
    private var ignoreUntil = Date.distantPast

    public init(store: ProfileStore = ProfileStore()) {
        self.store = store
    }

    public func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback(reconfigured, context)
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.log("unlock")
                self?.schedule(after: self?.unlockDelay ?? 1)
            }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.log("wake")
                self?.schedule(after: self?.settleDelay ?? 4)
            }
        })
        schedule(after: settleDelay)
    }

    fileprivate func displaysChanged() {
        guard Date() >= ignoreUntil else { return }
        log("display change; checking in \(settleDelay)s")
        schedule(after: settleDelay)
    }

    public func schedule(after delay: TimeInterval, force: Bool = false) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { _ = self?.restore(force: force) }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    @discardableResult
    public func restore(force: Bool = false, windowsOnly: Bool = false) -> RestoreOutcome {
        let outcome = computeAndApply(force: force, windowsOnly: windowsOnly)
        log("check: \(outcome)")
        switch outcome {
        case .restored, .windowsRestored, .failed: lastOutcome = (outcome, Date())
        default: break
        }
        onRestore?(outcome)
        return outcome
    }

    private func computeAndApply(force: Bool, windowsOnly: Bool) -> RestoreOutcome {
        if isPaused && !force { return .paused }
        let online = SystemDisplays.online()
        guard let profile = store.profile(for: online.map(\.placement.key)) else { return .noProfile }
        let diff = windowsOnly ? [] : profile.differences(from: online.map(\.placement)) ?? []
        if !diff.isEmpty {
            do {
                ignoreUntil = Date().addingTimeInterval(2)
                try Arranger.apply(profile, to: online)
            } catch {
                return .failed(String(describing: error))
            }
            // Windows wait for the next pass: macOS keeps relocating them for a while after the
            // displays move, and would undo a move made now.
            if restoresWindows { schedule(after: settleDelay, force: force) }
            return .restored(count: diff.count)
        }
        // Windows are checked on every pass: macOS can shuffle them even when the displays came back right.
        let windowsMoved = (restoresWindows || windowsOnly) && !profile.windows.isEmpty
            ? SystemWindows.restore(profile.windows, displays: online.map(\.placement)) : 0
        return windowsMoved > 0 ? .windowsRestored(count: windowsMoved) : .alreadyCorrect
    }

    /// Save the current arrangement as the layout to keep for this set of monitors.
    @discardableResult
    public func saveCurrent() throws -> Profile {
        let displays = SystemDisplays.online().map(\.placement)
        let windows = restoresWindows ? SystemWindows.snapshot(displays: displays) : []
        let profile = Profile(placements: displays, windows: windows)
        try store.save(profile)
        return profile
    }
}

private func reconfigured(_ id: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags, _ ctx: UnsafeMutableRawPointer?) {
    guard !flags.contains(.beginConfigurationFlag), let ctx else { return }
    let keeper = Unmanaged<Keeper>.fromOpaque(ctx).takeUnretainedValue()
    MainActor.assumeIsolated { keeper.displaysChanged() }
}
