import CoreGraphics
import Foundation
import IOKit

/// How a display's brightness is driven.
public enum BrightnessKind: Sendable {
    /// Built-in and Apple displays, through DisplayServices.
    case apple
    /// External monitors over DDC/CI.
    case ddc
    /// No hardware control: gamma dimming only.
    case software
}

/// Maps the one slider value (0…1) the user sees onto hardware brightness and a software dimming factor.
public enum BrightnessMix {
    /// With combined dimming, the slider below this point dims in software once hardware is at zero.
    public static let switchPoint = 0.5
    /// Without "allow zero", software dimming stops here so the screen never goes black.
    public static let softwareFloor = 0.15

    public static func split(_ value: Double, kind: BrightnessKind, combined: Bool, allowZero: Bool) -> (hardware: Double?, software: Double) {
        let v = min(max(value, 0), 1)
        let floor = allowZero ? 0 : softwareFloor
        func soft(_ x: Double) -> Double { floor + (1 - floor) * x }
        switch kind {
        case .apple: return (v, 1)
        case .software: return (nil, soft(v))
        case .ddc where !combined: return (v, 1)
        case .ddc: return v >= switchPoint ? ((v - switchPoint) / (1 - switchPoint), 1) : (0, soft(v / switchPoint))
        }
    }

    /// Slider value for a hardware reading. At hardware zero the software part can't be read back, so keep `previous`'s.
    public static func value(hardware: Double, kind: BrightnessKind, combined: Bool, previous: Double) -> Double {
        guard kind == .ddc, combined else { return hardware }
        return hardware > 0 ? switchPoint + hardware * (1 - switchPoint) : min(previous, switchPoint)
    }
}

/// DDC/CI through the Apple silicon display coprocessor (private IOAVService calls).
/// Intel Macs have no DCPAVServiceProxy, so `all()` finds nothing there and those displays fall back to software.
public final class DDCChannel: @unchecked Sendable {
    private typealias CreateFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias IOFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
    private static let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
    private static let create = dlsym(iokit, "IOAVServiceCreateWithService").map { unsafeBitCast($0, to: CreateFn.self) }
    private static let writeI2C = dlsym(iokit, "IOAVServiceWriteI2C").map { unsafeBitCast($0, to: IOFn.self) }
    private static let readI2C = dlsym(iokit, "IOAVServiceReadI2C").map { unsafeBitCast($0, to: IOFn.self) }

    private let service: CFTypeRef
    private let queue = DispatchQueue(label: "io.github.favoretti.DisplayKeeper.ddc")
    private let lock = NSLock()
    private var pending: UInt16?
    private var writing = false
    /// Only touched on `queue`.
    private var lastWritten: UInt16?

    private init(service: CFTypeRef) { self.service = service }

    /// DDC channels of external displays, keyed by framebuffer port ("dispext0").
    public static func all() -> [String: DDCChannel] {
        guard let create, writeI2C != nil, readI2C != nil else { return [:] }
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iter) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iter) }
        var result: [String: DDCChannel] = [:]
        while case let s = IOIteratorNext(iter), s != 0 {
            defer { IOObjectRelease(s) }
            let location = IORegistryEntryCreateCFProperty(s, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
            var parent: io_registry_entry_t = 0
            guard location == "External", IORegistryEntryGetParentEntry(s, kIOServicePlane, &parent) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(parent) }
            var name = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(parent, &name)
            // The parent is named "dispext0:dcpav-service-epic:0"; its prefix is the framebuffer port.
            guard let port = String(cString: name).split(separator: ":").first,
                  let av = create(kCFAllocatorDefault, s)?.takeRetainedValue() else { continue }
            result[String(port)] = DDCChannel(service: av)
        }
        return result
    }

    /// Current and maximum brightness (VCP 0x10), or nil if the monitor doesn't answer.
    public func readBrightness() -> (current: Int, max: Int)? {
        queue.sync {
            for _ in 0..<3 {
                guard send([0x01, 0x10]) else { usleep(50_000); continue }
                usleep(50_000)
                var r = [UInt8](repeating: 0, count: 11)
                let ok = r.withUnsafeMutableBytes { Self.readI2C!(service, 0x37, 0x51, $0.baseAddress!, 11) } == kIOReturnSuccess
                // Reply: src, len, 0x02, result, vcp, type, max hi/lo, current hi/lo, checksum (seeded with 0x50).
                guard ok, r[2] == 0x02, r[3] == 0, r[4] == 0x10, r[..<10].reduce(0x50, ^) == r[10] else { usleep(50_000); continue }
                let current = UInt16(r[8]) << 8 | UInt16(r[9])
                lastWritten = current
                return (Int(current), Int(UInt16(r[6]) << 8 | UInt16(r[7])))
            }
            return nil
        }
    }

    /// Sets brightness without blocking. While a write is in flight only the latest value is kept.
    public func setBrightness(_ value: Int) {
        lock.lock()
        pending = UInt16(clamping: value)
        let start = !writing
        writing = true
        lock.unlock()
        guard start else { return }
        queue.async { [self] in
            while true {
                lock.lock()
                guard let v = pending else { writing = false; lock.unlock(); return }
                pending = nil
                lock.unlock()
                guard v != lastWritten else { continue }
                if send([0x03, 0x10, UInt8(v >> 8), UInt8(v & 0xFF)]) { lastWritten = v }
                // Monitors drop commands that arrive closer together than this.
                usleep(50_000)
            }
        }
    }

    private func send(_ payload: [UInt8]) -> Bool {
        var packet = [0x80 | UInt8(payload.count)] + payload
        packet.append(packet.reduce(0x6E ^ 0x51, ^))
        return packet.withUnsafeMutableBytes { Self.writeI2C!(service, 0x37, 0x51, $0.baseAddress!, UInt32($0.count)) } == kIOReturnSuccess
    }
}

/// Built-in and Apple displays, through the private DisplayServices framework Control Center uses.
public enum AppleBrightness {
    private typealias CanFn = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private static let framework = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let canFn = dlsym(framework, "DisplayServicesCanChangeBrightness").map { unsafeBitCast($0, to: CanFn.self) }
    private static let getFn = dlsym(framework, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetFn.self) }
    private static let setFn = dlsym(framework, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetFn.self) }

    public static func canChange(_ id: CGDirectDisplayID) -> Bool { canFn?(id) ?? false }

    public static func get(_ id: CGDirectDisplayID) -> Double? {
        var b: Float = 0
        guard let getFn, getFn(id, &b) == 0 else { return nil }
        return Double(b)
    }

    public static func set(_ id: CGDirectDisplayID, _ value: Double) { _ = setFn?(id, Float(value)) }
}

/// Software dimming by scaling each display's gamma table.
@MainActor
public enum Gamma {
    private static var originals: [CGDirectDisplayID: [[CGGammaValue]]] = [:]

    public static func set(_ id: CGDirectDisplayID, factor: Double) {
        if originals[id] == nil {
            guard factor < 1 else { return }
            var r = [CGGammaValue](repeating: 0, count: 256), g = r, b = r
            var n: UInt32 = 0
            guard CGGetDisplayTransferByTable(id, 256, &r, &g, &b, &n) == .success, n > 0 else { return }
            originals[id] = [r, g, b].map { Array($0.prefix(Int(n))) }
        }
        let f = CGGammaValue(min(max(factor, 0), 1))
        let t = originals[id]!.map { $0.map { $0 * f } }
        CGSetDisplayTransferByTable(id, UInt32(t[0].count), t[0], t[1], t[2])
    }

    /// Gives every display its ColorSync gamma back and forgets the captured tables.
    public static func reset() {
        CGDisplayRestoreColorSyncSettings()
        originals.removeAll()
    }
}
