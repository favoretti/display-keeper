import Foundation

/// What the system tells us about a monitor, before we pick a stable key for it.
public struct RawIdentity: Equatable, Sendable {
    public var vendor: UInt32
    public var model: UInt32
    public var edidSerial: UInt32
    /// Per-unit serial from the EDID descriptor block; unique even when `edidSerial` is not.
    public var alphanumericSerial: String?
    /// Physical connection (framebuffer), e.g. "dispext0".
    public var port: String?
    public var isBuiltin: Bool
    public var uuid: String

    public init(vendor: UInt32, model: UInt32, edidSerial: UInt32, alphanumericSerial: String?,
                port: String?, isBuiltin: Bool, uuid: String) {
        self.vendor = vendor
        self.model = model
        self.edidSerial = edidSerial
        self.alphanumericSerial = alphanumericSerial
        self.port = port
        self.isBuiltin = isBuiltin
        self.uuid = uuid
    }
}

public enum IdentityResolver {
    /// One key per display, stable across sleep/wake. macOS's own display UUIDs are not: identical
    /// monitors often share an EDID serial and get their UUIDs swapped on wake.
    public static func keys(for displays: [RawIdentity]) -> [String] {
        let keys = displays.map { d -> String in
            if d.isBuiltin { return "builtin" }
            let base = String(format: "%04x-%04x", d.vendor, d.model)
            if let s = d.alphanumericSerial?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
                return "\(base)-\(s)"
            }
            let twins = displays.filter { $0.vendor == d.vendor && $0.model == d.model && $0.edidSerial == d.edidSerial }
            if d.edidSerial != 0 && twins.count == 1 { return "\(base)-\(d.edidSerial)" }
            if let port = d.port { return "\(base)@\(port)" }
            return "\(base)#\(d.uuid)"
        }
        var seen: [String: Int] = [:]
        return keys.map { key in
            seen[key, default: 0] += 1
            return seen[key]! == 1 ? key : "\(key)#\(seen[key]!)"
        }
    }

    /// "…/AppleSoCIO/dispext1@90000000/IOMobileFramebufferShim" -> "dispext1"
    public static func portName(fromLocation path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        if let disp = parts.last(where: { $0.hasPrefix("disp") }) {
            return String(disp.split(separator: "@")[0])
        }
        return parts.isEmpty ? nil : path
    }
}
