import AppKit
import Metal

/// The ghost's lit look: the liquid-metal shader from paper-design/liquid-logo (https://github.com/paper-design/liquid-logo,
/// PolyForm Shield 1.0.0, https://polyformproject.org/licenses/shield/1.0.0), ported to Metal and recoloured with the
/// ghost illustration's pastels. As there, the shape comes in as a bevelled mask (a Poisson solve inside the shape),
/// and stripes flow across it with a small per-channel refraction offset.
///
/// Two masks share one texture: R is the whole ghost, G is the rainbow pouring out of its mouth, and B is how far across
/// the stream each point is. The ghost gets pale, mostly white stripes; the stream gets the palette in lengthwise bands.
final class LiquidGhost {
    static let shared = LiquidGhost()

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private lazy var mask: MTLTexture? = makeMask()
    private var targets: [String: MTLTexture] = [:]

    // liquid-logo's defaults, a touch more refraction for colour.
    private struct Uniforms {
        var time: Float = 0
        var ratio: Float = Float(GhostArt.box.width / GhostArt.box.height)
        var patternScale: Float = 2
        var refraction: Float = 0.02
        var edge: Float = 0.25
        var patternBlur: Float = 0.005
        var liquid: Float = 0.07
        var textMode: Float = 0   // 1: the mask's alpha is glyph coverage, and gives the result's opacity
    }

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.shader, options: nil) else { return nil }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "liquid_vertex")
        desc.fragmentFunction = library.makeFunction(name: "liquid_fragment")
        desc.colorAttachments[0].pixelFormat = .rgba8Unorm
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: desc),
              let sampler = device.makeSamplerState(descriptor: samplerDesc) else { return nil }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.sampler = sampler
    }

    /// The liquid ghost (premultiplied, transparent outside the shape) at `width`×`height` pixels, covering
    /// `GhostArt.box`. `time` in seconds.
    func image(width: Int, height: Int, time: Double) -> CGImage? {
        guard let mask else { return nil }
        return render(mask: mask, ratio: Float(GhostArt.box.width / GhostArt.box.height), text: false, width: width, height: height, time: time)
    }

    private func render(mask: MTLTexture, ratio: Float, text: Bool, width: Int, height: Int, time: Double) -> CGImage? {
        guard width > 0, height > 0, let target = target(width, height), let buffer = queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        var u = Uniforms()
        u.ratio = ratio
        u.textMode = text ? 1 : 0
        if text { u.patternScale = 5; u.refraction = 0.03 }  // letters are small: finer bands, a stronger colour split
        u.time = Float((time * 0.3).truncatingRemainder(dividingBy: 1000))  // liquid-logo's default speed
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(mask, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        if target.storageMode == .managed, let blit = buffer.makeBlitCommandEncoder() {
            blit.synchronize(resource: target)
            blit.endEncoding()
        }
        buffer.commit()
        buffer.waitUntilCompleted()

        let rowBytes = width * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * height)
        target.getBytes(&bytes, bytesPerRow: rowBytes, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    // MARK: - Text

    private var textMasks: [String: (texture: MTLTexture, width: Int, height: Int)] = [:]

    /// `string` as liquid metal: the same shader as the ghost, over the glyphs' bevelled shape. The image is
    /// transparent outside the letters; `size` is in points, at `scale` pixels per point.
    func text(_ string: String, size: Double, weight: NSFont.Weight, kern: Double = 0, scale: CGFloat = 2, time: Double) -> (image: CGImage, size: CGSize)? {
        let key = "\(string)|\(size)|\(weight.rawValue)|\(kern)|\(scale)"
        if textMasks[key] == nil {
            if textMasks.count > 40 { textMasks.removeAll() }
            textMasks[key] = makeTextMask(string, size: size, weight: weight, kern: kern, scale: scale)
        }
        guard let m = textMasks[key],
              let image = render(mask: m.texture, ratio: 1, text: true, width: m.width, height: m.height, time: time) else { return nil }
        return (image, CGSize(width: CGFloat(m.width) / scale, height: CGFloat(m.height) / scale))
    }

    /// Same recipe as the ghost's: coverage for the outline, a Poisson bevel inside it. The glyphs' coverage goes in
    /// alpha so their edges stay smooth.
    private func makeTextMask(_ string: String, size: Double, weight: NSFont.Weight, kern: Double, scale: CGFloat) -> (texture: MTLTexture, width: Int, height: Int)? {
        let attributed = NSAttributedString(string: string, attributes: [
            .font: uiFont(size * Double(scale), weight), .foregroundColor: NSColor.white, .kern: kern * Double(scale)])
        let textSize = attributed.size()
        let pad = Int(ceil(size * Double(scale) * 0.25))
        let w = Int(ceil(textSize.width)) + 2 * pad, h = Int(ceil(textSize.height)) + 2 * pad
        var coverage = [UInt8](repeating: 0, count: w * h)
        coverage.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            attributed.draw(at: CGPoint(x: pad, y: pad))
            NSGraphicsContext.restoreGraphicsState()
        }
        let bevel = Self.bevel(coverage.map { $0 > 127 }, w, h)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            bytes[4 * i] = UInt8(bevel[i] * 255)
            bytes[4 * i + 1] = 255
            bytes[4 * i + 3] = coverage[i]
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        desc.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: bytes, bytesPerRow: w * 4)
        return (texture, w, h)
    }

    private func target(_ width: Int, _ height: Int) -> MTLTexture? {
        let key = "\(width)x\(height)"
        if let t = targets[key] { return t }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget]
        desc.storageMode = device.hasUnifiedMemory ? .shared : .managed
        let t = device.makeTexture(descriptor: desc)
        targets[key] = t
        return t
    }

    // MARK: - Mask

    /// liquid-logo's parse-logo-image, for our two shapes: inside each, solve Δu = -C with u = 0 on the border, then
    /// edge = 1 - (u / max)², which is 1 on and outside the border and falls toward the middle. Fewer iterations than
    /// there, as this mask is a fifth of the size: the bevel ends up about as wide relative to the shape.
    private func makeMask() -> MTLTexture? {
        let w = 200, h = Int((200 * GhostArt.box.height / GhostArt.box.width).rounded())
        let ghost = Self.rasterize(w, h) { GhostArt.ghostPath(in: $0).union(GhostArt.streamPath(in: $0)) }
        let stream = Self.rasterize(w, h) { GhostArt.streamPath(in: $0) }
        let r = Self.bevel(ghost, w, h), g = Self.bevel(stream, w, h)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            let row = (0..<w).filter { stream[y * w + $0] }
            let left = row.first ?? 0, span = max((row.last ?? 0) - left, 1)
            for x in 0..<w {
                let i = y * w + x
                bytes[4 * i] = UInt8(r[i] * 255)
                bytes[4 * i + 1] = UInt8(g[i] * 255)
                bytes[4 * i + 2] = UInt8(min(max(Double(x - left) / Double(span), 0), 1) * 255)
                bytes[4 * i + 3] = 255
            }
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        desc.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: desc) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: bytes, bytesPerRow: w * 4)
        return texture
    }

    /// Inside/outside per pixel, row 0 at the top.
    private static func rasterize(_ w: Int, _ h: Int, path: (CGRect) -> CGPath) -> [Bool] {
        var pixels = [UInt8](repeating: 0, count: w * h)
        pixels.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.addPath(path(CGRect(x: 0, y: 0, width: w, height: h)))
            ctx.fillPath()
        }
        return pixels.map { $0 > 127 }
    }

    private static func bevel(_ inside: [Bool], _ w: Int, _ h: Int) -> [Float] {
        func isIn(_ x: Int, _ y: Int) -> Bool { x >= 0 && x < w && y >= 0 && y < h && inside[y * w + x] }
        var border = [Bool](repeating: false, count: w * h)
        for y in 0..<h { for x in 0..<w where inside[y * w + x] {
            border[y * w + x] = !(isIn(x - 1, y) && isIn(x + 1, y) && isIn(x, y - 1) && isIn(x, y + 1))
        } }
        var u = [Float](repeating: 0, count: w * h), next = u
        for _ in 0..<60 {
            for y in 0..<h { for x in 0..<w {
                let i = y * w + x
                guard inside[i], !border[i] else { next[i] = 0; continue }
                next[i] = (0.01 + u[i - 1] + u[i + 1] + u[i - w] + u[i + w]) / 4
            } }
            swap(&u, &next)
        }
        let top = max(u.max() ?? 1, 1e-6)
        return (0..<(w * h)).map { inside[$0] ? 1 - pow(u[$0] / top, 2) : 1 }
    }

    // MARK: - Shader

    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms { float time, ratio, patternScale, refraction, edge, patternBlur, liquid, textMode; };
    struct VOut { float4 position [[position]]; float2 uv; };

    vertex VOut liquid_vertex(uint id [[vertex_id]]) {
        float2 p = float2(id == 1 ? 3.0 : -1.0, id == 2 ? 3.0 : -1.0);
        VOut o;
        o.position = float4(p, 0, 1);
        o.uv = float2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);   // origin top-left, like the mask
        return o;
    }

    #define PI 3.14159265358979323846

    float3 mod289(float3 x) { return x - floor(x * (1. / 289.)) * 289.; }
    float2 mod289(float2 x) { return x - floor(x * (1. / 289.)) * 289.; }
    float3 permute(float3 x) { return mod289(((x * 34.) + 1.) * x); }
    float snoise(float2 v) {
        const float4 C = float4(0.211324865405187, 0.366025403784439, -0.577350269189626, 0.024390243902439);
        float2 i = floor(v + dot(v, C.yy));
        float2 x0 = v - i + dot(i, C.xx);
        float2 i1 = (x0.x > x0.y) ? float2(1., 0.) : float2(0., 1.);
        float4 x12 = x0.xyxy + C.xxzz;
        x12.xy -= i1;
        i = mod289(i);
        float3 p = permute(permute(i.y + float3(0., i1.y, 1.)) + i.x + float3(0., i1.x, 1.));
        float3 m = max(0.5 - float3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.);
        m = m * m; m = m * m;
        float3 x = 2. * fract(p * C.www) - 1.;
        float3 h = abs(x) - 0.5;
        float3 ox = floor(x + 0.5);
        float3 a0 = x - ox;
        m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
        float3 g;
        g.x = a0.x * x0.x + h.x * x0.y;
        g.yz = a0.yz * x12.xz + h.yz * x12.yw;
        return 130. * dot(m, g);
    }

    float2 rotate(float2 uv, float th) { return float2x2(float2(cos(th), sin(th)), float2(-sin(th), cos(th))) * uv; }

    // c1 = 1, c2 = 0: how much of the light stripe each point gets.
    float channel(float stripe_p, float3 w, float blur, float b) {
        float ch = 0.;
        ch = mix(ch, 1., smoothstep(.0, blur, stripe_p));
        float border = w[0];
        ch = mix(ch, 0., smoothstep(border - blur, border + blur, stripe_p));
        b = smoothstep(.2, .8, b);
        border = w[0] + .4 * (1. - b) * w[1];
        ch = mix(ch, 1., smoothstep(border - blur, border + blur, stripe_p));
        border = w[0] + .5 * (1. - b) * w[1];
        ch = mix(ch, 0., smoothstep(border - blur, border + blur, stripe_p));
        border = w[0] + w[1];
        ch = mix(ch, 1., smoothstep(border - blur, border + blur, stripe_p));
        float gradient_t = (stripe_p - w[0] - w[1]) / w[2];
        ch = mix(ch, smoothstep(0., 1., gradient_t), smoothstep(border - blur, border + blur, stripe_p));
        return ch;
    }

    float wrap(float x) { return x - floor(x); }

    // liquid-logo's main(), for one bevelled mask value: the stripe light per channel in rgb, opacity in a; the stripe
    // position (for colouring) in phase.
    float4 liquid(float edge, float2 uv, float t, float noise, constant Uniforms &u, thread float &phase) {
        float diagonal = uv.x - uv.y;
        float2 grad_uv = uv - .5;
        float dist = length(grad_uv + float2(0., .2 * diagonal));
        grad_uv = rotate(grad_uv, (.25 - .2 * diagonal) * PI);
        float bulge = 1. - pow(1.8 * dist, 1.2);
        bulge *= pow(uv.y, .3);

        float cycle_width = u.patternScale;
        float thin1 = .12 / cycle_width * (1. - .4 * bulge);
        float thin2 = .07 / cycle_width * (1. + .4 * bulge);
        float wide = 1. - thin1 - thin2;

        float opacity = 1. - smoothstep(.9 - .5 * u.edge, 1. - .5 * u.edge, edge);
        edge += (1. - edge) * u.liquid * noise;

        float refr = clamp(1. - bulge, 0., 1.);
        float dir = grad_uv.x + diagonal;
        dir -= 2. * noise * diagonal * (smoothstep(0., 1., edge) * smoothstep(1., 0., edge));
        bulge *= clamp(pow(uv.y, .1), .3, 1.);
        dir *= (.1 + (1.1 - edge) * bulge);
        dir *= smoothstep(1., .7, edge);
        dir += .18 * (smoothstep(.1, .2, uv.y) * smoothstep(.4, .2, uv.y));
        dir += .03 * (smoothstep(.1, .2, 1. - uv.y) * smoothstep(.4, .2, 1. - uv.y));
        dir *= (.5 + .5 * pow(uv.y, 2.));
        dir *= cycle_width;
        dir -= t;
        phase = dir;

        float refr_r = refr + .03 * bulge * noise;
        float refr_b = 1.3 * refr;
        refr_r += 5. * (smoothstep(-.1, .2, uv.y) * smoothstep(.5, .1, uv.y)) * (smoothstep(.4, .6, bulge) * smoothstep(1., .4, bulge));
        refr_r -= diagonal;
        refr_b += (smoothstep(0., .4, uv.y) * smoothstep(.8, .1, uv.y)) * (smoothstep(.4, .6, bulge) * smoothstep(.8, .4, bulge));
        refr_b -= .2 * edge;
        refr_r *= u.refraction;
        refr_b *= u.refraction;

        float3 w = float3(cycle_width * thin1, cycle_width * thin2, wide);
        w[1] -= .02 * smoothstep(.0, 1., edge + bulge);
        float r = channel(wrap(dir + refr_r), w, .02 + .03 * u.refraction * bulge, bulge);
        float g = channel(wrap(dir), w, .01 / (1. - diagonal), bulge);
        float b = channel(wrap(dir - refr_b), w, .01, bulge);
        return float4(r, g, b, opacity);
    }

    // The illustration's pastels, cycling: pink, peach, aqua, sky blue, violet.
    float3 palette(float x) {
        const float3 c[5] = { float3(1., .44, .80), float3(1., .62, .55), float3(.36, .92, .84), float3(.36, .64, 1.), float3(.62, .48, 1.) };
        x = wrap(x) * 5.;
        int i = int(x);
        return mix(c[i % 5], c[(i + 1) % 5], smoothstep(0., 1., fract(x)));
    }

    fragment float4 liquid_fragment(VOut in [[stage_in]], texture2d<float> mask [[texture(0)]], sampler s [[sampler(0)]],
                                    constant Uniforms &u [[buffer(0)]]) {
        float2 uv = in.uv;
        uv.x *= u.ratio;
        float t = u.time;
        float4 img = mask.sample(s, in.uv);
        float noise = snoise(uv - t);

        float ghostPhase, streamPhase;
        float4 ghost = liquid(img.r, uv, t, noise, u, ghostPhase);
        float4 stream = liquid(img.g, uv, t + .37, noise, u, streamPhase);

        // The ghost: white light stripes with a faint tint, dusky violet dark ones.
        float3 tint = palette(ghostPhase * .5 + uv.y * .4);
        float3 ghostColor = mix(mix(float3(.40, .43, .74), tint, .35 + .35 * u.textMode), mix(float3(.97, .97, 1.), tint, .14 + .45 * u.textMode), ghost.rgb);
        // The stream, as in the illustration: pink on the left through lavender to aqua, then a dark side on the
        // right. Ripples run down it, so it reads as pouring out of the mouth.
        float flow = u.time / .3;   // back to seconds
        float across = img.b + .07 * sin(in.uv.y * 18. - flow * 4.) + .03 * sin(in.uv.y * 41. - flow * 7. + 1.3);
        float along = in.uv.y + .05 * sin(flow * .8);
        float3 hue = mix(float3(1., .42, .82), float3(.66, .62, 1.), smoothstep(.05, .38, across));
        hue = mix(hue, float3(.38, .92, .86), smoothstep(.38, .66, across));
        hue = mix(hue, float3(.46, .80, 1.), .35 * smoothstep(.75, .4, along) * smoothstep(.3, .6, across));
        float3 streamColor = mix(hue * .72, mix(hue, float3(1.), .22), stream.rgb);
        streamColor = mix(streamColor, float3(.07, .22, .24), smoothstep(.76, .82, across));

        float3 color = mix(ghostColor, streamColor, stream.a);
        // Print grain.
        float grain = fract(sin(dot(floor(in.position.xy), float2(12.9898, 78.233))) * 43758.5453) - .5;
        color += grain * .06;
        // Text keeps its own glyph coverage as opacity, and lifts the dark stripes so thin strokes stay legible.
        color = mix(color, mix(color, float3(.8, .82, 1.), .15), u.textMode);
        float alpha = mix(ghost.a, img.a, u.textMode);
        return float4(color * alpha, alpha);
    }
    """
}
