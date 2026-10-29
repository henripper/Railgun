import AppKit
import QuartzCore

/// One visual effect. Add a new effect by conforming to this and adding a case to `VisualEffectKind`.
protocol Visualizer: AnyObject {
    func update(features: AudioFeatures, dt: Double, size: CGSize)
    func draw(in ctx: CGContext, size: CGSize)
}

enum VisualEffectKind: String, CaseIterable, Identifiable {
    case matrixRain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .matrixRain: "Matrix Rain"
        }
    }

    func make() -> Visualizer {
        switch self {
        case .matrixRain: MatrixRain()
        }
    }
}

/// Drives the analyzer and the current effect from the display's refresh.
final class VisualsView: NSView {
    var effect: Visualizer
    let analyzer: AudioAnalyzer
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    init(effect: Visualizer, analyzer: AudioAnalyzer) {
        self.effect = effect
        self.analyzer = analyzer
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
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
        needsDisplay = true
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
