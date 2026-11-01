import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let booster = Booster()
    private var statusItem: NSStatusItem!
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
        statusItem.menu = menu

        booster.onChange = { [weak self] in self?.update() }
        update()

        // The gamma table outlives a killed process otherwise; put the display back on Ctrl-C / kill.
        for sig in [SIGINT, SIGTERM] {
            signal(sig) { _ in CGDisplayRestoreColorSyncSettings(); exit(0) }
        }
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

    private func update() {
        let on = booster.state == .on
        statusItem.button?.image = NSImage(systemSymbolName: on ? "sun.max.fill" : "sun.max",
                                           accessibilityDescription: "XDR Boost")
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
