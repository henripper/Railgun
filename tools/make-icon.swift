// Draws the Railgun app icon as a 1024px PNG: a side view of a sci-fi rail gun with a fluted
// black shroud, ribbed coils, a tan frame and a scope/light with a neon green lens.
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

let neon: UInt32 = 0x39FF14
let tanTop: UInt32 = 0xA9A07C, tanBottom: UInt32 = 0x6B654C
let blackTop: UInt32 = 0x3D4146, blackBottom: UInt32 = 0x0B0C0E

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
}

func linear(_ rect: CGRect, _ colors: [CGColor]) {
    ctx.drawLinearGradient(gradient(colors), start: rect.origin, end: CGPoint(x: rect.minX, y: rect.maxY), options: [])
}

func radial(_ center: CGPoint, _ radius: CGFloat, _ colors: [CGColor]) {
    ctx.drawRadialGradient(gradient(colors), startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

/// Any shape: vertical gradient fill, dark outline.
func fill(_ path: CGPath, top: UInt32, bottom: UInt32, outline: CGFloat = 3) {
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    linear(path.boundingBox, [rgb(top), rgb(bottom)])
    ctx.restoreGState()
    ctx.addPath(path)
    ctx.setStrokeColor(rgb(0x050607)); ctx.setLineWidth(outline); ctx.setLineJoin(.round); ctx.strokePath()
}

func block(_ rect: CGRect, radius: CGFloat = 8, top: UInt32, bottom: UInt32) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    fill(path, top: top, bottom: bottom)
    ctx.setFillColor(rgb(0xFFFFFF, 0.22))   // light catching the top edge
    ctx.fill(CGRect(x: rect.minX + radius / 2, y: rect.minY + 2, width: max(rect.width - radius, 0), height: 3))
}

func polygon(_ points: [(CGFloat, CGFloat)], top: UInt32, bottom: UInt32) {
    let path = CGMutablePath()
    path.addLines(between: points.map { CGPoint(x: $0.0, y: $0.1) })
    path.closeSubpath()
    fill(path, top: top, bottom: bottom)
}

func glow(_ rect: CGRect, blur: CGFloat = 14, color: UInt32 = neon) {
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
radial(CGPoint(x: 780, y: 230), 420, [rgb(0x5FB4D2, 0.38), rgb(0x5FB4D2, 0)])
radial(CGPoint(x: 240, y: 800), 380, [rgb(0x1E5A72, 0.35), rgb(0x1E5A72, 0)])
radial(CGPoint(x: 640, y: 520), 330, [rgb(neon, 0.20), rgb(neon, 0)])

// Gun, tilted a little and scaled to sit inside the tile.
ctx.saveGState()
ctx.translateBy(x: 512, y: 510)
ctx.rotate(by: -0.07)
ctx.scaleBy(x: 0.88, y: 0.88)
ctx.translateBy(x: -517, y: -545)

// Cables first, so everything else sits in front of them.
ctx.setLineCap(.round)
func cable(from start: CGPoint, to end: CGPoint, c1: CGPoint, c2: CGPoint, width: CGFloat) {
    ctx.move(to: start); ctx.addCurve(to: end, control1: c1, control2: c2)
    ctx.setStrokeColor(rgb(0x050607)); ctx.setLineWidth(width); ctx.strokePath()
    ctx.move(to: start); ctx.addCurve(to: end, control1: c1, control2: c2)
    ctx.setStrokeColor(rgb(0x30353A)); ctx.setLineWidth(width * 0.3); ctx.strokePath()
}
cable(from: CGPoint(x: 205, y: 585), to: CGPoint(x: 330, y: 775), c1: CGPoint(x: 190, y: 690), c2: CGPoint(x: 260, y: 770), width: 11)
cable(from: CGPoint(x: 222, y: 585), to: CGPoint(x: 342, y: 770), c1: CGPoint(x: 208, y: 685), c2: CGPoint(x: 272, y: 758), width: 11)
cable(from: CGPoint(x: 600, y: 640), to: CGPoint(x: 800, y: 676), c1: CGPoint(x: 660, y: 720), c2: CGPoint(x: 740, y: 726), width: 11)
block(CGRect(x: 322, y: 762, width: 44, height: 34), radius: 6, top: 0x30353A, bottom: 0x0B0C0E)   // connector
ctx.setFillColor(rgb(0xC8CCD0)); ctx.fill(CGRect(x: 336, y: 794, width: 16, height: 10))

// Front grip: tan, leaning back, finger ridges on its face.
polygon([(335, 584), (468, 584), (508, 688), (500, 716), (450, 724), (418, 640), (385, 612)],
        top: tanTop, bottom: tanBottom)
ctx.setStrokeColor(rgb(0x3E3A2A, 0.75)); ctx.setLineWidth(3)
for step in 0..<6 {
    let y = 626 + CGFloat(step) * 15
    ctx.move(to: CGPoint(x: 430 + CGFloat(step) * 5, y: y)); ctx.addLine(to: CGPoint(x: 487 + CGFloat(step) * 2, y: y + 4)); ctx.strokePath()
}

// Fluted black shroud with its front plate.
block(CGRect(x: 118, y: 440, width: 176, height: 142), radius: 12, top: blackTop, bottom: blackBottom)
for index in 0..<5 {
    let slot = CGRect(x: 140 + CGFloat(index) * 30, y: 466, width: 18, height: 96)
    ctx.setFillColor(rgb(0x040506))
    ctx.addPath(CGPath(roundedRect: slot, cornerWidth: 9, cornerHeight: 9, transform: nil)); ctx.fillPath()
    ctx.setFillColor(rgb(0x4A4F55, 0.7))
    ctx.fill(CGRect(x: slot.maxX - 2, y: slot.minY + 8, width: 2, height: slot.height - 16))
}
block(CGRect(x: 286, y: 422, width: 20, height: 186), radius: 5, top: 0x2A2E33, bottom: 0x08090A)

// Two ribbed coils and the aluminium rail rod.
for (index, y) in [440, 478].enumerated() {
    let coil = CGRect(x: 306, y: CGFloat(y), width: 150, height: 38)
    block(coil, radius: 8, top: 0x23272B, bottom: 0x08090A)
    ctx.setFillColor(rgb(0x6C737A, 0.65))
    for x in stride(from: coil.minX + 8 + CGFloat(index) * 4, to: coil.maxX - 6, by: 11) {
        ctx.fill(CGRect(x: x, y: coil.minY + 5, width: 4, height: coil.height - 10))
    }
}
let rod = CGRect(x: 306, y: 520, width: 160, height: 28)
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: rod, cornerWidth: 14, cornerHeight: 14, transform: nil)); ctx.clip()
linear(rod, [rgb(0xF4F8FB), rgb(0xAAB4BD), rgb(0x59616A), rgb(0xBFC8CF)])
ctx.restoreGState()
ctx.addPath(CGPath(roundedRect: rod, cornerWidth: 14, cornerHeight: 14, transform: nil))
ctx.setStrokeColor(rgb(0x050607)); ctx.setLineWidth(3); ctx.strokePath()

// Tan frame under the rod and the end block beside the cartridges.
block(CGRect(x: 296, y: 556, width: 200, height: 36), radius: 8, top: tanTop, bottom: tanBottom)
block(CGRect(x: 452, y: 428, width: 44, height: 164), radius: 8, top: tanTop, bottom: tanBottom)

// Three cartridge blocks with glowing circuit boards, a toothed top and a ribbed magazine below.
for index in 0..<3 {
    let x = 504 + CGFloat(index) * 54
    block(CGRect(x: x, y: 410, width: 50, height: 142), radius: 6, top: 0x30353A, bottom: 0x0A0B0D)
    for y in [436, 496] as [CGFloat] {
        ctx.setFillColor(rgb(0x1E7A2C)); ctx.fill(CGRect(x: x + 9, y: y, width: 32, height: 26))
        ctx.setFillColor(rgb(neon, 0.85)); ctx.fill(CGRect(x: x + 14, y: y + 8, width: 6, height: 6))
        ctx.setFillColor(rgb(0xC9A64A)); ctx.fill(CGRect(x: x + 26, y: y + 6, width: 10, height: 4))
    }
    ctx.setFillColor(rgb(0x0A0B0D))
    for tooth in 0..<3 { ctx.fill(CGRect(x: x + 4 + CGFloat(tooth) * 15, y: 394, width: 10, height: 18)) }
}
for index in 0..<2 {
    let shift = CGFloat(index) * 40
    polygon([(560 + shift, 552), (612 + shift, 552), (640 + shift, 650), (594 + shift, 668)], top: 0x2A2E33, bottom: 0x08090A)
    ctx.setStrokeColor(rgb(0x5C636A, 0.7)); ctx.setLineWidth(3)
    for rib in 0..<5 {
        let y = 574 + CGFloat(rib) * 18
        ctx.move(to: CGPoint(x: 568 + shift + CGFloat(rib) * 6, y: y)); ctx.addLine(to: CGPoint(x: 606 + shift + CGFloat(rib) * 6, y: y)); ctx.strokePath()
    }
}

// Rear grip.
polygon([(770, 552), (872, 552), (888, 650), (862, 690), (814, 696), (794, 632)], top: tanTop, bottom: tanBottom)
ctx.setStrokeColor(rgb(0x3E3A2A, 0.75)); ctx.setLineWidth(3)
for step in 0..<6 {
    let y = 604 + CGFloat(step) * 14
    ctx.move(to: CGPoint(x: 820 + CGFloat(step) * 3, y: y)); ctx.addLine(to: CGPoint(x: 872 + CGFloat(step) * 2, y: y + 3)); ctx.strokePath()
}

// Scope / light body: tan housing, rear knob, dial and controls.
block(CGRect(x: 886, y: 392, width: 48, height: 92), radius: 20, top: 0x2A2E33, bottom: 0x08090A)  // rear knob
block(CGRect(x: 690, y: 378, width: 202, height: 184), radius: 34, top: 0xB5AC86, bottom: 0x6B654C)
block(CGRect(x: 716, y: 362, width: 150, height: 24), radius: 8, top: 0x7E7859, bottom: 0x4E4A38)   // top lip
ctx.setFillColor(rgb(0x050607)); ctx.fillEllipse(in: CGRect(x: 800, y: 412, width: 56, height: 56)); // dial
ctx.setFillColor(rgb(0x3A3F45)); ctx.fillEllipse(in: CGRect(x: 808, y: 420, width: 40, height: 40))
ctx.setStrokeColor(rgb(0x6C737A)); ctx.setLineWidth(3)
for tick in 0..<8 {
    let angle = CGFloat(tick) * .pi / 4
    ctx.move(to: CGPoint(x: 828 + cos(angle) * 12, y: 440 + sin(angle) * 12))
    ctx.addLine(to: CGPoint(x: 828 + cos(angle) * 19, y: 440 + sin(angle) * 19)); ctx.strokePath()
}
ctx.setFillColor(rgb(0x0B0C0E)); ctx.fillEllipse(in: CGRect(x: 828, y: 486, width: 30, height: 30))  // button
block(CGRect(x: 784, y: 524, width: 80, height: 16), radius: 6, top: 0x30353A, bottom: 0x0A0B0D)        // switch

// The lens: a tan collar and bezel, then a glowing neon green disc.
let lens = CGPoint(x: 738, y: 470)
ctx.setFillColor(rgb(0x7E7859)); ctx.fillEllipse(in: CGRect(x: lens.x - 88, y: lens.y - 88, width: 176, height: 176))
ctx.setStrokeColor(rgb(0x050607)); ctx.setLineWidth(3)
ctx.strokeEllipse(in: CGRect(x: lens.x - 88, y: lens.y - 88, width: 176, height: 176))
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 90, color: rgb(neon))
ctx.setFillColor(rgb(0x0A0B0D)); ctx.fillEllipse(in: CGRect(x: lens.x - 76, y: lens.y - 76, width: 152, height: 152))
ctx.restoreGState()
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: lens.x - 66, y: lens.y - 66, width: 132, height: 132)); ctx.clip()
radial(CGPoint(x: lens.x - 14, y: lens.y - 18), 96, [rgb(0xE6FFD8), rgb(neon), rgb(0x0FB500)])
ctx.setStrokeColor(rgb(0xFFFFFF, 0.35)); ctx.setLineWidth(5)
ctx.move(to: CGPoint(x: lens.x - 66, y: lens.y)); ctx.addLine(to: CGPoint(x: lens.x + 66, y: lens.y)); ctx.strokePath()
ctx.move(to: CGPoint(x: lens.x, y: lens.y - 66)); ctx.addLine(to: CGPoint(x: lens.x, y: lens.y + 66)); ctx.strokePath()
ctx.restoreGState()
ctx.setStrokeColor(rgb(0x050607)); ctx.setLineWidth(3)
ctx.strokeEllipse(in: CGRect(x: lens.x - 66, y: lens.y - 66, width: 132, height: 132))
ctx.restoreGState()

// Thin rim so the tile reads on light backgrounds.
ctx.addPath(tilePath)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.08)); ctx.setLineWidth(4); ctx.strokePath()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
