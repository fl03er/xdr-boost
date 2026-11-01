import AppKit

/// The dropdown under the menu bar icon. On top, the ghost (GhostArt) watching a MacBook (MacBookArt): dark while off;
/// while the boost is on the screen's light falls on the ghost and it turns to liquid. Below it, the controls.
final class PanelView: NSView {
    var booster: Booster!
    var loginEnabled: () -> Bool = { false }
    var onToggleLogin: () -> Void = {}
    var onQuit: () -> Void = {}

    static let width = 320.0
    static let height = 576.0
    var contentHeight: Double { Self.height }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Layout (top-down, as the view is flipped).
    private let pad = 18.0
    private var hero: CGRect { CGRect(x: pad, y: 62, width: bounds.width - 2 * pad, height: 172) }

    // Hit areas, set while drawing.
    private var switchRect = CGRect.zero, sliderTrack = CGRect.zero, hotRect = CGRect.zero
    private var loginRect = CGRect.zero, quitRect = CGRect.zero
    private var draggingSlider = false

    private var timer: Timer?
    private let started = Date()
    private var t: Double { Date().timeIntervalSince(started) }
    private var shownLevel = 0.0
    private var lastDraw = Date()

    // Palette: translucent whites, so the glass behind the panel shows through.
    private let card = NSColor(white: 1, alpha: 0.075), raised = NSColor(white: 1, alpha: 0.20)
    private let text = NSColor(white: 1, alpha: 0.95), muted = NSColor(white: 1, alpha: 0.62), dim = NSColor(white: 1, alpha: 0.42)
    private let accent = hexColor("#7C6CFF"), night = hexColor("#07060B")

    /// Animate only while the panel is on screen.
    func setAnimating(_ on: Bool) {
        timer?.invalidate()
        timer = nil
        guard on else { return }
        let timer = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in self?.needsDisplay = true }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let booster, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let lit = booster.state == .on
        let w = bounds.width

        // The glass behind the panel is the background; only a hairline along the edge is drawn here.
        NSColor(white: 1, alpha: 0.10).setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 26, yRadius: 26).stroke()

        // Header: the name, centred.
        drawLiquidText("XDR BOOST", centeredAt: CGPoint(x: w / 2, y: 20), size: 22, weight: .bold, color: text, kern: 0.6)

        drawHero(ctx, lit: lit)
        drawControls(lit: lit)
    }

    private func drawHero(_ ctx: CGContext, lit: Bool) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: hero, xRadius: 18, yRadius: 18).setClip()
        let t = self.t

        // The colour rises up the bands when the boost turns on and drains when it goes off.
        let now = Date()
        let step = min(now.timeIntervalSince(lastDraw), 0.1) / 1.0
        lastDraw = now
        shownLevel = lit ? min(1, shownLevel + step) : max(0, shownLevel - step)

        let level = shownLevel * shownLevel * (3 - 2 * shownLevel)
        drawGhostScene(ctx, level: level, t: t)

        NSGraphicsContext.restoreGraphicsState()
        // A glass rim around the picture.
        NSColor(white: 1, alpha: 0.22).setStroke()
        NSBezierPath(roundedRect: hero.insetBy(dx: 0.5, dy: 0.5), xRadius: 18, yRadius: 18).stroke()
    }

    /// The ghost on the left watching the MacBook on the right. Off, an empty night: a plain ghost and a dark laptop.
    /// On, the screen throws its light across the deck onto the ghost, which turns to liquid, and the sky lights up.
    private func drawGhostScene(_ ctx: CGContext, level: Double, t: Double) {
        ctx.saveGState()
        // The scene draws y-up; flip about the hero's centre line so it lands in the same rect.
        ctx.translateBy(x: 0, y: hero.midY * 2)
        ctx.scaleBy(x: 1, y: -1)
        let h = hero, srgb = CGColorSpace(name: CGColorSpace.sRGB)

        // Night sky, and coloured haze while lit.
        let sky = [CGColor(srgbRed: 0.04, green: 0.06, blue: 0.13, alpha: 1), CGColor(srgbRed: 0.08, green: 0.12, blue: 0.25, alpha: 1)] as CFArray
        if let g = CGGradient(colorsSpace: srgb, colors: sky, locations: nil) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: h.minY), end: CGPoint(x: 0, y: h.maxY), options: [])
        }
        if level > 0 {
            for (c, r, col) in [(CGPoint(x: h.minX + 30, y: h.maxY - 10), 90.0, (0.25, 0.75, 0.65)),
                                (CGPoint(x: h.maxX - 20, y: h.maxY), 90.0, (0.55, 0.4, 0.95))] {
                let colors = [CGColor(srgbRed: col.0, green: col.1, blue: col.2, alpha: 0.28 * level),
                              CGColor(srgbRed: col.0, green: col.1, blue: col.2, alpha: 0)] as CFArray
                if let g = CGGradient(colorsSpace: srgb, colors: colors, locations: nil) {
                    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
                }
            }
            var seed: UInt64 = 5
            func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(1 << 31) }
            for _ in 0..<60 {
                let x = h.minX + rnd() * h.width, y = h.minY + 16 + rnd() * (h.height - 16), size = 0.5 + rnd() * 0.8
                ctx.setFillColor(CGColor(gray: 1, alpha: level * (0.2 + 0.5 * abs(sin(t * (0.6 + rnd() * 1.6) + rnd() * 6)))))
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: size, height: size))
            }
        }

        // Floor.
        let floorY = h.minY + 12
        ctx.setFillColor(CGColor(srgbRed: 0.03, green: 0.04, blue: 0.10, alpha: 1))
        ctx.fill(CGRect(x: h.minX, y: h.minY, width: h.width, height: floorY - h.minY))

        // The MacBook on the right, its screen facing the ghost.
        let lh = 92.0, lw = lh * MacBookArt.box.width / MacBookArt.box.height
        let laptop = CGRect(x: h.maxX - lw - 6, y: floorY - 4, width: lw, height: lh)
        MacBookArt.draw(ctx, in: laptop, level: level, t: t)

        // The ghost on the left, looking at it.
        let gh = 124.0, gw = gh * GhostArt.box.width / GhostArt.box.height
        let ghostRect = CGRect(x: h.minX + 14, y: floorY, width: gw, height: gh)
        let scale = window?.backingScaleFactor ?? 2
        let liquid = level > 0 ? LiquidGhost.shared?.image(width: Int(gw * scale), height: Int(gh * scale), time: t) : nil
        GhostArt.drawGhost(ctx, in: ghostRect, level: level, t: t, liquid: liquid, detail: true)

        // The screen's light over the deck and the ghost.
        MacBookArt.drawLight(ctx, laptop: laptop, toLeft: h.minX - 10, top: h.maxY + 50, floor: floorY, level: level, t: t)

        if level > 0 {
            for (i, (x, y, r)) in [(0.06, 0.78, 4.0), (0.46, 0.86, 3.5), (0.50, 0.30, 3.0), (0.30, 0.92, 2.5)].enumerated() {
                let colors = [(1.0, 0.5, 0.85), (0.45, 0.9, 0.9), (0.7, 0.6, 1.0)]
                let c = colors[i % colors.count], tw = 0.55 + 0.45 * sin(t * 2.2 + Double(i) * 1.9)
                GhostArt.sparkle(ctx, at: CGPoint(x: h.minX + x * h.width, y: h.minY + y * h.height), r: r * tw,
                                 color: CGColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: level * (0.5 + 0.5 * tw)))
            }
        }
        GhostArt.grain(ctx, clip: nil, in: h, alpha: 0.09)
        ctx.restoreGState()
    }

    private func drawControls(lit: Bool) {
        let w = bounds.width
        var y = hero.maxY + 22

        // The one switch, big and centred, with what it is doing underneath.
        switchRect = CGRect(x: (w - 70) / 2, y: y, width: 70, height: 40)
        drawSwitch(switchRect, on: booster.enabled)
        drawLiquidText(statusLine, centeredAt: CGPoint(x: w / 2, y: y + 58), size: 13, weight: .medium, color: muted)
        y += 84

        // Brightness card: the factor and its nits, a slider, and the part above the live headroom shaded.
        let slider = CGRect(x: pad, y: y, width: w - 2 * pad, height: 88)
        glassCard(slider)
        let inner = pad + 16
        draw("밝기", at: CGPoint(x: inner, y: y + 14), size: 13, weight: .semibold, color: text)
        draw(String(format: "%.2f×  ·  %@ nit", booster.factor, Self.nits(booster.factor)), rightAt: CGPoint(x: w - inner, y: y + 14),
             size: 13, weight: .medium, color: text)
        sliderTrack = CGRect(x: inner + 4, y: y + 44, width: w - 2 * inner - 8, height: 6)
        let track = NSBezierPath(roundedRect: sliderTrack, xRadius: 3, yRadius: 3)
        raised.setFill()
        track.fill()
        let knobX = sliderX(booster.factor)
        (lit ? accent : dim).setFill()
        NSBezierPath(roundedRect: CGRect(x: sliderTrack.minX, y: sliderTrack.minY, width: knobX - sliderTrack.minX,
                                         height: sliderTrack.height), xRadius: 3, yRadius: 3).fill()
        if lit, booster.headroom < Booster.maxFactor {
            let capX = sliderX(booster.headroom)
            NSColor(white: 0, alpha: 0.45).setFill()
            NSBezierPath(roundedRect: CGRect(x: capX, y: sliderTrack.minY, width: sliderTrack.maxX - capX, height: sliderTrack.height),
                         xRadius: 3, yRadius: 3).fill()
        }
        let knob = CGRect(x: knobX - 10, y: sliderTrack.midY - 10, width: 20, height: 20)
        let knobShadow = NSShadow()
        knobShadow.shadowColor = NSColor(white: 0, alpha: 0.4)
        knobShadow.shadowBlurRadius = 4
        NSGraphicsContext.saveGraphicsState()
        knobShadow.set()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: knob).fill()
        NSGraphicsContext.restoreGraphicsState()
        for (v, label) in [(1.0, "1.0×"), (2.0, "2.0× 지속 최대"), (Booster.maxFactor, "3.2×")] {
            let x = sliderX(v), ly = y + 64
            if v == 1.0 { draw(label, at: CGPoint(x: x - 4, y: ly), size: 11, weight: .regular, color: dim) }
            else if v == Booster.maxFactor { draw(label, rightAt: CGPoint(x: x + 4, y: ly), size: 11, weight: .regular, color: dim) }
            else { draw(label, centeredAt: CGPoint(x: x, y: ly), size: 11, weight: .regular, color: dim) }
        }
        y += 88 + 12

        // Options card: two rows with a hairline between.
        let options = CGRect(x: pad, y: y, width: w - 2 * pad, height: 88)
        glassCard(options)
        hotRect = CGRect(x: pad, y: y, width: options.width, height: 44)
        draw("발열 시 자동 일시정지", at: CGPoint(x: inner, y: y + 14), size: 14, weight: .medium, color: text)
        drawSwitch(CGRect(x: w - inner - 40, y: y + 12, width: 40, height: 22), on: booster.pauseWhenHot)
        NSColor(white: 1, alpha: 0.10).setFill()
        NSRect(x: inner, y: y + 44, width: w - 2 * inner, height: 1).fill()
        loginRect = CGRect(x: pad, y: y + 44, width: options.width, height: 44)
        draw("로그인 시 실행", at: CGPoint(x: inner, y: y + 58), size: 14, weight: .medium, color: text)
        drawSwitch(CGRect(x: w - inner - 40, y: y + 56, width: 40, height: 22), on: loginEnabled())
        y += 88 + 16

        // Footer.
        draw("발열 " + thermalText + "  ·  여유 " + String(format: "%.2f×", booster.headroom),
             at: CGPoint(x: pad + 2, y: y), size: 12, weight: .regular, color: dim)
        let quit = "종료"
        let quitW = (quit as NSString).size(withAttributes: [.font: uiFont(13, .semibold)]).width
        quitRect = CGRect(x: w - pad - quitW - 10, y: y - 4, width: quitW + 10, height: 24)
        draw(quit, rightAt: CGPoint(x: w - pad - 2, y: y - 1), size: 13, weight: .semibold, color: muted)
    }

    /// A frosted rounded card with a faint bright rim.
    private func glassCard(_ r: CGRect) {
        let path = NSBezierPath(roundedRect: r, xRadius: 18, yRadius: 18)
        card.setFill()
        path.fill()
        NSColor(white: 1, alpha: 0.12).setStroke()
        NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 18, yRadius: 18).stroke()
    }

    private var statusLine: String {
        switch booster.state {
        case .off: return "꺼짐"
        case .noDisplay: return "내장 XDR 디스플레이를 찾을 수 없음"
        case .pausedThermal: return "발열로 일시정지됨"
        case .on:
            let capped = booster.appliedFactor + 0.01 < booster.factor
            return String(format: "적용 %.2f×", booster.appliedFactor) + (capped ? " · 시스템 한도에 걸림" : " · 켜짐")
        }
    }

    private var thermalText: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "정상"
        case .fair: return "약간 따뜻함"
        case .serious: return "뜨거움"
        case .critical: return "매우 뜨거움"
        @unknown default: return "?"
        }
    }

    private func drawSwitch(_ r: CGRect, on: Bool) {
        (on ? accent : raised).setFill()
        NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2).fill()
        let d = r.height - 4
        NSColor.white.setFill()
        NSBezierPath(ovalIn: CGRect(x: on ? r.maxX - d - 2 : r.minX + 2, y: r.minY + 2, width: d, height: d)).fill()
    }

    // MARK: - Interaction

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if switchRect.insetBy(dx: -6, dy: -6).contains(p) {
            booster.enabled.toggle()
        } else if sliderTrack.insetBy(dx: -10, dy: -12).contains(p) {
            draggingSlider = true
            setFactor(from: p.x)
        } else if hotRect.contains(p) {
            booster.pauseWhenHot.toggle()
        } else if loginRect.contains(p) {
            onToggleLogin()
        } else if quitRect.contains(p) {
            onQuit()
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard draggingSlider else { return }
        setFactor(from: convert(event.locationInWindow, from: nil).x)
    }

    override func mouseUp(with event: NSEvent) { draggingSlider = false }

    private func setFactor(from x: Double) {
        let f = (x - sliderTrack.minX) / sliderTrack.width
        let v = 1 + min(max(f, 0), 1) * (Booster.maxFactor - 1)
        booster.factor = (v * 20).rounded() / 20  // 0.05 steps
        needsDisplay = true
    }

    private func sliderX(_ v: Double) -> Double {
        sliderTrack.minX + (min(max(v, 1), Booster.maxFactor) - 1) / (Booster.maxFactor - 1) * sliderTrack.width
    }

    // MARK: - Text

    /// SDR white is 500 nits on these panels; the factor is linear light.
    private static func nits(_ factor: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: Int((500 * factor).rounded()))) ?? ""
    }

    private func attrs(_ size: Double, _ weight: NSFont.Weight, _ color: NSColor, kern: Double = 0) -> [NSAttributedString.Key: Any] {
        [.font: uiFont(size, weight), .foregroundColor: color, .kern: kern]
    }

    private func draw(_ s: String, at p: CGPoint, size: Double, weight: NSFont.Weight, color: NSColor, kern: Double = 0) {
        (s as NSString).draw(at: p, withAttributes: attrs(size, weight, color, kern: kern))
    }

    private func draw(_ s: String, rightAt p: CGPoint, size: Double, weight: NSFont.Weight, color: NSColor) {
        let a = attrs(size, weight, color)
        (s as NSString).draw(at: CGPoint(x: p.x - (s as NSString).size(withAttributes: a).width, y: p.y), withAttributes: a)
    }

    /// Plain text while off; as the boost comes on the letters turn to flowing liquid metal (LiquidGhost).
    private func drawLiquidText(_ s: String, centeredAt p: CGPoint, size: Double, weight: NSFont.Weight, color: NSColor, kern: Double = 0) {
        let level = shownLevel * shownLevel * (3 - 2 * shownLevel)
        let a = attrs(size, weight, color.withAlphaComponent(color.alphaComponent * (1 - level)), kern: kern)
        let width = (s as NSString).size(withAttributes: a).width
        if level < 1 { (s as NSString).draw(at: CGPoint(x: p.x - width / 2, y: p.y), withAttributes: a) }
        guard level > 0, let ctx = NSGraphicsContext.current?.cgContext,
              let liquid = LiquidGhost.shared?.text(s, size: size, weight: weight, kern: kern, scale: window?.backingScaleFactor ?? 2, time: t)
        else { return }
        // The image is padded around the glyphs; centre it on the plain text's box. The view is flipped, so flip back.
        let textHeight = (s as NSString).size(withAttributes: a).height
        let rect = CGRect(x: p.x - liquid.size.width / 2, y: p.y + textHeight / 2 - liquid.size.height / 2,
                          width: liquid.size.width, height: liquid.size.height)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: rect.midY * 2)
        ctx.scaleBy(x: 1, y: -1)
        ctx.setAlpha(level)
        ctx.draw(liquid.image, in: rect)
        ctx.restoreGState()
    }

    private func draw(_ s: String, centeredAt p: CGPoint, size: Double, weight: NSFont.Weight, color: NSColor, kern: Double = 0) {
        let a = attrs(size, weight, color, kern: kern)
        (s as NSString).draw(at: CGPoint(x: p.x - (s as NSString).size(withAttributes: a).width / 2, y: p.y), withAttributes: a)
    }

    private func draw(_ s: String, centeredIn r: CGRect, size: Double, weight: NSFont.Weight, color: NSColor) {
        let a = attrs(size, weight, color)
        let sz = (s as NSString).size(withAttributes: a)
        (s as NSString).draw(at: CGPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2), withAttributes: a)
    }
}

/// Pretendard when it is installed, else the system font.
func uiFont(_ size: Double, _ weight: NSFont.Weight) -> NSFont {
    let names: [(NSFont.Weight, String)] = [(.ultraLight, "ExtraLight"), (.thin, "ExtraLight"), (.light, "Light"), (.regular, "Regular"),
                                            (.medium, "Medium"), (.semibold, "SemiBold"), (.bold, "Bold"), (.heavy, "ExtraBold"), (.black, "Black")]
    let name = names.first { $0.0 == weight }?.1 ?? "Regular"
    return NSFont(name: "Pretendard-" + name, size: size) ?? .systemFont(ofSize: size, weight: weight)
}

func hexColor(_ s: String) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: s.hasPrefix("#") ? String(s.dropFirst()) : s).scanHexInt64(&v)
    return NSColor(srgbRed: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255, alpha: 1)
}
