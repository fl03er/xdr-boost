import AppKit
import MetalKit

/// A tiny always-on-top window in the corner of a screen that shows EDR content (a value above 1.0).
/// While it is on screen macOS keeps that display in EDR mode, which opens up the headroom the gamma boost uses.
final class EDROverlay: NSObject, MTKViewDelegate {
    private let window: NSWindow
    private let view: MTKView
    private let queue: MTLCommandQueue
    var value: Double = 1.0 { didSet { if value != oldValue { view.needsDisplay = true } } }

    init?(screen: NSScreen) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.queue = queue
        // One point is enough; it sits in the bottom-left corner where it is hard to notice.
        let frame = NSRect(origin: screen.frame.origin, size: NSSize(width: 1, height: 1))
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.sharingType = .none  // keep it out of screenshots and recordings
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        view = MTKView(frame: NSRect(origin: .zero, size: frame.size), device: device)
        view.colorPixelFormat = .rgba16Float
        view.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        super.init()
        (view.layer as? CAMetalLayer)?.wantsExtendedDynamicRangeContent = true
        view.delegate = self
        window.contentView = view
    }

    func show() {
        window.orderFrontRegardless()
        view.needsDisplay = true
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
