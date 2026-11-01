import AppKit

/// Keeps the built-in XDR display in EDR mode and scales its gamma table into the EDR headroom,
/// so ordinary (SDR) content is shown brighter than the normal 500-nit ceiling.
final class Booster {
    enum State: Equatable { case off, on, pausedThermal, noDisplay }

    private struct Table { var r, g, b: [CGGammaValue] }

    /// The factor the user asked for; the applied one is capped by the live headroom.
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
    private var base: Table?
    private var timer: Timer?
    private let debug = ProcessInfo.processInfo.environment["XDR_DEBUG"] != nil

    static let maxFactor = 3.0

    init() {
        defaults.register(defaults: ["factor": 1.6, "enabled": false, "pauseWhenHot": true])
        factor = defaults.double(forKey: "factor")
        enabled = defaults.bool(forKey: "enabled")
        pauseWhenHot = defaults.bool(forKey: "pauseWhenHot")

        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.restart()
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

    private func start() {
        if debug { FileHandle.standardError.write("[xdr] start\n".data(using: .utf8)!) }
        guard let screen = builtinScreen(), let id = displayID(of: screen) else { return }
        // Start from the ColorSync profile's own table, never from one we already boosted.
        CGDisplayRestoreColorSyncSettings()
        display = id
        base = readTable(id)
        overlay = EDROverlay(screen: screen)
        overlay?.show()
        appliedFactor = 1.0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.apply(force: false) }
        apply(force: true)
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        overlay?.close()
        overlay = nil
        base = nil
        display = nil
        appliedFactor = 1.0
        CGDisplayRestoreColorSyncSettings()
    }

    // MARK: - Gamma

    /// Applies min(factor, headroom). Runs every second: headroom follows ambient light and the brightness
    /// setting, and macOS resets the gamma table on its own now and then (display changes, ColorSync updates).
    private func apply(force: Bool) {
        guard state == .on || force, let id = display, let base else { return }
        let headroom = self.headroom
        overlay?.value = headroom
        let target = max(1.0, min(factor, headroom))
        let changed = abs(target - appliedFactor) > 0.01
        if force || changed || tableWasReset(id, base: base) {
            let f = CGGammaValue(target)
            let r = base.r.map { $0 * f }, g = base.g.map { $0 * f }, b = base.b.map { $0 * f }
            CGSetDisplayTransferByTable(id, UInt32(r.count), r, g, b)
            appliedFactor = target
            if changed { onChange?() }
        }
        if debug {
            FileHandle.standardError.write(String(format: "[xdr] headroom %.2f / potential %.2f  factor %.2f  applied %.2f\n",
                                                  headroom, potentialHeadroom, factor, appliedFactor).data(using: .utf8)!)
        }
    }

    private func tableWasReset(_ id: CGDirectDisplayID, base: Table) -> Bool {
        guard let now = readTable(id), let last = now.r.last, let baseLast = base.r.last else { return false }
        return abs(Double(last) - Double(baseLast) * appliedFactor) > 0.01
    }

    private func readTable(_ id: CGDirectDisplayID) -> Table? {
        let capacity = Int(CGDisplayGammaTableCapacity(id))
        guard capacity > 0 else { return nil }
        var r = [CGGammaValue](repeating: 0, count: capacity)
        var g = r, b = r
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(id, UInt32(capacity), &r, &g, &b, &count) == .success, count > 0 else { return nil }
        let n = Int(count)
        return Table(r: Array(r[..<n]), g: Array(g[..<n]), b: Array(b[..<n]))
    }

    // MARK: - Display

    private func builtinScreen() -> NSScreen? {
        NSScreen.screens.first { screen in displayID(of: screen).map { CGDisplayIsBuiltin($0) != 0 } ?? false }
    }

    private func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
