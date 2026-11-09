import AppKit

/// A MacBook Pro seen from behind and to the right, after the user's reference render: the back of the lid faces us,
/// the screen faces left, and the keyboard deck runs off to the lower left. Lit, the screen throws its light out to the
/// left (in the colours of the M1 Pro wallpaper) across the deck and onto whatever stands there; the Apple logo glows
/// on the lid.
///
/// Shapes are traced in the reference's pixel coordinates (y down) inside `box`, and mapped onto any rect.
enum MacBookArt {
    static let box = CGRect(x: 170, y: 140, width: 1630, height: 1220)

    private static func p(_ r: CGRect, _ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: r.minX + (x - box.minX) / box.width * r.width, y: r.minY + (box.maxY - y) / box.height * r.height)
    }

    private static func polygon(_ r: CGRect, _ points: [(CGFloat, CGFloat)]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points.map { p(r, $0.0, $0.1) })
        path.closeSubpath()
        return path
    }

    /// The lid's outline: a quad with rounded corners.
    private static func lidPath(_ r: CGRect) -> CGPath {
        let corners = [(878.0, 222.0), (1792.0, 152.0), (1782.0, 1072.0), (892.0, 1305.0)].map { p(r, $0.0, $0.1) }
        let radius = 34 / box.width * r.width
        let path = CGMutablePath()
        path.move(to: CGPoint(x: (corners[3].x + corners[0].x) / 2, y: (corners[3].y + corners[0].y) / 2))
        for i in 0..<4 {
            path.addArc(tangent1End: corners[i], tangent2End: corners[(i + 1) % 4], radius: radius)
        }
        path.closeSubpath()
        return path
    }

    /// Where the screen's light leaves the lid: its left edge, top and bottom.
    static func screenEdge(in r: CGRect) -> (top: CGPoint, bottom: CGPoint) { (p(r, 880, 250), p(r, 892, 1285)) }

    /// The whole laptop in `r` (y-up context). `level` 0...1 from off to lit.
    static func draw(_ ctx: CGContext, in r: CGRect, level: Double, t: Double) {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)
        func gray(_ off: Double, _ on: Double) -> CGColor {
            let v = off + (on - off) * level
            return CGColor(srgbRed: v, green: v, blue: v * 1.02, alpha: 1)
        }
        func linear(_ path: CGPath, _ colors: [CGColor], from a: CGPoint, to b: CGPoint) {
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            if let g = CGGradient(colorsSpace: srgb, colors: colors as CFArray, locations: nil) {
                ctx.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            ctx.restoreGState()
        }

        // A soft shadow on the floor.
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: r.height * 0.08, color: CGColor(gray: 0, alpha: 0.8))
        ctx.addPath(polygon(r, [(178, 1150), (900, 1355), (1700, 1110), (1100, 1000)]))
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.6))
        ctx.fillPath()
        ctx.restoreGState()

        // Base: the side facing us with its ports, then the deck, trackpad and keyboard, lit from the screen side.
        let side = polygon(r, [(178, 1138), (895, 1318), (895, 1356), (196, 1178)])
        linear(side, [gray(0.22, 0.62), gray(0.16, 0.42)], from: p(r, 178, 1140), to: p(r, 895, 1340))
        ctx.setFillColor(CGColor(gray: 0.08, alpha: 1))
        for (x0, x1) in [(600.0, 680.0), (705.0, 725.0), (755.0, 795.0)] {
            ctx.addPath(polygon(r, [(x0, 1296 + (x0 - 600) * 0.05), (x1, 1300 + (x1 - 600) * 0.05),
                                    (x1, 1316 + (x1 - 600) * 0.05), (x0, 1312 + (x0 - 600) * 0.05)]))
        }
        ctx.fillPath()

        let deck = polygon(r, [(178, 1138), (880, 955), (895, 1318)])
        linear(deck, [gray(0.26, 0.55), gray(0.32, 0.82)], from: p(r, 178, 1138), to: p(r, 880, 1150))
        let trackpad = polygon(r, [(462, 1052), (876, 966), (878, 1008), (522, 1088)])
        linear(trackpad, [gray(0.24, 0.62), gray(0.30, 0.78)], from: p(r, 462, 1060), to: p(r, 876, 990))
        let keyboard = polygon(r, [(575, 1182), (878, 1096), (884, 1262), (830, 1268)])
        ctx.addPath(keyboard)
        ctx.setFillColor(CGColor(gray: 0.07, alpha: 1))
        ctx.fillPath()
        // Key tops catch the screen's light.
        ctx.saveGState()
        ctx.addPath(keyboard)
        ctx.clip()
        ctx.setStrokeColor(gray(0.22, 0.6))
        ctx.setLineWidth(max(0.5, r.height / 220))
        for row in 0..<6 {
            let y0 = 1150.0 + Double(row) * 22
            var x = 590.0 + Double(row) * 18
            while x < 880 {
                let len = (row == 5 && x > 700 && x < 760) ? 70.0 : 22.0
                ctx.move(to: p(r, x, y0 - (x - 590) * 0.28 + 10))
                ctx.addLine(to: p(r, x + len, y0 - (x + len - 590) * 0.28 + 10))
                x += len + 8
            }
        }
        ctx.strokePath()
        ctx.restoreGState()

        // Lid, back side: brushed grey, lighter toward the hinge, with its left rim catching the light.
        let lid = lidPath(r)
        linear(lid, [gray(0.30, 0.66), gray(0.20, 0.40)], from: p(r, 900, 1300), to: p(r, 1790, 160))
        ctx.saveGState()
        ctx.setStrokeColor(gray(0.32, 0.86))
        ctx.setLineWidth(max(0.6, r.width / 260))
        ctx.move(to: p(r, 878, 240))
        ctx.addLine(to: p(r, 890, 1290))
        ctx.strokePath()
        ctx.restoreGState()

        // The Apple logo on the lid. The lid is seen at a steep angle, so the logo is squeezed sideways (about 60% of its
        // frontal width in the reference) and follows the lid's top edge, which rises to the right.
        let k = r.width / box.width
        let logoH = 258 * k, logoW = logoH * 100 / 120
        let c = p(r, 1392, 702)
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.concatenate(CGAffineTransform(a: 0.62, b: 0.077 * 0.62, c: 0, d: 1, tx: 0, ty: 0))
        if level > 0 {
            ctx.setShadow(offset: .zero, blur: logoH * 0.22, color: CGColor(srgbRed: 1, green: 0.95, blue: 1, alpha: level))
        }
        let glow = 0.88 + 0.12 * sin(t * 1.6)
        ctx.addPath(applePath(in: CGRect(x: -logoW / 2, y: -logoH / 2, width: logoW, height: logoH)))
        ctx.setFillColor(CGColor(gray: 0.06 + 0.92 * level * glow, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()
    }

    /// The Apple logo in `r` (y-up), drawn from a 100×120 grid (y down).
    private static func applePath(in r: CGRect) -> CGPath {
        func q(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x / 100 * r.width, y: r.maxY - y / 120 * r.height) }
        let path = CGMutablePath()
        path.move(to: q(50, 36))
        path.addCurve(to: q(8, 58), control1: q(40, 28), control2: q(14, 28))
        path.addCurve(to: q(36, 112), control1: q(4, 84), control2: q(24, 112))
        path.addCurve(to: q(50, 108), control1: q(44, 112), control2: q(46, 108))
        path.addCurve(to: q(66, 112), control1: q(54, 108), control2: q(57, 112))
        path.addCurve(to: q(94, 76), control1: q(76, 112), control2: q(90, 92))
        path.addCurve(to: q(88, 44), control1: q(82, 70), control2: q(78, 56))
        path.addCurve(to: q(50, 36), control1: q(76, 28), control2: q(60, 28))
        path.closeSubpath()
        path.move(to: q(52, 30))
        path.addCurve(to: q(74, 4), control1: q(52, 16), control2: q(62, 6))
        path.addCurve(to: q(52, 30), control1: q(74, 16), control2: q(64, 28))
        path.closeSubpath()
        return path
    }

    /// The screen's light: a fan from the lid's left edge out to `reach` (a point far to the left), in silver
    /// with faint ice-blue, gold and blush tints, slowly drifting, fading with distance. Screen-blended, so it brightens what it hits.
    static func drawLight(_ ctx: CGContext, laptop r: CGRect, toLeft x: CGFloat, top: CGFloat, floor: CGFloat, level: Double, t: Double) {
        guard level > 0 else { return }
        let edge = screenEdge(in: r), srgb = CGColorSpace(name: CGColorSpace.sRGB)
        let fan = CGMutablePath()
        fan.addLines(between: [edge.top, CGPoint(x: x, y: top), CGPoint(x: x, y: floor), edge.bottom])
        fan.closeSubpath()

        ctx.saveGState()
        ctx.setBlendMode(.screen)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.addPath(fan)
        ctx.clip()
        // Bands of colour across the fan, drifting up and down.
        let drift = 0.12 * sin(t * 0.7)
        let hues: [(Double, Double, Double)] = [(0.62, 0.72, 1.0), (0.80, 0.84, 0.95), (0.96, 0.90, 0.80), (0.90, 0.78, 0.90), (0.58, 0.68, 0.98)]
        // The top of the fan fades out, so it has no hard edge across the sky.
        let colors = hues.enumerated().map { i, c in
            CGColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: (i == 0 ? 0 : 0.55) * level)
        } as CFArray
        let locations: [CGFloat] = [0, 0.4 + drift, 0.58 + drift * 0.5, 0.76 + drift, 1]
        if let g = CGGradient(colorsSpace: srgb, colors: colors, locations: locations) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: floor), options: [])
        }
        // Fade with distance from the screen.
        ctx.setBlendMode(.destinationIn)
        let fade = [CGColor(gray: 0, alpha: 1), CGColor(gray: 0, alpha: 0.35), CGColor(gray: 0, alpha: 0)] as CFArray
        if let g = CGGradient(colorsSpace: srgb, colors: fade, locations: [0, 0.55, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: edge.top.x, y: 0), end: CGPoint(x: x, y: 0), options: [])
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
}
