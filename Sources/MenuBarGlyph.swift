import AppKit

/// Menu-bar rail gun: a light silhouette with a dark outline (readable on light and dark bars)
/// and a neon green scope lens. Not a template image, because a template can't carry colour.
enum MenuBarGlyph {
    static let neon = NSColor(srgbRed: 0x39 / 255, green: 1, blue: 0x14 / 255, alpha: 1)

    static func image(active: Bool) -> NSImage {
        NSImage(size: NSSize(width: 26, height: 16), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setAlpha(active ? 1 : 0.5)
            ctx.setLineJoin(.round)

            let body = CGMutablePath()
            func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat = 0.5) {
                body.addRoundedRect(in: CGRect(x: x, y: y, width: width, height: height), cornerWidth: radius, cornerHeight: radius)
            }
            func polygon(_ points: [(CGFloat, CGFloat)]) {
                body.addLines(between: points.map { CGPoint(x: $0.0, y: $0.1) })
                body.closeSubpath()
            }
            rect(0.4, 4.2, 5.0, 7.2, 1.0)                                              // fluted shroud
            rect(5.6, 4.6, 4.8, 1.7); rect(5.6, 6.5, 4.8, 1.7); rect(5.6, 8.6, 5.0, 1.1, 0.55) // coils and rod
            rect(5.6, 10.0, 5.2, 1.4)                                                  // frame
            polygon([(6.6, 11.2), (10.0, 11.2), (10.8, 15.2), (8.5, 15.4)])            // front grip
            rect(11.0, 3.6, 4.4, 6.4)                                                  // cartridges
            polygon([(11.8, 10), (15, 10), (15.9, 13.2), (13.3, 13.5)])                // magazine
            rect(15.6, 2.8, 8.2, 8.2, 2.0)                                             // scope body
            rect(23.9, 2.2, 1.7, 4.2, 0.8)                                             // rear knob
            polygon([(19.6, 10.8), (23.4, 10.8), (24.0, 14.8), (21.6, 15.4), (20.6, 13)]) // rear grip

            ctx.addPath(body)
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.75).cgColor)
            ctx.setLineWidth(1.3)
            ctx.strokePath()
            ctx.addPath(body)
            ctx.setFillColor(NSColor(white: 0.93, alpha: 1).cgColor)
            ctx.fillPath()

            // Dark details: shroud flutes, cartridge slits, dial and button.
            ctx.setFillColor(NSColor(white: 0.18, alpha: 1).cgColor)
            for x in [1.3, 2.7, 4.1] as [CGFloat] { ctx.fill(CGRect(x: x, y: 5.3, width: 0.8, height: 4.8)) }
            for x in [12.3, 13.7] as [CGFloat] { ctx.fill(CGRect(x: x, y: 4.6, width: 0.5, height: 4.4)) }
            ctx.fillEllipse(in: CGRect(x: 21.2, y: 4.5, width: 1.4, height: 1.4))
            ctx.fillEllipse(in: CGRect(x: 21.9, y: 7.6, width: 1.0, height: 1.0))

            // The lens: dark bezel, then the neon disc with a soft glow.
            let lens = CGPoint(x: 18.6, y: 6.9)
            ctx.setFillColor(NSColor(white: 0.1, alpha: 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: lens.x - 3.1, y: lens.y - 3.1, width: 6.2, height: 6.2))
            ctx.saveGState()
            if active { ctx.setShadow(offset: .zero, blur: 3, color: neon.cgColor) }
            ctx.setFillColor((active ? neon : NSColor(white: 0.6, alpha: 1)).cgColor)
            ctx.fillEllipse(in: CGRect(x: lens.x - 2.5, y: lens.y - 2.5, width: 5.0, height: 5.0))
            ctx.restoreGState()
            if active {
                ctx.setFillColor(NSColor.white.withAlphaComponent(0.7).cgColor)
                ctx.fillEllipse(in: CGRect(x: lens.x - 1.5, y: lens.y - 1.7, width: 1.2, height: 1.2))
            }
            return true
        }
    }
}
