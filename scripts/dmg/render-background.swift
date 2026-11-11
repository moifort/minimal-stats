// Renders the background of the Stats disk image: the window people see
// when they open the DMG, with an arrow from the app to the Applications
// alias. The two icons themselves are laid out by Finder (see build-dmg.sh);
// this picture only paints what sits behind them.
//
// Usage: render-background.swift <output.png>
//
// The PNG is drawn at 2x and tagged 144 dpi, so Finder sizes it in points and
// it stays sharp on Retina displays.

import AppKit

let pointSize = NSSize(width: 660, height: 400)
let scale: CGFloat = 2
// Where build-dmg.sh places the icons (Finder coordinates, origin top-left).
let appIconCenter = NSPoint(x: 165, y: 175)
let applicationsIconCenter = NSPoint(x: 495, y: 175)

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: render-background.swift <output.png>\n".utf8))
    exit(64)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])

let pixels = NSSize(width: pointSize.width * scale, height: pointSize.height * scale)
guard
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )
else {
    FileHandle.standardError.write(Data("could not allocate the bitmap\n".utf8))
    exit(1)
}
// 1320 px for 660 pt: Finder reads the PNG as 144 dpi, and the drawing
// context below works in points.
rep.size = pointSize

NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = context
context.imageInterpolation = .high

// Finder coordinates have their origin at the top-left, AppKit at the bottom
// left: flip once here so the icon positions above can be reused as-is.
func flipped(_ point: NSPoint) -> NSPoint { NSPoint(x: point.x, y: pointSize.height - point.y) }

// The icon's own colours: a deep blue to violet glass cube.
let canvas = NSColor(srgbRed: 0.86, green: 0.87, blue: 0.93, alpha: 1)
let bounds = NSRect(origin: .zero, size: pointSize)
NSGradient(colors: [canvas.blended(withFraction: 0.45, of: .white)!, canvas])!
    .draw(in: bounds, angle: -90)

// A faint echo of the menu bar widgets along the bottom edge: the CPU line
// chart in the icon's blue and violet, over a grid like the widget's.
let violet = NSColor(srgbRed: 0.55, green: 0.42, blue: 0.94, alpha: 1)
let blue = NSColor(srgbRed: 0.26, green: 0.50, blue: 0.96, alpha: 1)
let cyan = NSColor(srgbRed: 0.30, green: 0.80, blue: 0.92, alpha: 1)

func chart(baseline: CGFloat, height: CGFloat, seed: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.lineWidth = 3
    path.lineCapStyle = .butt
    path.lineJoinStyle = .round
    var x: CGFloat = -20
    path.move(to: NSPoint(x: x, y: baseline))
    while x <= pointSize.width + 20 {
        // A few sines make a load curve: calm, a spike, calm again.
        let t = x / pointSize.width
        let envelope = sin(min(max(t, 0), 1) * .pi)
        let load = 0.35 * sin(t * 19 + seed) + 0.25 * sin(t * 47 + seed * 2) + 0.4 * exp(-pow((t - 0.62) * 9, 2))
        path.line(to: NSPoint(x: x, y: baseline + height * envelope * max(load, -0.2)))
        x += 3
    }
    return path
}

for (color, height, seed, baseline) in [(violet, 44.0, 0.0, 40.0), (blue, 30.0, 1.7, 34.0), (cyan, 20.0, 3.1, 30.0)] as [(NSColor, CGFloat, CGFloat, CGFloat)] {
    let glow = chart(baseline: baseline, height: height, seed: seed)
    glow.lineWidth = 12
    color.withAlphaComponent(0.10).setStroke()
    glow.stroke()
    let stroke = chart(baseline: baseline, height: height, seed: seed)
    color.withAlphaComponent(0.50).setStroke()
    stroke.stroke()
}

// The arrow, from the app to the Applications folder.
let arrowColor = NSColor(srgbRed: 0.38, green: 0.38, blue: 0.48, alpha: 1)
let arrowY = flipped(appIconCenter).y
let arrowStart = NSPoint(x: appIconCenter.x + 88, y: arrowY)
let arrowEnd = NSPoint(x: applicationsIconCenter.x - 88, y: arrowY)
let shaft = NSBezierPath()
shaft.lineWidth = 5
shaft.lineCapStyle = .round
shaft.move(to: arrowStart)
shaft.line(to: NSPoint(x: arrowEnd.x - 6, y: arrowEnd.y))
arrowColor.setStroke()
shaft.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: arrowEnd.x - 22, y: arrowEnd.y + 16))
head.line(to: arrowEnd)
head.line(to: NSPoint(x: arrowEnd.x - 22, y: arrowEnd.y - 16))
head.lineWidth = 5
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.stroke()

// The instruction, under the icons and their labels.
func drawCentered(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
    ]
    let string = NSAttributedString(string: text, attributes: attributes)
    let width = string.size().width
    string.draw(at: NSPoint(x: (pointSize.width - width) / 2, y: y))
}
// One picture for every Mac, whatever its language: English first, then
// French, like Dictate's.
drawCentered(
    "Drag Stats to Applications", size: 17, weight: .semibold,
    color: NSColor(srgbRed: 0.18, green: 0.19, blue: 0.24, alpha: 1), y: 94)
drawCentered(
    "Glissez Stats dans Applications", size: 13, weight: .regular,
    color: NSColor(srgbRed: 0.38, green: 0.39, blue: 0.46, alpha: 1), y: 74)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("could not encode the PNG\n".utf8))
    exit(1)
}
try png.write(to: output)
