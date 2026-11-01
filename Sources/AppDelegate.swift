import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let booster = Booster()
    private var statusItem: NSStatusItem!
    private var iconTimer: Timer?
    private var panel: NSPanel!
    private let panelView = PanelView(frame: NSRect(x: 0, y: 0, width: PanelView.width, height: PanelView.height))
    private let menu = NSMenu()
    private let toggleItem = NSMenuItem(title: "XDR 부스트", action: #selector(toggle), keyEquivalent: "b")
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let sliderLabel = NSTextField(labelWithString: "")
    private let slider = NSSlider(value: 1.6, minValue: 1.0, maxValue: Booster.maxFactor, target: nil, action: nil)
    private let hotItem = NSMenuItem(title: "발열 시 자동 일시정지", action: #selector(toggleHot), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "로그인 시 실행", action: #selector(toggleLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.toolTip = "XDR Boost"

        for item in [toggleItem, hotItem, loginItem] { item.target = self }
        statusLine.isEnabled = false

        menu.delegate = self
        menu.addItem(toggleItem)
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(sliderItem())
        menu.addItem(.separator())
        menu.addItem(hotItem)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Left click: the panel drops down under the icon. Right click: the plain menu.
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        panelView.booster = booster
        panelView.loginEnabled = { SMAppService.mainApp.status == .enabled }
        panelView.onToggleLogin = { [weak self] in self?.toggleLogin() }
        panelView.onQuit = { NSApp.terminate(nil) }
        panelView.setFrameSize(NSSize(width: PanelView.width, height: panelView.contentHeight))
        panel = NSPanel(contentRect: panelView.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)  // the glass stays dark over any wallpaper, for the light text
        panel.contentView = glassBackground(for: panelView)
        // A click anywhere else closes the panel.
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePanel()
        }

        booster.onChange = { [weak self] in self?.update() }
        update()
    }

    func applicationWillTerminate(_ notification: Notification) {
        booster.shutdown()
    }

    func menuWillOpen(_ menu: NSMenu) { update() }

    private func sliderItem() -> NSMenuItem {
        slider.target = self
        slider.action = #selector(sliderMoved)
        slider.isContinuous = true
        slider.doubleValue = booster.factor
        let stack = NSStackView(views: [sliderLabel, slider])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 20, bottom: 4, right: 16)
        stack.frame = NSRect(x: 0, y: 0, width: 240, height: 52)
        slider.widthAnchor.constraint(equalToConstant: 204).isActive = true
        let item = NSMenuItem()
        item.view = stack
        return item
    }

    /// The panel's backdrop: Liquid Glass on macOS 26 and later, a blurred HUD material before that.
    private func glassBackground(for content: NSView) -> NSView {
        let radius = 26.0
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: content.frame)
            glass.cornerRadius = radius
            glass.tintColor = NSColor(red: 0.05, green: 0.05, blue: 0.10, alpha: 0.55)
            glass.contentView = content
            return glass
        }
        let blur = NSVisualEffectView(frame: content.frame)
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = radius
        blur.layer?.masksToBounds = true
        content.autoresizingMask = [.width, .height]
        blur.addSubview(content)
        return blur
    }

    @objc private func statusClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            hidePanel()
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        if panel.isVisible { hidePanel() } else { showPanel() }
    }

    private func showPanel() {
        guard let button = statusItem.button, let window = button.window else { return }
        let icon = window.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = window.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let w = PanelView.width, h = panelView.contentHeight
        let x = min(max(icon.midX - w / 2, visible.minX + 8), visible.maxX - w - 8)
        panel.setFrame(NSRect(x: x, y: icon.minY - 6 - h, width: w, height: h), display: true)
        panel.orderFrontRegardless()
        panelView.setAnimating(true)
    }

    private func hidePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        panelView.setAnimating(false)
    }

    private func update() {
        panelView.needsDisplay = true
        animateIcon(booster.state == .on)
        toggleItem.state = booster.enabled ? .on : .off
        hotItem.state = booster.pauseWhenHot ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        sliderLabel.stringValue = String(format: "밝기 배율  %.2f×", booster.factor)

        switch booster.state {
        case .off: statusLine.title = "꺼짐"
        case .noDisplay: statusLine.title = "내장 XDR 디스플레이를 찾을 수 없음 (덮개 닫힘?)"
        case .pausedThermal: statusLine.title = "발열로 일시정지됨"
        case .on:
            let capped = booster.appliedFactor + 0.01 < booster.factor
            statusLine.title = String(format: "적용 %.2f× · 여유 %.2f×%@", booster.appliedFactor, booster.headroom,
                                      capped ? " (시스템 한도)" : "")
        }
    }

    /// Off: the template ghost. On: the liquid ghost, rendered live; it fades in over the first second.
    private func animateIcon(_ on: Bool) {
        guard on else {
            iconTimer?.invalidate()
            iconTimer = nil
            statusItem.button?.image = GhostArt.off
            return
        }
        guard iconTimer == nil else { return }
        let start = Date()
        let draw = { [weak self] in
            let t = Date().timeIntervalSince(start)
            self?.statusItem.button?.image = GhostArt.lit(t: t, fade: min(1, t / 0.8))
        }
        draw()
        // Each new image makes AppKit re-snapshot the status item for every display, so keep this slow.
        iconTimer = Timer.scheduledTimer(withTimeInterval: 1 / 8, repeats: true) { _ in draw() }
        RunLoop.main.add(iconTimer!, forMode: .common)  // keep animating while the menu is open
    }

    @objc private func toggle() { booster.enabled.toggle() }

    @objc private func toggleHot() { booster.pauseWhenHot.toggle() }

    @objc private func sliderMoved() {
        booster.factor = (slider.doubleValue * 20).rounded() / 20  // 0.05 steps
        update()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert(error: error)
            alert.informativeText = "~/Applications 또는 /Applications에 설치한 앱에서만 동작합니다 (./build.sh install)."
            alert.runModal()
        }
        update()
    }
}
