import AppKit
import ApplicationServices
import Foundation

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Reads and moves standard app windows through the Accessibility API.
public enum SystemWindows {
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Privacy & Security → Accessibility.
    public static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    struct Handle {
        let element: AXUIElement
        let live: LiveWindow
    }

    static func handles() -> [Handle] {
        guard isTrusted else { return [] }
        var out: [Handle] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier, app.processIdentifier != getpid() else { continue }
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            // A hung app would otherwise stall every pass.
            AXUIElementSetMessagingTimeout(appElement, 0.5)
            let windows: [AXUIElement] = attribute(appElement, kAXWindowsAttribute) ?? []
            var index = 0
            for w in windows {
                guard (attribute(w, kAXSubroleAttribute) as String?) == kAXStandardWindowSubrole,
                      (attribute(w, kAXMinimizedAttribute) as Bool?) != true,
                      (attribute(w, "AXFullScreen") as Bool?) != true,
                      let frame = frame(of: w) else { continue }
                var id: CGWindowID = 0
                let windowID = _AXUIElementGetWindow(w, &id) == .success ? id : nil
                let live = LiveWindow(bundleID: bundleID, title: attribute(w, kAXTitleAttribute) ?? "", index: index,
                                      windowID: windowID, pid: app.processIdentifier,
                                      x: Int(frame.minX), y: Int(frame.minY),
                                      width: Int(frame.width), height: Int(frame.height))
                out.append(Handle(element: w, live: live))
                index += 1
            }
        }
        return out
    }

    public static func live() -> [LiveWindow] { handles().map(\.live) }

    /// Test hook: move the first window of an app.
    public static func debugMove(bundleID: String, to r: CGRect) -> Bool {
        guard let h = handles().first(where: { $0.live.bundleID == bundleID }) else { return false }
        setFrame(h.element, r)
        return true
    }

    /// Snapshot open windows relative to the display each one is mostly on.
    public static func snapshot(displays: [Placement]) -> [SavedWindow] {
        let names = Dictionary(NSWorkspace.shared.runningApplications.compactMap { app in
            app.bundleIdentifier.map { ($0, app.localizedName ?? $0) }
        }, uniquingKeysWith: { a, _ in a })
        return live().compactMap { w in
            guard let d = display(for: w, among: displays) else { return nil }
            return SavedWindow(bundleID: w.bundleID, appName: names[w.bundleID] ?? w.bundleID, title: w.title,
                               index: w.index, displayKey: d.key, x: w.x - d.x, y: w.y - d.y,
                               width: w.width, height: w.height, windowID: w.windowID, pid: w.pid)
        }
    }

    /// Move matched windows that are not where they were saved. Returns how many moved.
    public static func restore(_ saved: [SavedWindow], displays: [Placement]) -> Int {
        let current = handles()
        let origins = Dictionary(uniqueKeysWithValues: displays.map { ($0.key, (x: $0.x, y: $0.y)) })
        var moved = 0
        for (s, l) in WindowMatcher.match(saved: saved, live: current.map(\.live)) {
            guard let t = WindowMatcher.target(for: s, origins: origins), !WindowMatcher.isClose(l, to: t),
                  let h = current.first(where: { $0.live == l }) else { continue }
            setFrame(h.element, CGRect(x: t.x, y: t.y, width: t.width, height: t.height))
            moved += 1
        }
        return moved
    }

    static func display(for w: LiveWindow, among displays: [Placement]) -> Placement? {
        let rect = CGRect(x: w.x, y: w.y, width: w.width, height: w.height)
        return displays.max { area(rect, $0) < area(rect, $1) }.flatMap { area(rect, $0) > 0 ? $0 : nil }
    }

    private static func area(_ r: CGRect, _ p: Placement) -> CGFloat {
        let i = r.intersection(CGRect(x: p.x, y: p.y, width: p.mode.width, height: p.mode.height))
        return i.isNull ? 0 : i.width * i.height
    }

    private static func attribute<T>(_ e: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func frame(of e: AXUIElement) -> CGRect? {
        var pos: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXPositionAttribute as CFString, &pos) == .success,
              AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &size) == .success else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(pos as! AXValue, .cgPoint, &p)
        AXValueGetValue(size as! AXValue, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }

    private static func setFrame(_ e: AXUIElement, _ r: CGRect) {
        var p = r.origin, s = r.size
        // Size, move, size again: a window can't grow past the edge of the screen it is still on,
        // so the first resize may be clipped until it has moved.
        if let size = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(e, kAXSizeAttribute as CFString, size) }
        if let pos = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(e, kAXPositionAttribute as CFString, pos) }
        if let size = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(e, kAXSizeAttribute as CFString, size) }
    }
}
