import AppKit
import DisplayKeeperCore
import SwiftUI

/// Brightness for every online display: DDC for external monitors, DisplayServices for built-in and Apple
/// displays, and gamma dimming for monitors without DDC or below hardware zero.
@MainActor
final class BrightnessController: ObservableObject {
    enum Startup: String, CaseIterable, Identifiable {
        case assume, apply, read
        var id: String { rawValue }
        var title: String {
            switch self {
            case .assume: "Assume last saved settings are valid (recommended)"
            case .apply: "Apply last saved settings to the displays"
            case .read: "Read settings from the displays"
            }
        }
    }

    private enum Key {
        static let smooth = "brightness.smooth"
        static let combined = "brightness.combined"
        static let sync = "brightness.sync"
        static let allowZero = "brightness.allowZero"
        static let startup = "brightness.startup"
        static let values = "brightness.values"
    }

    final class Display {
        let id: CGDirectDisplayID
        let key: String
        let name: String
        let kind: BrightnessKind
        let ddc: DDCChannel?
        var max = 100
        /// What the slider shows and what is saved.
        var value = 1.0
        /// What is applied right now; trails `value` while a smooth transition runs.
        var shown = 1.0

        init(id: CGDirectDisplayID, key: String, name: String, kind: BrightnessKind, ddc: DDCChannel?) {
            self.id = id; self.key = key; self.name = name; self.kind = kind; self.ddc = ddc
        }
    }

    private let defaults = UserDefaults.standard

    @Published var smooth: Bool { didSet { defaults.set(smooth, forKey: Key.smooth) } }
    @Published var combined: Bool { didSet { defaults.set(combined, forKey: Key.combined); applyAll() } }
    @Published var sync: Bool { didSet { defaults.set(sync, forKey: Key.sync); updateSyncTimer() } }
    @Published var allowZero: Bool { didSet { defaults.set(allowZero, forKey: Key.allowZero); applyAll() } }
    @Published var startup: Startup { didSet { defaults.set(startup.rawValue, forKey: Key.startup) } }
    @Published private(set) var displays: [Display] = []

    /// Shift held at launch: forget saved values and don't read or write anything until the user does.
    private let safeMode = NSEvent.modifierFlags.contains(.shift)
    private var animation: Timer?
    private var syncTimer: Timer?
    private var lastApple: [CGDirectDisplayID: Double] = [:]
    private var pending: DispatchWorkItem?
    private var woke = false
    private var observer: NSObjectProtocol?

    init() {
        defaults.register(defaults: [Key.smooth: true, Key.combined: true, Key.sync: false, Key.allowZero: false,
                                     Key.startup: Startup.assume.rawValue])
        smooth = defaults.bool(forKey: Key.smooth)
        combined = defaults.bool(forKey: Key.combined)
        sync = defaults.bool(forKey: Key.sync)
        allowZero = defaults.bool(forKey: Key.allowZero)
        startup = defaults.string(forKey: Key.startup).flatMap(Startup.init(rawValue:)) ?? .assume
    }

    func start() {
        if safeMode { defaults.removeObject(forKey: Key.values) }
        CGDisplayRegisterReconfigurationCallback(brightnessReconfigured, Unmanaged.passUnretained(self).toOpaque())
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.woke = true
                self?.scheduleReload()
            }
        }
        reload(startup: !safeMode)
        updateSyncTimer()
    }

    /// Puts the gamma tables back, so a quit leaves no software dimming behind.
    func stop() { Gamma.reset() }

    func display(_ id: CGDirectDisplayID) -> Display? { displays.first { $0.id == id } }

    func set(_ value: Double, for d: Display) {
        d.value = min(max(value, 0), 1)
        if d.kind != .apple {
            var stored = defaults.dictionary(forKey: Key.values) as? [String: Double] ?? [:]
            stored[d.key] = d.value
            defaults.set(stored, forKey: Key.values)
        }
        if smooth { animate() } else { apply(d, d.value) }
    }

    fileprivate func scheduleReload() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.reload(startup: self.woke && !self.safeMode)
                self.woke = false
            }
        }
        pending = work
        // Same wait as layout restore: DDC writes to a monitor that is still coming up are lost.
        DispatchQueue.main.asyncAfter(deadline: .now() + defaults.double(forKey: AppSettings.Key.settleDelay), execute: work)
    }

    /// Rebuilds the display list. On launch and wake, `startup` applies the "Upon startup or wake" choice.
    private func reload(startup isStartup: Bool) {
        animation?.invalidate(); animation = nil
        let channels = DDCChannel.all()
        let stored = defaults.dictionary(forKey: Key.values) as? [String: Double] ?? [:]
        // A display change can reset gamma behind our back; start from ColorSync and reapply.
        Gamma.reset()
        displays = SystemDisplays.online().map { o in
            let ddc = o.raw.port.flatMap { channels[$0] }
            let kind: BrightnessKind = AppleBrightness.canChange(o.id) ? .apple : ddc != nil ? .ddc : .software
            let d = Display(id: o.id, key: o.placement.key, name: o.placement.name, kind: kind, ddc: ddc)
            let saved = stored[d.key]
            switch kind {
            case .apple:
                d.value = AppleBrightness.get(o.id) ?? 1
                lastApple[o.id] = d.value
            case .software:
                d.value = saved ?? 1
            case .ddc:
                d.value = saved ?? 1
                // shortcut: without a read the DDC maximum is assumed to be 100; store it if a monitor differs.
                if !safeMode, saved == nil || (isStartup && startup == .read), let r = ddc?.readBrightness(), r.max > 0 {
                    d.max = r.max
                    d.value = BrightnessMix.value(hardware: Double(r.current) / Double(r.max), kind: .ddc, combined: combined, previous: saved ?? 1)
                }
            }
            apply(d, d.value, hardware: isStartup && startup == .apply && kind == .ddc)
            return d
        }
        if sync && !safeMode { matchApple() }
    }

    /// Brings every other display to the first Apple display's brightness.
    private func matchApple() {
        guard let source = displays.first(where: { $0.kind == .apple }) else { return }
        for d in displays where d !== source { set(source.value, for: d) }
    }

    private func applyAll() { displays.forEach { apply($0, $0.value) } }

    private func apply(_ d: Display, _ value: Double, hardware: Bool = true) {
        let split = BrightnessMix.split(value, kind: d.kind, combined: combined, allowZero: allowZero)
        if hardware, let h = split.hardware {
            switch d.kind {
            case .apple: AppleBrightness.set(d.id, h); lastApple[d.id] = h
            case .ddc: d.ddc?.setBrightness(Int((h * Double(d.max)).rounded()))
            case .software: break
            }
        }
        Gamma.set(d.id, factor: split.software)
        d.shown = value
    }

    private func animate() {
        guard animation == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.step() } }
        // Common modes, so it keeps running while the menu is tracking the slider.
        RunLoop.main.add(t, forMode: .common)
        animation = t
    }

    private func step() {
        var moving = false
        for d in displays where d.shown != d.value {
            let next = abs(d.value - d.shown) < 0.01 ? d.value : d.shown + (d.value - d.shown) * 0.25
            apply(d, next)
            moving = moving || next != d.value
        }
        if !moving { animation?.invalidate(); animation = nil }
    }

    private func updateSyncTimer() {
        syncTimer?.invalidate(); syncTimer = nil
        guard sync else { return }
        for d in displays where d.kind == .apple {
            lastApple[d.id] = AppleBrightness.get(d.id)
            d.value = lastApple[d.id] ?? d.value
        }
        matchApple()
        // shortcut: polls DisplayServices twice a second; switch to its change notification if this shows up in Energy.
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.pollApple() } }
        RunLoop.main.add(t, forMode: .common)
        syncTimer = t
    }

    /// Copies a brightness change we didn't make (light sensor, keys, Control Center) to the other displays.
    private func pollApple() {
        for d in displays where d.kind == .apple {
            guard let now = AppleBrightness.get(d.id) else { continue }
            let before = lastApple[d.id]
            lastApple[d.id] = now
            guard let before, abs(now - before) > 0.005 else { continue }
            d.value = now
            d.shown = now
            for other in displays where other !== d { set(now, for: other) }
            return
        }
    }
}

private func brightnessReconfigured(_ id: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags, _ ctx: UnsafeMutableRawPointer?) {
    guard !flags.contains(.beginConfigurationFlag), let ctx else { return }
    let controller = Unmanaged<BrightnessController>.fromOpaque(ctx).takeUnretainedValue()
    MainActor.assumeIsolated { controller.scheduleReload() }
}

/// Status-menu row with a brightness slider. NSMenu keeps custom views live while it is open.
final class BrightnessSliderView: NSView {
    private let display: BrightnessController.Display
    private weak var controller: BrightnessController?

    init(display: BrightnessController.Display, controller: BrightnessController) {
        self.display = display
        self.controller = controller
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 26))
        let icon = NSImageView(frame: NSRect(x: 20, y: 5, width: 16, height: 16))
        icon.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        let slider = NSSlider(value: display.value, minValue: 0, maxValue: 1, target: self, action: #selector(changed))
        slider.frame = NSRect(x: 42, y: 3, width: 204, height: 20)
        slider.autoresizingMask = .width
        slider.isContinuous = true
        slider.controlSize = .small
        slider.setAccessibilityLabel("Brightness of \(display.name)")
        addSubview(icon)
        addSubview(slider)
        autoresizingMask = .width
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @MainActor @objc private func changed(_ slider: NSSlider) { controller?.set(slider.doubleValue, for: display) }
}

struct BrightnessSettingsView: View {
    @ObservedObject var brightness: BrightnessController

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $brightness.smooth) {
                    Text("Enable smooth brightness transitions")
                    Text("Turn off for more direct, immediate control.")
                }
                Toggle(isOn: $brightness.combined) {
                    Text("Combine hardware and software dimming")
                    Text("Dim in software after the display reaches zero hardware brightness, for extended range. Works for DDC controlled displays only.")
                }
                Toggle(isOn: $brightness.sync) {
                    Text("Sync brightness changes from built-in and Apple displays")
                    Text("Changes made by the ambient light sensor, brightness keys, Touch Bar, Control Center or System Settings are copied to all displays.")
                }
                Toggle(isOn: $brightness.allowZero) {
                    Text("Allow zero brightness via software or combined dimming")
                    Text("Warning: with this on you can end up with a black display.")
                }
            } header: {
                Text("General Options")
            }

            Section {
                Picker("Upon startup or wake", selection: $brightness.startup) {
                    ForEach(BrightnessController.Startup.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Text("Use brightness from last time, or read it from the displays. With the first choice, values are sent to a display when you first change them. Hold Shift while Display Keeper starts for safe mode: saved brightness is reset and nothing is read or set.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                ForEach(brightness.displays, id: \.id) { d in
                    LabeledContent(d.name, value: Self.method(d.kind))
                }
            } header: {
                Text("Displays")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private static func method(_ kind: BrightnessKind) -> String {
        switch kind {
        case .apple: "macOS"
        case .ddc: "DDC"
        case .software: "Software dimming"
        }
    }
}
