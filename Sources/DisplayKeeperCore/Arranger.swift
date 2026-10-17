import CoreGraphics
import Foundation

public enum ArrangeError: Error, CustomStringConvertible {
    case begin(CGError), complete(CGError), noMode(String, DisplayMode)

    public var description: String {
        switch self {
        case .begin(let e): return "could not begin display configuration (\(e.rawValue))"
        case .complete(let e): return "macOS rejected the display configuration (\(e.rawValue))"
        case .noMode(let name, let mode): return "\(name) no longer offers \(mode.description)"
        }
    }
}

public enum Arranger {
    /// Apply `profile` to the given online displays in one transaction.
    public static func apply(_ profile: Profile, to online: [OnlineDisplay]) throws {
        let byKey = Dictionary(uniqueKeysWithValues: online.map { ($0.placement.key, $0) })
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success, let config else { throw ArrangeError.begin(begin) }
        do {
            for want in profile.placements {
                guard let display = byKey[want.key] else { continue }
                if !display.placement.mode.matches(want.mode) {
                    let modes = SystemDisplays.availableModes(of: display.id)
                    guard let i = DisplayMode.best(for: want.mode, among: modes.map(DisplayMode.init)) else {
                        throw ArrangeError.noMode(display.placement.name, want.mode)
                    }
                    CGConfigureDisplayWithDisplayMode(config, display.id, modes[i], nil)
                }
                CGConfigureDisplayOrigin(config, display.id, Int32(want.x), Int32(want.y))
            }
        } catch {
            CGCancelDisplayConfiguration(config)
            throw error
        }
        let done = CGCompleteDisplayConfiguration(config, .permanently)
        guard done == .success else { throw ArrangeError.complete(done) }
    }
}
