import Foundation

public struct DisplayMode: Codable, Equatable, Sendable {
    /// Size in points, i.e. the "looks like" resolution.
    public var width: Int
    public var height: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var refreshRate: Double

    public init(width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, refreshRate: Double) {
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
    }

    public func matches(_ other: DisplayMode) -> Bool {
        sameSize(other) && abs(refreshRate - other.refreshRate) < 0.5
    }

    func sameSize(_ other: DisplayMode) -> Bool {
        width == other.width && height == other.height
            && pixelWidth == other.pixelWidth && pixelHeight == other.pixelHeight
    }

    public var description: String {
        let hidpi = pixelWidth > width ? " HiDPI" : ""
        return "\(width)x\(height)\(hidpi) @\(Int(refreshRate.rounded()))Hz"
    }
}

public struct Placement: Codable, Equatable, Sendable {
    /// Stable identity of the physical monitor; see `IdentityResolver`.
    public var key: String
    public var name: String
    public var x: Int
    public var y: Int
    public var mode: DisplayMode

    public init(key: String, name: String, x: Int, y: Int, mode: DisplayMode) {
        self.key = key
        self.name = name
        self.x = x
        self.y = y
        self.mode = mode
    }
}

/// The saved arrangement for one particular set of monitors.
public struct Profile: Codable, Equatable, Sendable {
    public var placements: [Placement]
    public var savedAt: Date

    public init(placements: [Placement], savedAt: Date = Date()) {
        self.placements = placements
        self.savedAt = savedAt
    }

    public var id: String { Profile.id(for: placements.map(\.key)) }

    public static func id(for keys: [String]) -> String {
        keys.sorted().joined(separator: "+")
    }

    /// Placements that differ from `current`, or nil when `current` is a different set of monitors.
    public func differences(from current: [Placement]) -> [Placement]? {
        let byKey = Dictionary(uniqueKeysWithValues: current.map { ($0.key, $0) })
        guard byKey.count == placements.count, placements.allSatisfy({ byKey[$0.key] != nil }) else { return nil }
        return placements.filter { want in
            let have = byKey[want.key]!
            return have.x != want.x || have.y != want.y || !have.mode.matches(want.mode)
        }
    }
}
