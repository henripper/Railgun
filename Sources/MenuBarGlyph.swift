import AppKit

/// Monochrome rail-gun silhouette for the menu bar (template image, so macOS tints it).
enum MenuBarGlyph {
    static func image(active: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 16), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.translateBy(x: 11, y: 8)
            ctx.rotate(by: -0.14)
            ctx.translateBy(x: -11, y: -8)

            let path = CGMutablePath()
            path.addRect(CGRect(x: 0.5, y: 7.2, width: 1.6, height: 1.6))                       // muzzle tip
            path.addRoundedRect(in: CGRect(x: 2, y: 5.6, width: 2.2, height: 4.6), cornerWidth: 0.6, cornerHeight: 0.6) // muzzle block
            path.addRect(CGRect(x: 4, y: 7, width: 10, height: 2.4))                            // barrel
            path.addRect(CGRect(x: 5.5, y: 5.2, width: 8, height: 1.2))                         // upper rail
            path.addRoundedRect(in: CGRect(x: 9, y: 4.4, width: 4.4, height: 5.8), cornerWidth: 0.6, cornerHeight: 0.6) // coil housing
            path.addRoundedRect(in: CGRect(x: 13, y: 3.8, width: 7.4, height: 6.6), cornerWidth: 1.4, cornerHeight: 1.4) // receiver
            path.addRoundedRect(in: CGRect(x: 6.4, y: 9, width: 1.5, height: 4), cornerWidth: 0.5, cornerHeight: 0.5)   // foregrip
            path.addRoundedRect(in: CGRect(x: 17, y: 9.6, width: 1.9, height: 5), cornerWidth: 0.6, cornerHeight: 0.6)  // grip
            ctx.addPath(path)
            ctx.setFillColor(NSColor.black.withAlphaComponent(active ? 1 : 0.4).cgColor)
            ctx.fillPath()

            // Knock out the coil slits and the orb so they read as "lights".
            ctx.setBlendMode(.clear)
            for row in 0..<3 { ctx.fill(CGRect(x: 9.7, y: 5.3 + CGFloat(row) * 1.6, width: 3, height: 0.7)) }
            ctx.fillEllipse(in: CGRect(x: 14.2, y: 5.6, width: 3, height: 3))
            return true
        }
        image.isTemplate = true
        return image
    }
}
