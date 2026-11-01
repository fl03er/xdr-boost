import AppKit
import MetalKit

/// An always-on-top, click-through window over the whole screen showing EDR content (a value above 1.0). While it is
/// on screen macOS keeps that display in EDR mode, and its `multiply` compositing multiplies everything under it by
/// `value`, which is the boost itself.
final class EDROverlay: NSObject, MTKViewDelegate {
    private let window: NSWindow
    private let view: MTKView
    private let queue: MTLCommandQueue
    var value: Double = 1.0

    init?(screen: NSScreen) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.queue = queue
        let frame = screen.frame
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.animationBehavior = .none
        window.sharingType = .none  // keep it out of screenshots and recordings
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        view = MTKView(frame: NSRect(origin: .zero, size: frame.size), device: device)
        view.colorPixelFormat = .rgba16Float
        view.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        // Keep presenting frames: once EDR content stops updating, macOS drops it back to SDR brightness after a
        // moment (the boost only held while the slider was moving). 5 fps is what BrightIntosh uses.
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 5
        // A single flat colour: one pixel stretched over the window is enough and costs nothing to redraw.
        view.autoResizeDrawable = false
        view.drawableSize = CGSize(width: 1, height: 1)
        view.autoresizingMask = [.width, .height]
        super.init()
        if let layer = view.layer as? CAMetalLayer {
            layer.wantsExtendedDynamicRangeContent = true
            layer.isOpaque = false
            layer.compositingFilter = "multiply"
        }
        view.delegate = self
        window.contentView = view
    }

    func show() {
        // Start invisible and fade in after the first frame, so the full-screen window never flashes white.
        window.alphaValue = 0
        window.orderFrontRegardless()
        view.needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.window.alphaValue = 1 }
    }

    func move(to screen: NSScreen) {
        window.setFrame(screen.frame, display: true)
    }

    func close() { window.close() }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        view.clearColor = MTLClearColor(red: value, green: value, blue: value, alpha: 1)
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)
        else { return }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
