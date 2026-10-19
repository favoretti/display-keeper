import AppKit
import CoreGraphics
import Foundation

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
    public var log: (String) -> Void = { print("\(Date()) \($0)") }

    /// Wake fires a burst of callbacks while monitors come up; act once it has been quiet.
    public var settleDelay: TimeInterval = 4
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
            MainActor.assumeIsolated { self?.schedule(after: self?.unlockDelay ?? 1) }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule(after: self?.settleDelay ?? 4) }
        })
        schedule(after: settleDelay)
    }

    fileprivate func displaysChanged() {
        guard Date() >= ignoreUntil else { return }
        schedule(after: settleDelay)
    }

    public func schedule(after delay: TimeInterval) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { _ = self?.restore() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    @discardableResult
    public func restore(force: Bool = false) -> RestoreOutcome {
        let outcome = computeAndApply(force: force)
        switch outcome {
        case .alreadyCorrect, .noProfile, .paused: break
        default: log(String(describing: outcome))
        }
        onRestore?(outcome)
        return outcome
    }

    private func computeAndApply(force: Bool) -> RestoreOutcome {
        if isPaused && !force { return .paused }
        let online = SystemDisplays.online()
        guard let profile = store.profile(for: online.map(\.placement.key)) else { return .noProfile }
        let diff = profile.differences(from: online.map(\.placement)) ?? []
        var displaysMoved = 0
        if !diff.isEmpty {
            do {
                ignoreUntil = Date().addingTimeInterval(2)
                try Arranger.apply(profile, to: online)
                displaysMoved = diff.count
            } catch {
                return .failed(String(describing: error))
            }
        }
        // Windows are checked on every pass: macOS can shuffle them even when the displays came back right.
        let windowsMoved = restoresWindows && !profile.windows.isEmpty
            ? SystemWindows.restore(profile.windows, displays: SystemDisplays.online().map(\.placement)) : 0
        if displaysMoved > 0 { return .restored(count: displaysMoved) }
        if windowsMoved > 0 { return .windowsRestored(count: windowsMoved) }
        return .alreadyCorrect
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
