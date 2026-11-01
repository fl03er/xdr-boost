import AppKit

/// Keeps the built-in XDR display in EDR mode and pushes ordinary (SDR) content into the EDR headroom,
/// so it is shown brighter than the normal 500-nit ceiling: a full-screen EDR window multiplies everything under it
/// (BrightIntosh's "alternate backend").
final class Booster {
    enum State: Equatable { case off, on, pausedThermal, noDisplay }

    /// The factor the user asked for, in linear light (2.0 = twice the nits); the applied one is capped by the live headroom.
    var factor: Double {
        didSet { defaults.set(factor, forKey: "factor"); apply(force: true) }
    }
    var enabled: Bool {
        didSet { defaults.set(enabled, forKey: "enabled"); refresh() }
    }
    var pauseWhenHot: Bool {
        didSet { defaults.set(pauseWhenHot, forKey: "pauseWhenHot"); refresh() }
    }
    var onChange: (() -> Void)?

    private(set) var state: State = .off
    private(set) var appliedFactor: Double = 1.0
    private let defaults = UserDefaults.standard
    private var overlay: EDROverlay?
    private var display: CGDirectDisplayID?
    private var timer: Timer?
    private let debug = ProcessInfo.processInfo.environment["XDR_DEBUG"] != nil

    static let maxFactor = 3.2

    init() {
        defaults.register(defaults: ["factor": 2.0, "enabled": false, "pauseWhenHot": true])
        factor = defaults.double(forKey: "factor")
        enabled = defaults.bool(forKey: "enabled")
        pauseWhenHot = defaults.bool(forKey: "pauseWhenHot")

        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensChanged()
        }
        nc.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.restart()
        }
        refresh()
    }

    /// Headroom the system currently grants the built-in display (1.0 = no EDR).
    var headroom: Double {
        guard let screen = builtinScreen() else { return 1.0 }
        return Double(screen.maximumExtendedDynamicRangeColorComponentValue)
    }

    var potentialHeadroom: Double {
        guard let screen = builtinScreen() else { return 1.0 }
        return Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue)
    }

    func shutdown() { stop() }

    // MARK: - State

    private func refresh() {
        let hot = ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
        let wanted: State
        if !enabled { wanted = .off }
        else if builtinScreen() == nil { wanted = .noDisplay }
        else if pauseWhenHot && hot { wanted = .pausedThermal }
        else { wanted = .on }

        if wanted == .on && state != .on { start() }
        if wanted != .on && state == .on { stop() }
        state = wanted
        onChange?()
    }

    private func restart() {
        guard state == .on else { refresh(); return }
        stop()
        state = .off
        refresh()
    }

    /// Screen parameters change for many reasons, EDR itself switching on among them; tearing down and rebuilding
    /// every time makes the screen flash. Only rebuild when the built-in display itself came or went.
    private func screensChanged() {
        let id = builtinScreen().flatMap(displayID(of:))
        if state == .on, id != nil, id == display {
            if let screen = builtinScreen() { overlay?.move(to: screen) }
            apply(force: false)
        } else {
            restart()
        }
    }

    private func start() {
        guard let screen = builtinScreen(), let id = displayID(of: screen) else { return }
        display = id
        overlay = EDROverlay(screen: screen)
        overlay?.show()
        appliedFactor = 1.0
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.apply(force: false) }
        apply(force: true)
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        overlay?.close()
        overlay = nil
        display = nil
        appliedFactor = 1.0
    }

    // MARK: - Boost

    /// Applies min(factor, headroom). Runs on a timer: headroom follows ambient light and the brightness setting.
    private func apply(force: Bool) {
        guard state == .on || force, display != nil else { return }
        let headroom = self.headroom
        let target = max(1.0, min(factor, headroom))
        let changed = abs(target - appliedFactor) > 0.01
        overlay?.value = Self.encodedScale(target)
        appliedFactor = target
        if changed { onChange?() }
        if debug {
            FileHandle.standardError.write(String(format: "[xdr] headroom %.2f / potential %.2f  factor %.2f  applied %.2f (scale %.3f)\n",
                                                  headroom, potentialHeadroom, factor, appliedFactor,
                                                  Self.encodedScale(appliedFactor)).data(using: .utf8)!)
        }
    }

    /// The overlay multiplies encoded values, not linear light. An exponent of 2.5
    /// matches BrightIntosh's tuned ceiling for these panels (headroom 3.2 → 1.59). Scaling by the linear factor
    /// instead overshoots the headroom, and then each channel clips on its own and hues shift.
    private static func encodedScale(_ linear: Double) -> Double { pow(linear, 1 / 2.5) }

    // MARK: - Display

    private func builtinScreen() -> NSScreen? {
        NSScreen.screens.first { screen in displayID(of: screen).map { CGDisplayIsBuiltin($0) != 0 } ?? false }
    }

    private func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
