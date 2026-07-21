import AppKit
import CoreGraphics

// Renders a 1024×1024 app icon PNG to the path given as argv[1].
// Motif: a stack of flashcards on an indigo→violet gradient, front card showing "文".

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let S: CGFloat = 1024

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

// Background rounded square with gradient.
let bg = CGRect(x: 0, y: 0, width: S, height: S)
let corner = S * 0.223
let bgPath = CGPath(roundedRect: bg, cornerWidth: corner, cornerHeight: corner, transform: nil)
ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
let grad = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(0.34, 0.38, 0.95), color(0.58, 0.44, 0.97)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])
// Soft top-left glow.
let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [color(1, 1, 1, 0.22), color(1, 1, 1, 0)] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: S * 0.3, y: S * 0.78), startRadius: 0,
                       endCenter: CGPoint(x: S * 0.3, y: S * 0.78), endRadius: S * 0.6, options: [])
ctx.restoreGState()

// A rounded card helper (centered at origin, drawn in a rotated space).
func drawCard(center: CGPoint, size: CGSize, rotationDeg: CGFloat, fill: CGColor,
              glyph: String? = nil, glyphColor: CGColor? = nil) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: rotationDeg * .pi / 180)
    let r = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
    let cr = size.width * 0.14
    let p = CGPath(roundedRect: r, cornerWidth: cr, cornerHeight: cr, transform: nil)
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 46, color: color(0.1, 0.08, 0.25, 0.35))
    ctx.addPath(p)
    ctx.setFillColor(fill)
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    if let glyph, let glyphColor {
        let font = NSFont.systemFont(ofSize: size.height * 0.52, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(cgColor: glyphColor) ?? .systemIndigo
        ]
        let str = NSAttributedString(string: glyph, attributes: attrs)
        let textSize = str.size()
        // Flip vertically for AppKit string drawing inside a CG context.
        ctx.saveGState()
        ctx.textMatrix = .identity
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        str.draw(at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2))
        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()
    }
    ctx.restoreGState()
}

let cardSize = CGSize(width: S * 0.5, height: S * 0.62)
let mid = CGPoint(x: S * 0.5, y: S * 0.47)

// Back card (accent tint), then front white card with the glyph.
drawCard(center: CGPoint(x: mid.x + S * 0.075, y: mid.y - S * 0.02),
         size: cardSize, rotationDeg: 9, fill: color(1, 1, 1, 0.32))
drawCard(center: mid, size: cardSize, rotationDeg: -7,
         fill: color(1, 1, 1, 1), glyph: "文", glyphColor: color(0.36, 0.40, 0.93))

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("Failed to make PNG\n".data(using: .utf8)!)
    exit(1)
}
try! data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
