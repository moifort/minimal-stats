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

// A plain background, as quiet as the app: no gradient.
let canvas = NSColor(srgbRed: 0.965, green: 0.965, blue: 0.97, alpha: 1)
let bounds = NSRect(origin: .zero, size: pointSize)
canvas.setFill()
bounds.fill()

// One stats curve along the bottom edge, the icon's, in grey: a few points
// of load, calm, a spike, calm again, smoothed.
let load: [CGFloat] = [0.22, 0.30, 0.24, 0.38, 0.32, 0.52, 0.90, 0.62, 0.44, 0.50, 0.36, 0.42]
let chart = NSRect(x: -10, y: 10, width: pointSize.width + 20, height: 50)
let points = load.enumerated().map { i, v in
    NSPoint(x: chart.minX + chart.width * CGFloat(i) / CGFloat(load.count - 1), y: chart.minY + chart.height * v)
}
let curve = NSBezierPath()
curve.move(to: points[0])
for i in 0..<(points.count - 1) {
    let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, points.count - 1)]
    curve.curve(
        to: p2,
        controlPoint1: NSPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
        controlPoint2: NSPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
}
curve.lineWidth = 2.5
curve.lineCapStyle = .round
curve.lineJoinStyle = .round
NSColor(white: 0.0, alpha: 0.16).setStroke()
curve.stroke()

// The arrow, from the app to the Applications folder.
let arrowColor = NSColor(white: 0.40, alpha: 1)
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
    color: NSColor(white: 0.15, alpha: 1), y: 94)
drawCentered(
    "Glissez Stats dans Applications", size: 13, weight: .regular,
    color: NSColor(white: 0.42, alpha: 1), y: 74)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("could not encode the PNG\n".utf8))
    exit(1)
}
try png.write(to: output)
