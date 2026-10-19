// Renders the app icon: swift scripts/render-icon.swift <out.png> [size]
import AppKit

let out = CommandLine.arguments[1]
let size = CGFloat(Double(CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "1024")!)
let s = size / 1024

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
ctx.scaleBy(x: s, y: s)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
}
func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
func fill(_ path: CGPath, _ g: CGGradient, from: CGPoint, to: CGPoint) {
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

// macOS icon grid: 824pt squircle-ish tile centred in 1024, with a soft drop shadow.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = rounded(tile, 186)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(tilePath); ctx.setFillColor(color(0x1b1f4b)); ctx.fillPath()
ctx.restoreGState()
fill(tilePath, gradient([color(0x6a5cff), color(0x3346d6), color(0x101a5c)]),
     from: CGPoint(x: 180, y: 924), to: CGPoint(x: 844, y: 100))

// Soft glow behind the monitors.
ctx.saveGState(); ctx.addPath(tilePath); ctx.clip()
ctx.drawRadialGradient(gradient([color(0x9fb4ff, 0.55), color(0x9fb4ff, 0)]),
                       startCenter: CGPoint(x: 512, y: 600), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 600), endRadius: 420, options: [])
ctx.restoreGState()

// Restore arc over the monitors, arrowhead pointing back down: "put back".
ctx.saveGState()
ctx.setLineWidth(30); ctx.setLineCap(.round)
ctx.setStrokeColor(color(0xffffff, 0.55))
let c = CGPoint(x: 512, y: 590), r: CGFloat = 290
let a0: CGFloat = .pi * 0.86, a1: CGFloat = .pi * 0.25
ctx.addArc(center: c, radius: r, startAngle: a0, endAngle: a1, clockwise: true)
ctx.strokePath()
let tip = CGPoint(x: c.x + r * cos(a1), y: c.y + r * sin(a1))
let dir = CGPoint(x: sin(a1), y: -cos(a1))
let nrm = CGPoint(x: cos(a1), y: sin(a1))
ctx.setFillColor(color(0xffffff, 0.55))
ctx.move(to: CGPoint(x: tip.x + dir.x * 46, y: tip.y + dir.y * 46))
ctx.addLine(to: CGPoint(x: tip.x - dir.x * 10 + nrm.x * 40, y: tip.y - dir.y * 10 + nrm.y * 40))
ctx.addLine(to: CGPoint(x: tip.x - dir.x * 10 - nrm.x * 40, y: tip.y - dir.y * 10 - nrm.y * 40))
ctx.closePath(); ctx.fillPath()
ctx.restoreGState()

func monitor(_ frame: CGRect, screen: [CGColor]) {
    let bezel = rounded(frame, 26)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0x050a30, 0.55))
    ctx.addPath(bezel); ctx.setFillColor(color(0xf4f6ff)); ctx.fillPath()
    ctx.restoreGState()
    fill(bezel, gradient([color(0xffffff), color(0xdfe4ff)]), from: CGPoint(x: frame.midX, y: frame.maxY), to: CGPoint(x: frame.midX, y: frame.minY))
    let glass = frame.insetBy(dx: 16, dy: 16)
    fill(rounded(glass, 13), gradient(screen), from: CGPoint(x: glass.minX, y: glass.maxY), to: CGPoint(x: glass.maxX, y: glass.minY))
    // Gloss.
    ctx.saveGState(); ctx.addPath(rounded(glass, 13)); ctx.clip()
    ctx.move(to: CGPoint(x: glass.minX, y: glass.maxY))
    ctx.addLine(to: CGPoint(x: glass.minX + glass.width * 0.55, y: glass.maxY))
    ctx.addLine(to: CGPoint(x: glass.minX, y: glass.minY + glass.height * 0.25))
    ctx.closePath(); ctx.setFillColor(color(0xffffff, 0.16)); ctx.fillPath()
    ctx.restoreGState()
    // Stand.
    let neck = CGRect(x: frame.midX - 16, y: frame.minY - 34, width: 32, height: 36)
    fill(rounded(neck, 6), gradient([color(0xdfe4ff), color(0xb8c1f2)]), from: CGPoint(x: neck.midX, y: neck.maxY), to: CGPoint(x: neck.midX, y: neck.minY))
    let foot = CGRect(x: frame.midX - 56, y: frame.minY - 46, width: 112, height: 16)
    fill(rounded(foot, 9), gradient([color(0xf4f6ff), color(0xc4ccf5)]), from: CGPoint(x: foot.midX, y: foot.maxY), to: CGPoint(x: foot.midX, y: foot.minY))
}

monitor(CGRect(x: 170, y: 500, width: 324, height: 210), screen: [color(0xffb36b), color(0xff5f8f), color(0x9b4dff)])
monitor(CGRect(x: 530, y: 500, width: 324, height: 210), screen: [color(0x5ee7ff), color(0x3d8bff), color(0x5a3dff)])

// Laptop, centred below.
let lid = CGRect(x: 392, y: 236, width: 240, height: 150)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 26, color: color(0x050a30, 0.55))
ctx.addPath(rounded(lid, 20)); ctx.setFillColor(color(0xf4f6ff)); ctx.fillPath()
ctx.restoreGState()
fill(rounded(lid, 20), gradient([color(0xffffff), color(0xdfe4ff)]), from: CGPoint(x: lid.midX, y: lid.maxY), to: CGPoint(x: lid.midX, y: lid.minY))
let lglass = lid.insetBy(dx: 13, dy: 13)
fill(rounded(lglass, 9), gradient([color(0x7cf2c8), color(0x23b7a6), color(0x1c6fd6)]), from: CGPoint(x: lglass.minX, y: lglass.maxY), to: CGPoint(x: lglass.maxX, y: lglass.minY))
let base = CGMutablePath()
base.move(to: CGPoint(x: 356, y: 230)); base.addLine(to: CGPoint(x: 668, y: 230))
base.addLine(to: CGPoint(x: 648, y: 206)); base.addLine(to: CGPoint(x: 376, y: 206)); base.closeSubpath()
fill(base, gradient([color(0xf4f6ff), color(0xb8c1f2)]), from: CGPoint(x: 512, y: 230), to: CGPoint(x: 512, y: 206))

// Check badge: "kept in place".
let badge = CGRect(x: 676, y: 214, width: 156, height: 156)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: color(0x050a30, 0.5))
ctx.addEllipse(in: badge); ctx.setFillColor(color(0x34d399)); ctx.fillPath()
ctx.restoreGState()
fill(CGPath(ellipseIn: badge, transform: nil), gradient([color(0x6ef0b4), color(0x10b981)]), from: CGPoint(x: badge.midX, y: badge.maxY), to: CGPoint(x: badge.midX, y: badge.minY))
ctx.setStrokeColor(color(0xffffff)); ctx.setLineWidth(18); ctx.setLineCap(.round); ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: badge.minX + 42, y: badge.midY + 2))
ctx.addLine(to: CGPoint(x: badge.minX + 66, y: badge.midY - 24))
ctx.addLine(to: CGPoint(x: badge.maxX - 38, y: badge.midY + 28))
ctx.strokePath()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
