// Draws the Railgun app icon (a stylised sci-fi rail gun with green coil lights) as a 1024px PNG.
// Usage: swift tools/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Work in top-left coordinates.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

func linear(_ rect: CGRect, _ colors: [CGColor], vertical: Bool = true) {
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    let end = vertical ? CGPoint(x: rect.minX, y: rect.maxY) : CGPoint(x: rect.maxX, y: rect.minY)
    ctx.drawLinearGradient(gradient, start: rect.origin, end: end, options: [])
}

func radial(_ center: CGPoint, _ radius: CGFloat, _ colors: [CGColor]) {
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

/// A metal part: gradient fill, dark outline and a light top edge.
func part(_ rect: CGRect, radius: CGFloat = 8, top: UInt32 = 0x4A525C, bottom: UInt32 = 0x14171B) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    linear(rect, [rgb(top), rgb(bottom)])
    ctx.setFillColor(rgb(0x9AA6B2, 0.55))
    ctx.fill(CGRect(x: rect.minX + radius / 2, y: rect.minY + 2, width: rect.width - radius, height: 3))
    ctx.restoreGState()
    ctx.addPath(path)
    ctx.setStrokeColor(rgb(0x050607)); ctx.setLineWidth(3); ctx.strokePath()
}

func glow(_ rect: CGRect, blur: CGFloat = 18, color: UInt32 = 0x3BFF6E) {
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: blur, color: rgb(color))
    ctx.setFillColor(rgb(color))
    ctx.fill(rect)
    ctx.restoreGState()
}

// Background squircle: dark blue haze, like a smoky night set.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.addPath(tilePath); ctx.clip()
linear(tile, [rgb(0x15384C), rgb(0x061722), rgb(0x02080D)])
radial(CGPoint(x: 760, y: 260), 420, [rgb(0x5FB4D2, 0.45), rgb(0x5FB4D2, 0)])
radial(CGPoint(x: 260, y: 820), 380, [rgb(0x1E5A72, 0.35), rgb(0x1E5A72, 0)])
radial(CGPoint(x: 640, y: 540), 260, [rgb(0x3BFF6E, 0.28), rgb(0x3BFF6E, 0)])

// Gun, rotated so the muzzle points up-left.
ctx.saveGState()
ctx.translateBy(x: 512, y: 512)
ctx.rotate(by: -0.14)
ctx.scaleBy(x: 0.9, y: 0.9)
ctx.translateBy(x: -512, y: -540)

// Cables hanging off the back.
ctx.setLineCap(.round)
for (offset, width) in [(0.0, 16.0), (26.0, 12.0)] as [(CGFloat, CGFloat)] {
    ctx.move(to: CGPoint(x: 880, y: 570 + offset))
    ctx.addCurve(to: CGPoint(x: 900 + offset, y: 900), control1: CGPoint(x: 980, y: 620), control2: CGPoint(x: 860, y: 780))
    ctx.setStrokeColor(rgb(0x0A0C0E)); ctx.setLineWidth(width); ctx.strokePath()
}

part(CGRect(x: 280, y: 500, width: 46, height: 140), radius: 10)             // foregrip
part(CGRect(x: 640, y: 590, width: 130, height: 90), radius: 10, top: 0x2C3238) // battery pack
ctx.saveGState()                                                            // pistol grip, raked back
ctx.translateBy(x: 800, y: 600); ctx.rotate(by: 0.18)
part(CGRect(x: -26, y: 0, width: 54, height: 150), radius: 12)
ctx.restoreGState()

part(CGRect(x: 230, y: 428, width: 460, height: 30), radius: 6)               // upper rail
part(CGRect(x: 150, y: 470, width: 560, height: 52), radius: 8)               // main barrel
ctx.setFillColor(rgb(0x07090B))                                             // barrel ribbing
for x in stride(from: 180, through: 410, by: 20) { ctx.fill(CGRect(x: CGFloat(x), y: 476, width: 7, height: 40)) }
part(CGRect(x: 106, y: 452, width: 58, height: 86), radius: 10)               // muzzle block
part(CGRect(x: 78, y: 480, width: 34, height: 28), radius: 5, top: 0x8A949E, bottom: 0x3A4048)

part(CGRect(x: 430, y: 410, width: 210, height: 136), radius: 12, top: 0x2E343B, bottom: 0x0C0E10) // coil housing
for row in 0..<6 { glow(CGRect(x: 452, y: 428 + CGFloat(row) * 19, width: 166, height: 7)) }

part(CGRect(x: 600, y: 392, width: 290, height: 206), radius: 26)             // receiver
part(CGRect(x: 870, y: 430, width: 64, height: 130), radius: 12)             // rear block
for index in 0..<4 { glow(CGRect(x: 742 + CGFloat(index) * 28, y: 416, width: 16, height: 12), blur: 12) }

// The glowing green orb.
let orb = CGPoint(x: 690, y: 520)
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 70, color: rgb(0x3BFF6E))
ctx.setFillColor(rgb(0x1AFF5A))
ctx.fillEllipse(in: CGRect(x: orb.x - 38, y: orb.y - 38, width: 76, height: 76))
ctx.restoreGState()
radial(CGPoint(x: orb.x - 10, y: orb.y - 12), 40, [rgb(0xF4FFF0), rgb(0x7CFF9C), rgb(0x1AFF5A, 0)])
ctx.restoreGState()

// Thin rim so the tile reads on light backgrounds.
ctx.addPath(tilePath)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.08)); ctx.setLineWidth(4); ctx.strokePath()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
