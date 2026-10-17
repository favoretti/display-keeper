import AppKit
import CoreGraphics
import Foundation
import IOKit

/// A display that is currently online.
public struct OnlineDisplay: Sendable {
    public let id: CGDirectDisplayID
    public let raw: RawIdentity
    public let placement: Placement
}

public enum SystemDisplays {
    public static func online() -> [OnlineDisplay] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(32, &ids, &count) == .success else { return [] }
        // Mirrored secondaries share the primary's position; arrange only what is actually placed.
        let active = ids.prefix(Int(count)).filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
        let raws = active.map(rawIdentity)
        let keys = IdentityResolver.keys(for: raws)
        let names = screenNames()
        return zip(active, zip(raws, keys)).compactMap { id, pair in
            guard let mode = currentMode(of: id) else { return nil }
            let bounds = CGDisplayBounds(id)
            let placement = Placement(key: pair.1, name: names[id] ?? pair.1,
                                      x: Int(bounds.origin.x), y: Int(bounds.origin.y), mode: mode)
            return OnlineDisplay(id: id, raw: pair.0, placement: placement)
        }
    }

    static func rawIdentity(_ id: CGDirectDisplayID) -> RawIdentity {
        let location = PrivateDisplayInfo.ioLocation(of: id)
        let uuid = CGDisplayCreateUUIDFromDisplayID(id).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String } ?? "\(id)"
        return RawIdentity(
            vendor: CGDisplayVendorNumber(id),
            model: CGDisplayModelNumber(id),
            edidSerial: CGDisplaySerialNumber(id),
            alphanumericSerial: location.flatMap(PrivateDisplayInfo.alphanumericSerial(atLocation:)),
            port: location.flatMap(IdentityResolver.portName(fromLocation:)),
            isBuiltin: CGDisplayIsBuiltin(id) != 0,
            uuid: uuid
        )
    }

    static func screenNames() -> [CGDirectDisplayID: String] {
        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            if let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                names[n.uint32Value] = screen.localizedName
            }
        }
        return names
    }

    static func currentMode(of id: CGDirectDisplayID) -> DisplayMode? {
        CGDisplayCopyDisplayMode(id).map(DisplayMode.init)
    }

    static func availableModes(of id: CGDirectDisplayID) -> [CGDisplayMode] {
        // Without this option the HiDPI ("scaled") modes are left out.
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        return (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode]) ?? []
    }
}

extension DisplayMode {
    init(_ m: CGDisplayMode) {
        self.init(width: m.width, height: m.height, pixelWidth: m.pixelWidth, pixelHeight: m.pixelHeight,
                  refreshRate: m.refreshRate)
    }

    /// Exact match if available, otherwise the same size at the closest refresh rate.
    public static func best(for target: DisplayMode, among candidates: [DisplayMode]) -> Int? {
        if let exact = candidates.firstIndex(where: { $0.matches(target) }) { return exact }
        return candidates.indices
            .filter { candidates[$0].sameSize(target) }
            .min { abs(candidates[$0].refreshRate - target.refreshRate) < abs(candidates[$1].refreshRate - target.refreshRate) }
    }
}

/// Undocumented lookups. Public APIs only expose the EDID serial, which identical monitors can share;
/// the per-unit serial is reachable via the display's IOKit framebuffer node.
enum PrivateDisplayInfo {
    private typealias InfoFn = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?

    private static let createInfo: InfoFn? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY),
              let sym = dlsym(handle, "CoreDisplay_DisplayCreateInfoDictionary") else { return nil }
        return unsafeBitCast(sym, to: InfoFn.self)
    }()

    static func ioLocation(of id: CGDirectDisplayID) -> String? {
        guard let info = createInfo?(id)?.takeRetainedValue() as? [String: Any] else { return nil }
        return info["IODisplayLocation"] as? String
    }

    static func alphanumericSerial(atLocation path: String) -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, path)
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        let attrs = IORegistryEntryCreateCFProperty(entry, "DisplayAttributes" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any]
        let product = attrs?["ProductAttributes"] as? [String: Any]
        return product?["AlphanumericSerialNumber"] as? String
    }
}
