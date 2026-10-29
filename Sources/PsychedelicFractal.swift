import AppKit

/// Winamp / Windows Media Player-era psychedelia: a banded Julia set that breathes with the
/// music, with glowing oscilloscope lines, a waveform ring and spectrum rays on top.
final class PsychedelicFractal: Visualizer {
    private static let width = 256          // fractal resolution; it's scaled up, which suits the look
    private static let maxIterations = 56

    private var height = 0
    private var pixels: UnsafeMutablePointer<UInt32>?
    private var bitmap: CGContext?
    private let palette: UnsafeMutablePointer<UInt32>
    private var vignette: UnsafeMutablePointer<Float>?  // per-pixel edge darkening, baked into the bitmap

    private var features = AudioFeatures()
    private var time: Float = 0
    private var orbit: Float = 0    // where the Julia parameter sits on its circle
    private var spin: Float = 0     // view rotation
    private var hue: Float = 0      // palette and line colour cycling
    private var zoom: Float = 1.3
    private var flash: Float = 0

    init() {
        palette = .allocate(capacity: 256)
        for index in 0..<256 {
            // Rainbow with a few dark bands, which gives the classic banded look.
            let t = Float(index) / 256
            let banding = 0.4 + 0.6 * (0.5 + 0.5 * sin(2 * .pi * t * 4))
            func channel(_ shift: Float) -> UInt32 {
                let value = pow((0.5 + 0.5 * cos(2 * .pi * (t + shift))) * banding, 1.2)
                return UInt32(min(max(value, 0), 1) * 255)
            }
            palette[index] = channel(0) | channel(0.33) << 8 | channel(0.67) << 16 | 0xFF << 24
        }
    }

    deinit {
        palette.deallocate()
        pixels?.deallocate()
        vignette?.deallocate()
    }

    func update(features: AudioFeatures, dt: Double, size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        let dt = Float(dt)
        self.features = features
        resizeBitmap(for: size)

        time += dt
        flash = max(features.beatPulse, flash - dt * 3)
        orbit += dt * (0.22 + features.level * 1.1 + features.bass * 0.9)
        if features.beat { orbit += 0.3 }
        spin += dt * (0.05 + features.bass * 0.12)
        hue += dt * (0.025 + features.treble * 0.3)
        let targetZoom = 1.25 + features.beatPulse * 0.45 + features.bass * 0.3
        zoom += (targetZoom - zoom) * min(1, dt * 9)
        renderFractal()
    }

    /// Full resolution in a normal window; capped near a million pixels so full screen stays smooth.
    func pixelScale(for size: CGSize) -> CGFloat? {
        min(1, (1_000_000 / max(size.width * size.height, 1)).squareRoot())
    }

    func draw(in ctx: CGContext, size: CGSize) {
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        if let image = bitmap?.makeImage() {
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(origin: .zero, size: size))
        }

        // Everything below glows additively, like phosphor.
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let unit = min(size.width, size.height) / 600
        drawScope(ctx, size: size, unit: unit)
        drawRingAndRays(ctx, size: size, unit: unit)
        ctx.restoreGState()
    }

    // MARK: Fractal

    private func resizeBitmap(for size: CGSize) {
        let wanted = min(512, max(48, Int((Float(Self.width) * Float(size.height / size.width)).rounded())))
        guard wanted != height || pixels == nil else { return }
        pixels?.deallocate()
        vignette?.deallocate()
        height = wanted
        let buffer = UnsafeMutablePointer<UInt32>.allocate(capacity: Self.width * height)
        buffer.initialize(repeating: 0xFF00_0000, count: Self.width * height)
        pixels = buffer

        let table = UnsafeMutablePointer<Float>.allocate(capacity: Self.width * height)
        for row in 0..<height {
            for column in 0..<Self.width {
                let x = (Float(column) - Float(Self.width) / 2) / (Float(Self.width) / 2)
                let y = (Float(row) - Float(height) / 2) / (Float(height) / 2)
                let t = min(max((hypot(x, y) / 1.41 - 0.35) / 0.65, 0), 1)
                table[row * Self.width + column] = 1 - 0.65 * t * t * (3 - 2 * t)
            }
        }
        vignette = table
        bitmap = CGContext(data: buffer, width: Self.width, height: height, bitsPerComponent: 8,
                           bytesPerRow: Self.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// Julia set whose parameter circles the edge of the Mandelbrot set's main body.
    private func renderFractal() {
        guard let pixels, let vignette else { return }
        let flashBoost = flash * 70
        /// Applies the baked-in edge darkening and the beat flash to one packed pixel.
        func shade(_ color: UInt32, _ factor: Float) -> UInt32 {
            func channel(_ shift: UInt32) -> UInt32 {
                UInt32(min(Float((color >> shift) & 255) * factor + flashBoost, 255))
            }
            return channel(0) | channel(8) << 8 | channel(16) << 16 | 0xFF << 24
        }
        let width = Self.width, height = self.height, maxIterations = Self.maxIterations
        let radius = 0.745 + 0.05 * sin(time * 0.37) + 0.03 * features.level
        let cr = radius * cos(orbit), ci = radius * sin(orbit)
        let unit = 1.5 / zoom
        let cosine = cos(spin), sine = sin(spin)
        let paletteShift = hue
        let palette = self.palette
        let inside = UInt32(0xFF00_0000 | (UInt32(10 + features.bass * 60) << 16) | UInt32(6 + features.level * 20))

        DispatchQueue.concurrentPerform(iterations: height) { row in
            let rowPixels = pixels + row * width
            let imagStart = (Float(row) - Float(height) / 2) / (Float(height) / 2) * unit
            for column in 0..<width {
                let realStart = (Float(column) - Float(width) / 2) / (Float(height) / 2) * unit
                var zr = realStart * cosine - imagStart * sine
                var zi = realStart * sine + imagStart * cosine
                var zr2 = zr * zr, zi2 = zi * zi
                var count = 0
                while count < maxIterations, zr2 + zi2 <= 256 {
                    zi = 2 * zr * zi + ci
                    zr = zr2 - zi2 + cr
                    zr2 = zr * zr
                    zi2 = zi * zi
                    count += 1
                }
                let factor = vignette[row * width + column]
                if count == maxIterations {
                    rowPixels[column] = shade(inside, factor)
                } else {
                    let smooth = Float(count) + 1 - log2(0.5 * log2(zr2 + zi2))
                    let phase = smooth * 0.045 + paletteShift
                    rowPixels[column] = shade(palette[Int((phase - phase.rounded(.down)) * 256) & 255], factor)
                }
            }
        }
    }

    // MARK: Lines

    private func drawScope(_ ctx: CGContext, size: CGSize, unit: CGFloat) {
        let wave = features.waveform
        let amplitude = size.height * 0.26 * CGFloat(0.55 + features.bass * 0.8 + features.beatPulse * 0.25)
        for (shift, mirror) in [(0.5, CGFloat(1)), (0.62, CGFloat(-1))] as [(Float, CGFloat)] {
            let path = CGMutablePath()
            for (index, value) in wave.enumerated() {
                let point = CGPoint(x: size.width * CGFloat(index) / CGFloat(wave.count - 1),
                                    y: size.height / 2 + CGFloat(value) * amplitude * mirror)
                index == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            glow(ctx, path, hue: hue + shift, unit: unit)
        }
    }

    private func drawRingAndRays(_ ctx: CGContext, size: CGSize, unit: CGFloat) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let base = min(size.width, size.height) * CGFloat(0.15 + features.bass * 0.05 + features.beatPulse * 0.07)
        let wave = features.waveform

        let ring = CGMutablePath()
        for index in 0...wave.count {
            let value = CGFloat(wave[index % wave.count])
            let angle = 2 * CGFloat.pi * CGFloat(index) / CGFloat(wave.count) + CGFloat(spin)
            let radius = base * (1 + value * 0.45)
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            index == 0 ? ring.move(to: point) : ring.addLine(to: point)
        }
        glow(ctx, ring, hue: hue + 0.25, unit: unit)

        // Spectrum rays, mirrored left/right so the burst is symmetrical.
        let bands = features.bands
        let rays = bands.count * 2
        let reach = min(size.width, size.height) * CGFloat(0.3 + features.beatPulse * 0.1)
        for index in 0..<rays {
            let band = index < bands.count ? index : rays - 1 - index
            let angle = 2 * CGFloat.pi * CGFloat(index) / CGFloat(rays) + CGFloat(spin) * 2
            let inner = base * 1.35
            let outer = inner + CGFloat(bands[band]) * reach
            let path = CGMutablePath()
            path.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
            path.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
            let rayHue = hue + 0.1 + Float(band) / Float(bands.count) * 0.55
            ctx.addPath(path)
            ctx.setStrokeColor(color(rayHue, 0.8, 1, 0.16)); ctx.setLineWidth(7 * unit); ctx.strokePath()
            ctx.addPath(path)
            ctx.setStrokeColor(color(rayHue, 0.45, 1, 0.9)); ctx.setLineWidth(2 * unit); ctx.strokePath()
        }
    }

    /// Three passes (wide dim, medium, thin bright) fake a bloom around a line.
    private func glow(_ ctx: CGContext, _ path: CGPath, hue: Float, unit: CGFloat) {
        for (width, saturation, alpha) in [(11, 0.9, 0.10), (5, 0.85, 0.28), (2.2, 0.55, 0.95)] as [(CGFloat, CGFloat, CGFloat)] {
            ctx.addPath(path)
            ctx.setStrokeColor(color(hue, saturation, 1, alpha))
            ctx.setLineWidth(width * unit)
            ctx.strokePath()
        }
    }

    private func color(_ hue: Float, _ saturation: CGFloat, _ brightness: CGFloat, _ alpha: CGFloat) -> CGColor {
        NSColor(hue: CGFloat(hue - hue.rounded(.down)), saturation: saturation, brightness: brightness, alpha: alpha).cgColor
    }
}
