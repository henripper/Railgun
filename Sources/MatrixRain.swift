import AppKit
import CoreText

/// Falling green glyph columns. Beats surge every column and flash the heads; each column
/// is tied to one spectrum band, which sets its brightness and trail length.
final class MatrixRain: Visualizer {
    private struct Column {
        var head: Float      // row of the leading glyph (can be negative while waiting to enter)
        var speed: Float     // rows per second
        var length: Int
        var band: Int
        var glyphs: [CGGlyph]
    }

    private static let levels = 12
    private let font: CTFont
    private let glyphSet: [CGGlyph]
    private let cellWidth: CGFloat
    private let cellHeight: CGFloat
    private var columns: [Column] = []
    private var rows = 0
    private var layoutSize = CGSize.zero
    private var energy: [Float] = []
    private var flash: Float = 0

    // Per-frame scratch, grouped by brightness so each level is a single draw call.
    private var bucketGlyphs = [[CGGlyph]](repeating: [], count: MatrixRain.levels + 1)
    private var bucketPositions = [[CGPoint]](repeating: [], count: MatrixRain.levels + 1)

    init() {
        font = CTFontCreateWithName("HiraginoSans-W5" as CFString, 17, nil)
        let characters = Array("ｦｱｳｴｵｶｷｹｺｻｼｽｾｿﾀﾂﾃﾅﾆﾇﾈﾊﾋﾎﾏﾐﾑﾒﾓﾔﾕﾗﾘﾜ0123456789Z:.=*+-<>¦".utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count)
        glyphSet = glyphs.filter { $0 != 0 }
        cellWidth = 15
        cellHeight = 20
    }

    func update(features: AudioFeatures, dt: Double, size: CGSize) {
        if size != layoutSize { layout(size) }
        let dt = Float(dt)
        flash = max(features.beatPulse, flash - dt * 4)
        let surge = 1 + features.beatPulse * 2.2 + features.bass * 1.2

        for index in columns.indices {
            let bandValue = features.bands[columns[index].band]
            energy[index] += (bandValue - energy[index]) * min(1, dt * 12)
            columns[index].head += columns[index].speed * surge * dt
            if Int(columns[index].head) - columns[index].length > rows { respawn(index, entering: false) }

            // Glyphs flicker; more so on a beat and in loud columns.
            let mutations = features.beat ? 4 : (Float.random(in: 0...1) < 0.25 + energy[index] * 0.5 ? 1 : 0)
            for _ in 0..<mutations { mutate(index) }
        }
        // A beat also wakes up a few waiting columns.
        if features.beat {
            for _ in 0..<max(1, columns.count / 12) {
                let index = Int.random(in: 0..<columns.count)
                if columns[index].head < 0 { columns[index].head = 0 }
            }
        }
    }

    func draw(in ctx: CGContext, size: CGSize) {
        ctx.setFillColor(CGColor(red: 0, green: 0.012, blue: 0.004, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        if flash > 0.01 {
            ctx.setFillColor(CGColor(red: 0.1, green: 1, blue: 0.35, alpha: CGFloat(flash) * 0.07))
            ctx.fill(CGRect(origin: .zero, size: size))
        }

        for level in bucketGlyphs.indices {
            bucketGlyphs[level].removeAll(keepingCapacity: true)
            bucketPositions[level].removeAll(keepingCapacity: true)
        }
        for (index, column) in columns.enumerated() {
            let headRow = Int(column.head)
            let columnEnergy = energy[index]
            let length = max(4, Int(Float(column.length) * (0.55 + columnEnergy * 0.9)))
            let x = CGFloat(index) * cellWidth
            for step in 0..<length {
                let row = headRow - step
                guard row >= 0, row < rows else { continue }
                let fade = 1 - Float(step) / Float(length)
                let brightness = fade * (0.3 + 0.7 * columnEnergy)
                let level = step == 0 ? Self.levels : min(Self.levels - 1, Int(brightness * Float(Self.levels)))
                bucketGlyphs[level].append(column.glyphs[row])
                bucketPositions[level].append(CGPoint(x: x, y: size.height - CGFloat(row + 1) * cellHeight + 4))
            }
        }

        ctx.textMatrix = .identity
        for level in 0...Self.levels where !bucketGlyphs[level].isEmpty {
            if level == Self.levels {
                // Leading glyphs: near-white, whiter on a beat.
                let whiteness = CGFloat(0.65 + flash * 0.35)
                ctx.setFillColor(CGColor(red: whiteness, green: 1, blue: whiteness, alpha: 1))
                ctx.setShadow(offset: .zero, blur: 8, color: CGColor(red: 0.3, green: 1, blue: 0.5, alpha: 0.9))
            } else {
                let alpha = CGFloat(level + 1) / CGFloat(Self.levels)
                ctx.setFillColor(CGColor(red: 0.05, green: 0.55 + 0.45 * alpha, blue: 0.2, alpha: alpha))
                ctx.setShadow(offset: .zero, blur: 0, color: nil)
            }
            CTFontDrawGlyphs(font, bucketGlyphs[level], bucketPositions[level], bucketGlyphs[level].count, ctx)
        }
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
    }

    private func layout(_ size: CGSize) {
        layoutSize = size
        rows = max(1, Int(size.height / cellHeight) + 1)
        let count = max(1, Int(size.width / cellWidth))
        columns = []
        energy = [Float](repeating: 0, count: count)
        for _ in 0..<count {
            columns.append(Column(head: 0, speed: 0, length: 0,
                                  band: Int.random(in: 0..<AudioFeatures.bandCount * 3 / 4),
                                  glyphs: (0..<rows).map { _ in glyphSet.randomElement()! }))
        }
        for index in columns.indices { respawn(index, entering: true) }
    }

    private func respawn(_ index: Int, entering: Bool) {
        columns[index].head = entering ? Float.random(in: -Float(rows)...Float(rows)) : -Float.random(in: 0...Float(rows) * 0.6)
        columns[index].speed = Float.random(in: 7...20)
        columns[index].length = Int.random(in: 8...30)
    }

    private func mutate(_ index: Int) {
        let row = Int.random(in: 0..<rows)
        columns[index].glyphs[row] = glyphSet.randomElement()!
    }
}
