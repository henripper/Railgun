import AppKit

/// Retro pixel-art Earth spinning in a dithered night sky, with satellites on inclined orbits.
/// The whole scene is drawn into a tiny bitmap (about 120 pixels tall) that the window scales up
/// with hard pixel edges. Music drives it: bass swells the globe and its atmosphere, beats send
/// out ping rings, loudness spins it faster, and each satellite follows one frequency band and
/// fires a scan beam at the surface when its band is loud.
final class PixelGlobe: Visualizer {
    var crispScaling: Bool { true }

    private struct Satellite {
        var angle: Float
        let inclination: Float
        let node: Float
        let altitude: Float   // orbit radius, in globe radii
        let direction: Float  // +1 or -1
        let band: Int         // spectrum band that drives it
        var energy: Float = 0
    }

    private struct Star {
        let x: Int, y: Int
        let phase: Float, speed: Float
        let sparkle: Bool
    }

    private var width = 0
    private var height = 0
    private var pixels: UnsafeMutablePointer<UInt32>
    private var bitmap: CGContext?

    private var features = AudioFeatures()
    private var time: Float = 0
    private var spin: Float = 0
    private var pulse: Float = 0
    private var pings: [Float] = []     // ages of the expanding rings, in seconds
    private var stars: [Star] = []
    private var satellites: [Satellite] = [
        Satellite(angle: 0.0, inclination: 0.25, node: 0.0, altitude: 1.32, direction: 1, band: 2),
        Satellite(angle: 2.1, inclination: 1.00, node: 1.0, altitude: 1.42, direction: -1, band: 8),
        Satellite(angle: 4.0, inclination: -0.65, node: 2.2, altitude: 1.50, direction: 1, band: 14),
        Satellite(angle: 1.2, inclination: 1.35, node: 3.1, altitude: 1.38, direction: -1, band: 22),
        Satellite(angle: 5.0, inclination: 0.55, node: 4.2, altitude: 1.58, direction: 1, band: 32),
        Satellite(angle: 3.1, inclination: -1.10, node: 5.3, altitude: 1.64, direction: -1, band: 42),
    ]

    // MARK: Palettes

    /// Packs 0xRRGGBB into the bitmap's byte order.
    private static func rgb(_ hex: UInt32) -> UInt32 {
        ((hex >> 16) & 0xFF) | (hex & 0xFF00) | ((hex & 0xFF) << 16) | 0xFF00_0000
    }
    private static func palette(_ hexes: [UInt32]) -> [UInt32] { hexes.map(rgb) }

    private static let sky = palette([0x04051A, 0x070824, 0x0B0B30, 0x120C3C, 0x1A0F48, 0x221254])
    private static let ocean = palette([0x06123A, 0x0E3A8C, 0x1B62C9, 0x3C8CF0])
    private static let land = palette([0x0A2412, 0x1D5A2A, 0x3C9A3C, 0x78C850])
    private static let desert = palette([0x2A2410, 0x7A6A30, 0xB09A48, 0xD8C46C])
    private static let ice = palette([0x2B3A55, 0x8EA4C4, 0xCFE0F2, 0xFFFFFF])
    private static let kindPalettes = [ocean, land, desert, ice]
    private static let cityLight = rgb(0xFFD84A)
    private static let glint = rgb(0xBFE4FF)
    private static let rimLight = rgb(0x8EC2FF)
    private static let glowNear = rgb(0x3A78E8), glowFar = rgb(0x234CA8)
    private static let ringFront = rgb(0x4A74C4), ringBack = rgb(0x22366A)
    private static let ping = rgb(0x7FD8FF)
    private static let beamBright = rgb(0x39FF14), beamDim = rgb(0x1FA00B)

    private static let bayer: [Float] = [
        0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5,
    ].map { ($0 + 0.5) / 16 }

    // MARK: Earth map

    static let mapWidth = 192, mapHeight = 96
    /// 0 sea, 1 land, 2 desert, 3 ice. Equirectangular; row 0 is the north pole.
    private static let earth: [UInt8] = buildEarth()

    // Rough continent outlines as flat (lon, lat) pairs, good enough at about 2 degrees per cell.
    private static let landOutlines: [[Double]] = [
        // North and Central America
        [-166, 65, -156, 71, -125, 70, -95, 68, -82, 66, -78, 62, -62, 58, -56, 52, -66, 45, -70, 42, -76, 38,
         -81, 31, -80, 25, -83, 29, -90, 30, -97, 27, -97, 22, -92, 18, -88, 21, -87, 16, -83, 10, -79, 9,
         -82, 8, -86, 11, -92, 14, -105, 19, -112, 27, -117, 32, -124, 40, -124, 48, -134, 56, -146, 60,
         -155, 58, -165, 60],
        // South America
        [-79, 9, -72, 12, -62, 10, -52, 5, -50, 0, -44, -2, -35, -6, -39, -14, -41, -22, -48, -26, -53, -34,
         -58, -38, -65, -41, -66, -47, -69, -52, -73, -52, -75, -46, -73, -37, -71, -30, -70, -18, -76, -14,
         -81, -5, -80, 0],
        // Europe and Asia
        [-9, 37, -9, 43, -2, 44, -4, 48, 2, 51, 8, 54, 8, 57, 11, 58, 5, 60, 5, 63, 12, 66, 20, 70, 30, 71,
         40, 67, 44, 68, 60, 70, 70, 73, 80, 73, 100, 77, 112, 74, 130, 72, 140, 72, 160, 70, 180, 68, 172, 62,
         163, 59, 156, 51, 150, 59, 142, 59, 137, 54, 141, 48, 135, 43, 130, 42, 127, 35, 126, 38, 124, 40,
         121, 40, 118, 38, 122, 37, 120, 32, 122, 30, 120, 25, 111, 21, 108, 21, 106, 17, 109, 12, 105, 9,
         99, 10, 100, 6, 104, 1, 101, 3, 98, 8, 98, 16, 94, 19, 91, 22, 88, 22, 80, 15, 77, 8, 73, 17, 72, 21,
         67, 24, 62, 25, 57, 26, 56, 27, 50, 30, 48, 29, 51, 25, 56, 24, 59, 22, 55, 17, 52, 16, 43, 13, 39, 21,
         35, 28, 35, 35, 30, 36, 27, 37, 26, 40, 23, 40, 24, 37, 22, 37, 20, 40, 19, 42, 14, 45, 12, 44, 18, 40,
         16, 38, 12, 42, 9, 44, 3, 43, 0, 39, -5, 36],
        // Africa
        [-17, 21, -16, 28, -10, 30, -6, 36, 10, 37, 11, 33, 20, 31, 32, 31, 34, 28, 38, 20, 43, 12, 51, 12,
         46, 2, 41, -4, 40, -15, 35, -24, 33, -28, 27, -34, 20, -35, 17, -30, 12, -18, 13, -8, 9, -1, 9, 4,
         5, 5, -4, 5, -9, 5, -15, 11, -17, 15],
        // Australia
        [114, -22, 122, -18, 130, -12, 137, -12, 142, -11, 146, -19, 153, -26, 151, -34, 145, -39, 138, -35,
         131, -31, 124, -33, 115, -34],
        // British Isles, Iceland, Japan, Cuba
        [-5, 50, 1, 51, 2, 53, -2, 57, -5, 58, -6, 55, -3, 54],
        [-10, 52, -6, 52, -6, 55, -10, 54],
        [-24, 64, -14, 64, -15, 66, -22, 66],
        [130, 32, 135, 34, 140, 36, 142, 40, 141, 44, 145, 44, 140, 41, 135, 36, 131, 34],
        [-84, 22, -80, 23, -74, 20, -78, 20],
        // Indonesia, Philippines, Madagascar, New Zealand
        [95, 5, 98, 4, 106, -5, 104, -6, 100, -2],
        [109, 1, 113, 4, 119, 6, 118, 0, 116, -4, 110, -3],
        [105, -6, 114, -7, 114, -8, 106, -7],
        [131, -1, 141, -3, 150, -10, 142, -9, 138, -8, 132, -4],
        [120, 18, 122, 18, 125, 10, 122, 8, 120, 14],
        [44, -25, 48, -25, 50, -15, 48, -13, 44, -17],
        [172, -35, 178, -38, 175, -41, 171, -45, 167, -46, 172, -41],
    ]
    private static let iceOutlines: [[Double]] = [
        // Greenland
        [-73, 78, -60, 82, -30, 83, -20, 76, -22, 70, -40, 64, -48, 61, -54, 67, -60, 76],
    ]
    private static let seaOutlines: [[Double]] = [
        [-95, 60, -94, 52, -85, 53, -80, 52, -79, 58, -86, 64, -92, 64],   // Hudson Bay
        [28, 42, 41, 42, 41, 45, 35, 46, 30, 46, 28, 44],                  // Black Sea
        [47, 37, 54, 37, 54, 42, 51, 47, 47, 45, 49, 41],                  // Caspian Sea
    ]
    /// lonMin, lonMax, latMin, latMax
    private static let desertBoxes: [[Double]] = [
        [-15, 32, 14, 30], [38, 56, 17, 29], [88, 112, 38, 46], [118, 142, -30, -20], [15, 25, -26, -18],
    ]

    private static func contains(_ outline: [Double], lon: Double, lat: Double) -> Bool {
        var inside = false
        var previous = outline.count - 2
        var index = 0
        while index < outline.count {
            let xi = outline[index], yi = outline[index + 1]
            let xj = outline[previous], yj = outline[previous + 1]
            if (yi > lat) != (yj > lat), lon < (xj - xi) * (lat - yi) / (yj - yi) + xi { inside.toggle() }
            previous = index
            index += 2
        }
        return inside
    }

    private static func hash(_ x: Int, _ y: Int) -> Float {
        var value = UInt32(truncatingIfNeeded: x) &* 374_761_393 &+ UInt32(truncatingIfNeeded: y) &* 668_265_263
        value = (value ^ (value >> 13)) &* 1_274_126_177
        return Float(value ^ (value >> 16)) / Float(UInt32.max)
    }

    private static func buildEarth() -> [UInt8] {
        var map = [UInt8](repeating: 0, count: mapWidth * mapHeight)
        for row in 0..<mapHeight {
            for column in 0..<mapWidth {
                let lon = (Double(column) + 0.5) / Double(mapWidth) * 360 - 180
                let lat = 90 - (Double(row) + 0.5) / Double(mapHeight) * 180
                var kind: UInt8 = 0
                if landOutlines.contains(where: { contains($0, lon: lon, lat: lat) }) { kind = 1 }
                if kind == 1, seaOutlines.contains(where: { contains($0, lon: lon, lat: lat) }) { kind = 0 }
                if kind == 1,
                   desertBoxes.contains(where: { lon >= $0[0] && lon <= $0[1] && lat >= $0[2] && lat <= $0[3] }),
                   hash(column, row) > 0.3 {
                    kind = 2
                }
                if iceOutlines.contains(where: { contains($0, lon: lon, lat: lat) }) { kind = 3 }
                if lat < -70 + 4 * sin(lon * .pi / 60) || lat > 83 { kind = 3 }
                map[row * mapWidth + column] = kind
            }
        }
        return map
    }

    // MARK: Lifecycle

    init() {
        pixels = .allocate(capacity: 1)
    }

    deinit {
        pixels.deallocate()
    }

    /// About 120 art pixels tall, each a whole number of points so the scaling stays even.
    private func artPixelSize(for size: CGSize) -> CGFloat {
        max(3, (size.height / 120).rounded())
    }

    func pixelScale(for size: CGSize) -> CGFloat? { 1 / artPixelSize(for: size) }

    func update(features: AudioFeatures, dt: Double, size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        resize(for: size)
        let dt = Float(dt)
        self.features = features
        time += dt
        spin += dt * (0.22 + features.level * 0.9 + features.bass * 0.5)
        pulse = max(features.beatPulse, pulse - dt * 4)
        if features.beat { pings.append(0) }
        pings = pings.map { $0 + dt }.filter { $0 < 0.9 }

        for index in satellites.indices {
            let target = features.bands[satellites[index].band]
            satellites[index].energy += (target - satellites[index].energy) * min(1, dt * 10)
            let base = 0.9 / pow(satellites[index].altitude, 1.5)
            satellites[index].angle += satellites[index].direction * dt * (base + satellites[index].energy * 1.4)
            if features.beat { satellites[index].angle += satellites[index].direction * 0.1 }
        }
        render()
    }

    func draw(in ctx: CGContext, size: CGSize) {
        guard let image = bitmap?.makeImage() else { return }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
    }

    private func resize(for size: CGSize) {
        let scale = 1 / artPixelSize(for: size)
        let newWidth = max(32, Int((size.width * scale).rounded()))
        let newHeight = max(32, Int((size.height * scale).rounded()))
        guard newWidth != width || newHeight != height else { return }
        width = newWidth
        height = newHeight
        pixels.deallocate()
        pixels = .allocate(capacity: width * height)
        pixels.initialize(repeating: Self.sky[0], count: width * height)
        bitmap = CGContext(data: pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                           space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)

        var generator = SeededGenerator(seed: 0xE4271)
        stars = (0..<(width * height / 170)).map { _ in
            Star(x: Int.random(in: 0..<width, using: &generator), y: Int.random(in: 0..<height, using: &generator),
                 phase: Float.random(in: 0..<6.28, using: &generator), speed: Float.random(in: 0.6..<2.2, using: &generator),
                 sparkle: Int.random(in: 0..<12, using: &generator) == 0)
        }
    }

    // MARK: Drawing

    @inline(__always) private func plot(_ x: Int, _ y: Int, _ color: UInt32) {
        if x >= 0, x < width, y >= 0, y < height { pixels[y * width + x] = color }
    }

    @inline(__always) private func bayer(_ x: Int, _ y: Int) -> Float { Self.bayer[(y & 3) * 4 + (x & 3)] }

    private func dimmed(_ color: UInt32, _ factor: Float) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 { UInt32(Float((color >> shift) & 0xFF) * factor) }
        return channel(0) | channel(8) << 8 | channel(16) << 16 | 0xFF00_0000
    }

    /// Satellite position in globe radii: x right, y up, z towards the viewer.
    private func orbitPoint(_ satellite: Satellite, angle: Float) -> (x: Float, y: Float, z: Float) {
        let x = cos(angle), z = sin(angle)
        let inclinedY = -z * sin(satellite.inclination)
        let inclinedZ = z * cos(satellite.inclination)
        let nodeX = x * cos(satellite.node) + inclinedZ * sin(satellite.node)
        let nodeZ = -x * sin(satellite.node) + inclinedZ * cos(satellite.node)
        return (nodeX * satellite.altitude, inclinedY * satellite.altitude, nodeZ * satellite.altitude)
    }

    private func render() {
        let skyCount = Self.sky.count
        for y in 0..<height {
            let value = Float(y) / Float(height - 1) * Float(skyCount - 1)
            let base = Int(value), fraction = value - Float(base)
            for x in 0..<width {
                let step = fraction > bayer(x, y) ? min(base + 1, skyCount - 1) : base
                pixels[y * width + x] = Self.sky[step]
            }
        }
        drawStars()

        let cx = Float(width) / 2, cy = Float(height) / 2
        let radius = Float(height) * 0.30 * (1 + 0.035 * pulse + 0.02 * features.bass)

        // Behind the globe: far halves of the orbits.
        drawOrbits(cx: cx, cy: cy, radius: radius, front: false)
        for satellite in satellites {
            let p = orbitPoint(satellite, angle: satellite.angle)
            if p.z < 0 { drawSatellite(satellite, p, cx: cx, cy: cy, radius: radius, behind: true) }
        }

        drawGlobe(cx: cx, cy: cy, radius: radius)

        // In front: near halves, scan beams, satellites, then the ping rings.
        drawOrbits(cx: cx, cy: cy, radius: radius, front: true)
        for satellite in satellites {
            let p = orbitPoint(satellite, angle: satellite.angle)
            guard p.z >= 0 else { continue }
            if satellite.energy > 0.35, p.x * p.x + p.y * p.y < satellite.altitude * satellite.altitude * 0.98 {
                drawBeam(satellite, p, cx: cx, cy: cy, radius: radius)
            }
        }
        for satellite in satellites {
            let p = orbitPoint(satellite, angle: satellite.angle)
            if p.z >= 0 { drawSatellite(satellite, p, cx: cx, cy: cy, radius: radius, behind: false) }
        }
        drawPings(cx: cx, cy: cy, radius: radius)
    }

    private func drawStars() {
        let rate = 1 + features.treble * 5
        for star in stars {
            let brightness = 0.5 + 0.5 * sin(time * star.speed * rate + star.phase)
            let color = brightness > 0.85 ? Self.rgb(0xFFFFFF) : brightness > 0.5 ? Self.rgb(0x8EA4D8) : Self.rgb(0x3A4A7A)
            plot(star.x, star.y, color)
            if star.sparkle, brightness > 0.92 {
                let arm = Self.rgb(0xB8C8F0)
                plot(star.x - 1, star.y, arm); plot(star.x + 1, star.y, arm)
                plot(star.x, star.y - 1, arm); plot(star.x, star.y + 1, arm)
            }
        }
    }

    private func drawGlobe(cx: Float, cy: Float, radius: Float) {
        let tilt: Float = 0.41, pitch: Float = 0.32
        let ct = cos(tilt), st = sin(tilt), cp = cos(pitch), sp = sin(pitch)
        let lightX: Float = -0.55, lightY: Float = 0.45, lightZ: Float = 0.70
        let glow = 2 + features.bass * 5
        let extent = Int(radius + glow) + 2
        let minX = max(0, Int(cx) - extent), maxX = min(width - 1, Int(cx) + extent)
        let minY = max(0, Int(cy) - extent), maxY = min(height - 1, Int(cy) + extent)
        let earth = Self.earth, mapW = Self.mapWidth, mapH = Self.mapHeight
        let rimSquared = (1 - 1.3 / radius) * (1 - 1.3 / radius)

        for py in minY...maxY {
            for px in minX...maxX {
                let dx = (Float(px) + 0.5 - cx) / radius
                let dy = (cy - Float(py) - 0.5) / radius
                let d2 = dx * dx + dy * dy
                let dither = bayer(px, py)

                if d2 > 1 {
                    // Atmosphere: dithered halo, stronger on the lit side and with the bass.
                    let distance = sqrt(d2)
                    let falloff = 1 - (distance - 1) * radius / glow
                    guard falloff > 0 else { continue }
                    let lit = 0.3 + 0.7 * max(0, (dx * lightX + dy * lightY) / distance)
                    if falloff * lit > dither { plot(px, py, falloff > 0.55 ? Self.glowNear : Self.glowFar) }
                    continue
                }

                let dz = sqrt(1 - d2)
                // Undo the view pitch and the axial tilt to find the point on the planet.
                let y1 = dy * cp + dz * sp
                let z1 = -dy * sp + dz * cp
                let x2 = dx * ct + y1 * st
                let y2 = -dx * st + y1 * ct
                let lon = atan2(x2, z1) - spin
                let lat = asin(max(-1, min(1, y2)))
                var u = (lon + .pi) / (2 * .pi)
                u -= floor(u)
                let v = (.pi / 2 - lat) / .pi
                let mapX = min(mapW - 1, Int(u * Float(mapW))), mapY = min(mapH - 1, max(0, Int(v * Float(mapH))))
                let kind = earth[mapY * mapW + mapX]

                // Four-step cel shading with ordered dithering between the steps.
                let diff = dx * lightX + dy * lightY + dz * lightZ
                let shade = diff * 0.95 + (dither - 0.5) * 0.3
                let level = shade > 0.62 ? 3 : shade > 0.34 ? 2 : shade > 0.08 ? 1 : 0
                var color = Self.kindPalettes[Int(kind)][level]

                if level == 0, diff < 0.02, kind == 1 || kind == 2,
                   Self.hash(mapX, mapY) > 0.86, abs(lat) < 1.1, (Int(time * 2) + mapX * 3 + mapY) % 5 != 0 {
                    color = Self.cityLight
                } else if level == 3, kind == 0, diff > 0.93 {
                    color = Self.glint
                } else if d2 > rimSquared, diff > 0 {
                    color = Self.rimLight
                }
                pixels[py * width + px] = color
            }
        }
    }

    private func drawOrbits(cx: Float, cy: Float, radius: Float, front: Bool) {
        for satellite in satellites {
            for step in stride(from: 0, to: 144, by: 2) {
                let p = orbitPoint(satellite, angle: Float(step) / 144 * 2 * .pi)
                let outside = p.x * p.x + p.y * p.y > 1
                if front ? p.z >= 0 : (p.z < 0 && outside) {
                    plot(Int(cx + p.x * radius), Int(cy - p.y * radius), front ? Self.ringFront : Self.ringBack)
                }
            }
        }
    }

    private func drawSatellite(_ satellite: Satellite, _ p: (x: Float, y: Float, z: Float),
                               cx: Float, cy: Float, radius: Float, behind: Bool) {
        let x = Int(cx + p.x * radius), y = Int(cy - p.y * radius)
        let factor: Float = behind ? 0.55 : 1
        let hot = satellite.energy > 0.5
        let body = dimmed(Self.rgb(0xC8CCD4), factor), core = dimmed(Self.rgb(0x8890A0), factor)
        let panel = dimmed(Self.rgb(hot ? 0x6FA0FF : 0x2F6BFF), factor)
        let panelLight = dimmed(Self.rgb(hot ? 0xDFF0FF : 0x7FB2FF), factor)

        for dy in -1...1 { for dx in -1...1 { plot(x + dx, y + dy, body) } }
        plot(x, y, core)
        plot(x - 2, y, core); plot(x + 2, y, core)
        for column in 3...6 {
            let color = column % 2 == 0 ? panelLight : panel
            for row in -1...0 { plot(x - column, y + row, color); plot(x + column, y + row, color) }
        }
        plot(x, y - 2, dimmed(Self.rgb(0xE0E0E0), factor))
        let blink = (Int(time * 2) + satellite.band) % 2 == 0
        plot(x, y - 3, blink ? dimmed(Self.beamBright, factor) : dimmed(Self.rgb(0xFF3B3B), factor))
    }

    /// A dotted neon scan line from a satellite down to the surface point beneath it.
    private func drawBeam(_ satellite: Satellite, _ p: (x: Float, y: Float, z: Float), cx: Float, cy: Float, radius: Float) {
        let length = sqrt(p.x * p.x + p.y * p.y + p.z * p.z)
        let startX = Int(cx + p.x * radius), startY = Int(cy - p.y * radius)
        let endX = Int(cx + p.x / length * radius), endY = Int(cy - p.y / length * radius)
        let steps = max(abs(endX - startX), abs(endY - startY))
        guard steps > 2 else { return }
        let phase = Int(time * 18)
        let color = satellite.energy > 0.7 ? Self.beamBright : Self.beamDim
        for index in 0...steps where (index + phase) % 3 != 0 {
            plot(startX + (endX - startX) * index / steps, startY + (endY - startY) * index / steps, color)
        }
        // A small target blip where the beam lands.
        let blip = Int(time * 6) % 2 == 0
        plot(endX, endY, Self.beamBright)
        if blip { plot(endX - 1, endY, color); plot(endX + 1, endY, color); plot(endX, endY - 1, color); plot(endX, endY + 1, color) }
    }

    private func drawPings(cx: Float, cy: Float, radius: Float) {
        for age in pings {
            let ringRadius = radius * (1.08 + age * 1.6)
            let strength = 1 - age / 0.9
            let steps = Int(ringRadius * 6.5)
            for step in 0..<steps {
                let angle = Float(step) / Float(steps) * 2 * .pi
                let x = Int(cx + cos(angle) * ringRadius), y = Int(cy - sin(angle) * ringRadius)
                if strength > bayer(x, y) { plot(x, y, Self.ping) }
            }
        }
    }
}

/// Small deterministic generator so the star field is the same every time.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
