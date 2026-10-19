import Foundation

public struct SavedWindow: Codable, Equatable, Sendable {
    public var bundleID: String
    public var appName: String
    public var title: String
    /// Position of this window among the app's windows when saved; last-resort matching.
    public var index: Int
    /// Key of the display the window was on, and its frame relative to that display's origin,
    /// so a profile stays valid if the whole arrangement is shifted.
    public var displayKey: String
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int
    /// CGWindowID at save time. Only meaningful while the app keeps running.
    public var windowID: UInt32?
    public var pid: Int32?

    public init(bundleID: String, appName: String, title: String, index: Int, displayKey: String,
                x: Int, y: Int, width: Int, height: Int, windowID: UInt32? = nil, pid: Int32? = nil) {
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.index = index
        self.displayKey = displayKey
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.windowID = windowID
        self.pid = pid
    }
}

/// A window that is open right now, in global coordinates.
public struct LiveWindow: Equatable, Sendable {
    public var bundleID: String
    public var title: String
    public var index: Int
    public var windowID: UInt32?
    public var pid: Int32
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(bundleID: String, title: String, index: Int, windowID: UInt32?, pid: Int32,
                x: Int, y: Int, width: Int, height: Int) {
        self.bundleID = bundleID
        self.title = title
        self.index = index
        self.windowID = windowID
        self.pid = pid
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum WindowMatcher {
    /// Pair saved windows with live ones. Each live window is used at most once.
    /// Order: same window (app still running), then app + title, then app + index.
    public static func match(saved: [SavedWindow], live: [LiveWindow]) -> [(saved: SavedWindow, live: LiveWindow)] {
        var used = Set<Int>()
        var result: [Int: Int] = [:]

        func pass(_ isMatch: (SavedWindow, LiveWindow) -> Bool) {
            for (si, s) in saved.enumerated() where result[si] == nil {
                if let li = live.indices.first(where: { !used.contains($0) && isMatch(s, live[$0]) }) {
                    result[si] = li
                    used.insert(li)
                }
            }
        }

        pass { s, l in s.windowID != nil && s.windowID == l.windowID && s.pid == l.pid }
        pass { s, l in s.bundleID == l.bundleID && !s.title.isEmpty && s.title == l.title }
        pass { s, l in s.bundleID == l.bundleID && s.index == l.index }

        return result.keys.sorted().map { (saved[$0], live[result[$0]!]) }
    }

    /// Target global frame for a saved window, given current display origins by key.
    public static func target(for w: SavedWindow, origins: [String: (x: Int, y: Int)]) -> (x: Int, y: Int, width: Int, height: Int)? {
        guard let o = origins[w.displayKey] else { return nil }
        return (o.x + w.x, o.y + w.y, w.width, w.height)
    }

    /// Small differences come from apps snapping sizes to their own increments (terminals).
    public static func isClose(_ l: LiveWindow, to t: (x: Int, y: Int, width: Int, height: Int), tolerance: Int = 4) -> Bool {
        abs(l.x - t.x) <= tolerance && abs(l.y - t.y) <= tolerance
            && abs(l.width - t.width) <= tolerance && abs(l.height - t.height) <= tolerance
    }
}
