import AppKit

/// The ghost, after the user's illustration: a bell-shaped sheet ghost with big oval eyes and a rainbow pouring out
/// of its mouth. Off, a plain silhouette and nothing else. On, the ghost and the rainbow turn to flowing liquid in the
/// chrome of the Siri orb (LiquidGhost) and sparkles show in its eyes.
///
/// Shapes are traced in the illustration's own pixel coordinates (y down) inside `box`, and mapped onto any rect.
enum GhostArt {
    /// The ghost plus its rainbow, in the illustration's pixels.
    static let box = CGRect(x: 600, y: 250, width: 1000, height: 1030)

    /// Illustration pixel → point in `r` (y up).
    private static func p(_ r: CGRect, _ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: r.minX + (x - box.minX) / box.width * r.width, y: r.minY + (box.maxY - y) / box.height * r.height)
    }

    static func ghostPath(in r: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.move(to: p(r, 600, 1280))
        path.addCurve(to: p(r, 830, 470), control1: p(r, 760, 1230), control2: p(r, 800, 760))
        path.addCurve(to: p(r, 1130, 250), control1: p(r, 860, 300), control2: p(r, 990, 250))
        path.addCurve(to: p(r, 1450, 560), control1: p(r, 1300, 250), control2: p(r, 1430, 380))
        path.addCurve(to: p(r, 1500, 1280), control1: p(r, 1470, 800), control2: p(r, 1490, 1180))
        path.closeSubpath()
        return path
    }

    /// The rainbow, from the mouth down to the floor, sweeping out past the ghost's right foot.
    static func streamPath(in r: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.move(to: p(r, 1145, 760))
        path.addCurve(to: p(r, 1270, 1280), control1: p(r, 1140, 1000), control2: p(r, 1230, 1190))
        path.addLine(to: p(r, 1590, 1280))
        path.addCurve(to: p(r, 1250, 760), control1: p(r, 1440, 1220), control2: p(r, 1260, 1000))
        path.closeSubpath()
        return path
    }

    private static func eyeRects(in r: CGRect) -> [CGRect] {
        [1035.0, 1335.0].map { x in
            let c = p(r, x, 550), rx = 46 / box.width * r.width, ry = 76 / box.height * r.height
            return CGRect(x: c.x - rx, y: c.y - ry, width: 2 * rx, height: 2 * ry)
        }
    }

    private static func mouthPath(in r: CGRect) -> CGPath {
        let path = CGMutablePath()
        let c = p(r, 1195, 720), rad = 55 / box.width * r.width
        path.move(to: p(r, 1140, 800))
        path.addLine(to: p(r, 1140, 720))
        path.addArc(center: c, radius: rad, startAngle: .pi, endAngle: 0, clockwise: true)
        path.addLine(to: p(r, 1250, 800))
        path.closeSubpath()
        return path
    }

    // MARK: - Menu bar

    // Menu bars here are 30-33 pt tall; 25 pt fills them without touching the edges.
    static let size = NSSize(width: 26, height: 26)
    private static let iconRect = CGRect(x: 0.8, y: 0.5, width: 24.4, height: 25)

    /// Off: the silhouette with the eyes and mouth cut out, as a template so it takes the menu bar's colour.
    static let off: NSImage = {
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.addPath(ghostPath(in: iconRect))
            ctx.fillPath()
            ctx.setBlendMode(.clear)
            for e in eyeRects(in: iconRect) { ctx.fillEllipse(in: e) }
            ctx.addPath(mouthPath(in: iconRect))
            ctx.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }()

    /// One lit frame. `fade` 0...1 brings the liquid in over the plain ghost when the boost turns on.
    static func lit(t: Double, fade: Double, scale: Double = 2.0) -> NSImage {
        let liquid = LiquidGhost.shared?.image(width: Int(iconRect.width * scale), height: Int(iconRect.height * scale), time: t)
        let image = NSImage(size: size)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return image }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        if let ctx = NSGraphicsContext.current?.cgContext {
            drawGhost(ctx, in: iconRect, level: fade, t: t, liquid: liquid, detail: false)
        }
        NSGraphicsContext.restoreGraphicsState()
        image.addRepresentation(rep)
        return image
    }

    // MARK: - Drawing

    /// The ghost in `r` (y-up context). `level` 0...1 from off to lit; `liquid` is LiquidGhost's image for this rect.
    static func drawGhost(_ ctx: CGContext, in r: CGRect, level: Double, t: Double, liquid: CGImage?, detail: Bool) {
        let ghost = ghostPath(in: r)
        let k = r.height / 100

        // A cool silver aura while lit.
        if level > 0 && detail {
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 16 * k, color: CGColor(srgbRed: 0.72, green: 0.80, blue: 1, alpha: 0.75 * level))
            ctx.addPath(ghost)
            ctx.setFillColor(CGColor(srgbRed: 0.8, green: 0.84, blue: 0.95, alpha: 1))
            ctx.fillPath()
            ctx.restoreGState()
        }

        // The plain sheet, which the liquid fades in over.
        ctx.addPath(ghost)
        ctx.setFillColor(detail ? CGColor(srgbRed: 0.78, green: 0.82, blue: 0.92, alpha: 1)
                                : CGColor(srgbRed: 0.86, green: 0.88, blue: 0.95, alpha: 1))
        ctx.fillPath()
        if let liquid, level > 0 {
            ctx.saveGState()
            ctx.setAlpha(level)
            ctx.draw(liquid, in: r)
            ctx.restoreGState()
        }
        // A thin rim keeps the small icon readable on a light menu bar.
        if !detail {
            ctx.addPath(ghost)
            ctx.setStrokeColor(CGColor(srgbRed: 0.28, green: 0.30, blue: 0.36, alpha: 0.9))
            ctx.setLineWidth(0.7)
            ctx.strokePath()
        }

        if detail { grain(ctx, clip: ghost, in: r, alpha: 0.10) }

        let eyes = eyeRects(in: r)
        guard detail else {
            // Small: plain holes, a silver spark in each eye while lit.
            ctx.setFillColor(CGColor(srgbRed: 0.07, green: 0.10, blue: 0.22, alpha: 1))
            for e in eyes { ctx.fillEllipse(in: e) }
            ctx.addPath(mouthPath(in: r))
            ctx.fillPath()
            if level > 0 {
                ctx.setFillColor(CGColor(srgbRed: 0.86, green: 0.92, blue: 1, alpha: level))
                for e in eyes { ctx.fillEllipse(in: e.insetBy(dx: e.width * 0.3, dy: e.height * 0.3)) }
            }
            return
        }
        for (i, e) in eyes.enumerated() { eye(ctx, e, mobile: mobiles[i], level: level, t: t) }
        mouth(ctx, in: r, level: level, t: t)
        if level > 0 { drips(ctx, in: r, level: level, t: t) }
    }

    // MARK: - Eyes

    /// Each eye is a hole into a night sky with a mobile hanging in it: stars on threads from the top of the hole.
    /// (x across the eye, thread length, star size), all as fractions of the eye.
    private static let mobiles: [[(x: CGFloat, length: CGFloat, size: CGFloat)]] = [
        [(0.40, 0.66, 0.30), (0.72, 0.36, 0.17)],
        [(0.30, 0.38, 0.19), (0.55, 0.80, 0.27), (0.80, 0.50, 0.13)],
    ]

    /// The hole is shaded like the illustration's: dark silver at the top, lighter toward the bottom, and a pale crescent
    /// of inner wall along the lower right that gives it depth.
    private static func eye(_ ctx: CGContext, _ e: CGRect, mobile: [(x: CGFloat, length: CGFloat, size: CGFloat)], level: Double, t: Double) {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)
        ctx.saveGState()
        ctx.addEllipse(in: e)
        ctx.clip()
        // Inner wall first; the sky covers all of it but the crescent.
        ctx.setFillColor(mix((0.20, 0.26, 0.36), (0.52, 0.56, 0.64), level))
        ctx.fill(e)
        let sky = e.offsetBy(dx: -e.width * 0.13, dy: e.height * 0.06)
        ctx.addEllipse(in: sky)
        ctx.clip()
        let colors = [mix((0.04, 0.06, 0.12), (0.05, 0.06, 0.08), level), mix((0.08, 0.10, 0.20), (0.24, 0.27, 0.33), level)] as CFArray
        if let g = CGGradient(colorsSpace: srgb, colors: colors, locations: nil) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: e.maxY), end: CGPoint(x: 0, y: e.minY), options: [])
        }
        guard level > 0 else { ctx.restoreGState(); return }

        // Star dust.
        var seed: UInt64 = UInt64(e.minX * 7) &+ 3
        func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
        for _ in 0..<10 {
            let d = e.width * (0.025 + rnd() * 0.03)
            ctx.setFillColor(CGColor(srgbRed: 0.75 + rnd() * 0.25, green: 0.82, blue: 0.92, alpha: 0.5 * level))
            ctx.fillEllipse(in: CGRect(x: e.minX + rnd() * e.width, y: e.minY + rnd() * e.height, width: d, height: d))
        }

        // The mobile: each star swings gently on its thread.
        for (i, m) in mobile.enumerated() {
            let pivot = CGPoint(x: e.minX + m.x * e.width, y: e.maxY)
            let swing = 0.09 * sin(t * (1.1 + 0.23 * Double(i)) + Double(i) * 1.7)
            let len = m.length * e.height
            let star = CGPoint(x: pivot.x + len * sin(swing), y: pivot.y - len * cos(swing))
            ctx.setStrokeColor(CGColor(srgbRed: 0.88, green: 0.90, blue: 0.96, alpha: 0.75 * level))
            ctx.setLineWidth(max(0.35, e.width * 0.025))
            ctx.move(to: pivot)
            ctx.addLine(to: star)
            ctx.strokePath()
            let size = m.size * e.width * (0.92 + 0.08 * sin(t * 2.4 + Double(i)))
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: size * 0.8, color: CGColor(srgbRed: 0.66, green: 0.78, blue: 1, alpha: level))
            sparkle(ctx, at: CGPoint(x: star.x, y: star.y - size), r: size, color: CGColor(srgbRed: 0.84, green: 0.89, blue: 1, alpha: level))
            sparkle(ctx, at: CGPoint(x: star.x, y: star.y - size), r: size * 0.45, color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: level))
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    // MARK: - Mouth

    /// A dark graphite hole with a little star dust; while lit, a drop of the liquid wobbles on its lower lip.
    private static func mouth(_ ctx: CGContext, in r: CGRect, level: Double, t: Double) {
        let path = mouthPath(in: r)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.setFillColor(mix((0.06, 0.08, 0.16), (0.04, 0.05, 0.07), level))
        ctx.fill(r)
        if level > 0 {
            var seed: UInt64 = 9
            func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
            let box = path.boundingBox
            for _ in 0..<14 {
                let d = box.width * (0.02 + rnd() * 0.025)
                ctx.setFillColor(CGColor(srgbRed: 0.6 + rnd() * 0.3, green: 0.72, blue: 0.82 + rnd() * 0.18, alpha: 0.6 * level))
                ctx.fillEllipse(in: CGRect(x: box.minX + rnd() * box.width, y: box.minY + rnd() * box.height, width: d, height: d))
            }
        }
        ctx.restoreGState()
    }

    /// Point on the stream, `s` 0 at the mouth to 1 at the floor, `across` 0 at its left edge to 1 at its right.
    private static func streamPoint(in r: CGRect, _ s: CGFloat, across: CGFloat) -> CGPoint {
        func bezier(_ q: [(CGFloat, CGFloat)]) -> CGPoint {
            let u = 1 - s, w = [u * u * u, 3 * u * u * s, 3 * u * s * s, s * s * s]
            let pts = q.map { p(r, $0.0, $0.1) }
            return CGPoint(x: zip(w, pts).map { $0 * $1.x }.reduce(0, +), y: zip(w, pts).map { $0 * $1.y }.reduce(0, +))
        }
        let left = bezier([(1145, 760), (1140, 1000), (1230, 1190), (1270, 1280)])
        let right = bezier([(1250, 760), (1260, 1000), (1440, 1220), (1590, 1280)])
        return CGPoint(x: left.x + (right.x - left.x) * across, y: left.y + (right.y - left.y) * across)
    }

    /// Liquid running out of the mouth: drips slide down the dark side of the stream, stretching as they go, and a
    /// drop swells on the lower lip.
    private static func drips(_ ctx: CGContext, in r: CGRect, level: Double, t: Double) {
        let k = r.width / box.width
        let silver = CGColor(srgbRed: 0.86, green: 0.90, blue: 0.97, alpha: level)
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setStrokeColor(silver)
        for (i, (period, across)) in [(3.2, 0.91), (4.4, 0.87)].enumerated() {
            let phase = ((t + Double(i) * 1.6) / period).truncatingRemainder(dividingBy: 1)
            let head = 0.04 + 0.5 * phase * phase              // speeds up as it runs
            let tail = max(0.04, head - 0.1 - 0.12 * phase)
            ctx.setAlpha(min(1, (1 - phase) * 4))               // thins out at the end
            let path = CGMutablePath()
            path.move(to: streamPoint(in: r, tail, across: across))
            for j in 1...8 { path.addLine(to: streamPoint(in: r, tail + (head - tail) * CGFloat(j) / 8, across: across)) }
            ctx.setLineWidth(max(0.8, 12 * k))
            ctx.addPath(path)
            ctx.strokePath()
            let tip = streamPoint(in: r, head, across: across)  // the bead at its head
            let bead = max(1.2, 10 * k)
            ctx.fillEllipse(in: CGRect(x: tip.x - bead, y: tip.y - bead, width: 2 * bead, height: 2 * bead))
        }
        ctx.setAlpha(1)
        // The drop on the lip.
        let swell = 0.8 + 0.2 * sin(t * 2.1)
        let lip = p(r, 1178, 798)
        ctx.setFillColor(silver)
        ctx.fillEllipse(in: CGRect(x: lip.x - 24 * k, y: lip.y - 8 * k * swell, width: 46 * k, height: 15 * k * swell))
        ctx.restoreGState()
    }

    // MARK: - Texture

    /// Film grain, like the illustration's print texture.
    static let grainTile: CGImage? = {
        let n = 128
        var seed: UInt64 = 1
        let bytes = (0..<(n * n)).map { _ -> UInt8 in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return UInt8(truncatingIfNeeded: seed >> 56)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: n, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }()

    /// Overlays grain inside `clip` (or all of `rect` without one).
    static func grain(_ ctx: CGContext, clip: CGPath?, in rect: CGRect, alpha: Double) {
        guard let tile = grainTile else { return }
        ctx.saveGState()
        if let clip { ctx.addPath(clip); ctx.clip() } else { ctx.clip(to: rect) }
        ctx.setBlendMode(.overlay)
        ctx.setAlpha(alpha)
        // Tile at half a point per grain, so it stays fine on Retina.
        ctx.draw(tile, in: CGRect(x: rect.minX, y: rect.minY, width: 64, height: 64), byTiling: true)
        ctx.restoreGState()
    }

    private static func mix(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ f: Double) -> CGColor {
        CGColor(srgbRed: a.0 + (b.0 - a.0) * f, green: a.1 + (b.1 - a.1) * f, blue: a.2 + (b.2 - a.2) * f, alpha: 1)
    }

    /// A four-pointed star.
    static func sparkle(_ ctx: CGContext, at c: CGPoint, r: CGFloat, color: CGColor) {
        let path = CGMutablePath()
        let n = r * 0.22
        path.move(to: CGPoint(x: c.x, y: c.y + r))
        path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + n, y: c.y + n))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x + n, y: c.y - n))
        path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - n, y: c.y - n))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x - n, y: c.y + n))
        ctx.setFillColor(color)
        ctx.addPath(path)
        ctx.fillPath()
    }
}
