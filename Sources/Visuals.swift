import AppKit
import QuartzCore

/// One visual effect. Add a new effect by conforming to this and adding a case to `VisualEffectKind`.
protocol Visualizer: AnyObject {
    func update(features: AudioFeatures, dt: Double, size: CGSize)
    func draw(in ctx: CGContext, size: CGSize)
    /// Pixels per point to render at, or nil for the screen's full resolution. Heavy effects
    /// return less than 1 on big windows; the GPU then stretches the result to fit.
    func pixelScale(for size: CGSize) -> CGFloat?
}

extension Visualizer {
    func pixelScale(for size: CGSize) -> CGFloat? { nil }
}

enum VisualEffectKind: String, CaseIterable, Identifiable {
    case matrixRain
    case psychedelic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .matrixRain: "Matrix Rain"
        case .psychedelic: "Psychedelic Fractal"
        }
    }

    func make() -> Visualizer {
        switch self {
        case .matrixRain: MatrixRain()
        case .psychedelic: PsychedelicFractal()
        }
    }
}

/// Drives the analyzer and the current effect from the display's refresh.
final class VisualsView: NSView {
    var effect: Visualizer {
        didSet {
            offscreen = nil
            layer?.contents = nil
            needsDisplay = true
        }
    }
    let analyzer: AudioAnalyzer
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var offscreen: CGContext?

    init(effect: Visualizer, analyzer: AudioAnalyzer) {
        self.effect = effect
        self.analyzer = analyzer
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.contentsGravity = .resize
        layer?.magnificationFilter = .linear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        guard window != nil else { return }
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let dt = lastTimestamp == 0 ? 1.0 / 60 : min(0.1, now - lastTimestamp)
        lastTimestamp = now
        analyzer.update(dt: dt)
        effect.update(features: analyzer.features, dt: dt, size: bounds.size)
        if let scale = effect.pixelScale(for: bounds.size) {
            renderScaled(scale)
        } else {
            needsDisplay = true
        }
    }

    /// Draws into a smaller bitmap and hands it to the layer, so Core Animation does the upscaling.
    private func renderScaled(_ scale: CGFloat) {
        let pixels = CGSize(width: max(1, (bounds.width * scale).rounded()),
                            height: max(1, (bounds.height * scale).rounded()))
        if offscreen?.width != Int(pixels.width) || offscreen?.height != Int(pixels.height) {
            offscreen = CGContext(data: nil, width: Int(pixels.width), height: Int(pixels.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        guard let ctx = offscreen else { return }
        ctx.saveGState()
        ctx.scaleBy(x: pixels.width / bounds.width, y: pixels.height / bounds.height)
        effect.draw(in: ctx, size: bounds.size)
        ctx.restoreGState()
        layer?.contents = ctx.makeImage()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        effect.draw(in: ctx, size: bounds.size)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.toggleFullScreen(nil) }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, window?.styleMask.contains(.fullScreen) == true {  // Esc
            window?.toggleFullScreen(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}

@MainActor
final class VisualsWindowController: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?
    private var window: NSWindow?
    private var view: VisualsView?

    func show(effect: VisualEffectKind, analyzer: AudioAnalyzer) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let view = VisualsView(effect: effect.make(), analyzer: analyzer)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Railgun Visuals"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .black
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.delegate = self
        window.setFrameAutosaveName("RailgunVisuals")
        if !window.setFrameUsingName("RailgunVisuals") { window.center() }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSApp.activate()
        self.window = window
        self.view = view
    }

    func setEffect(_ effect: VisualEffectKind) {
        view?.effect = effect.make()
    }

    func close() {
        guard let window else { return }
        window.delegate = nil
        teardown()
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        teardown()
        onClose?()
    }

    private func teardown() {
        view?.stop()
        view = nil
        window = nil
    }
}
