// Renders the Stats app icon: a flat plate with a stats curve, nothing else.
// No glass, no gradient: the icon looks like the menu bar widgets, monochrome.
//
// Usage: swift scripts/icon/render-icon.swift <output.png> [dark|light|widgets]
//
// Drawn on Apple's macOS grid: a 1024 px canvas, the plate 824 px wide with
// a 185 px corner radius, centred, under a soft drop shadow.
// scripts/icon/build-icns.sh turns the PNG into Sources/Stats/AppIcon.icns.

import AppKit

let size: CGFloat = 1024
let plateRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 185

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: render-icon.swift <output.png> [dark|light|widgets]\n".utf8))
    exit(64)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let variant = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "dark"

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: size, height: size)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

let light = variant == "light"
let plateColor = light ? NSColor(white: 0.97, alpha: 1) : NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
let ink = light ? NSColor(white: 0.10, alpha: 1) : NSColor.white

// The plate and its shadow.
let plate = NSBezierPath(roundedRect: plateRect, xRadius: radius, yRadius: radius)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.shadowBlurRadius = 24
shadow.set()
plateColor.setFill()
plate.fill()
NSGraphicsContext.restoreGraphicsState()
if light {
    NSColor.black.withAlphaComponent(0.08).setStroke()
    plate.lineWidth = 2
    plate.stroke()
}
plate.addClip()

/// A smooth curve through the points (Catmull-Rom turned into Béziers).
func smooth(_ points: [NSPoint]) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: points[0])
    for i in 0..<(points.count - 1) {
        let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, points.count - 1)]
        let c1 = NSPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
        let c2 = NSPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
        path.curve(to: p2, controlPoint1: c1, controlPoint2: c2)
    }
    return path
}

/// A load curve over `rect`: values 0…1, calm, a spike, calm again.
func curve(in rect: NSRect, values: [CGFloat]) -> [NSPoint] {
    values.enumerated().map { i, v in
        NSPoint(x: rect.minX + rect.width * CGFloat(i) / CGFloat(values.count - 1), y: rect.minY + rect.height * v)
    }
}

let load: [CGFloat] = [0.22, 0.30, 0.24, 0.38, 0.32, 0.52, 0.90, 0.62, 0.44, 0.50, 0.36, 0.42]

switch variant {
case "widgets":
    // The four menu bar widgets, side by side, as on the bar.
    ink.setStroke(); ink.setFill()
    let top: CGFloat = 640, bottom: CGFloat = 384, mid = (top + bottom) / 2
    // CPU: a line chart.
    let cpu = smooth(curve(in: NSRect(x: 160, y: bottom + 20, width: 230, height: top - bottom - 40), values: load))
    cpu.lineWidth = 20; cpu.lineCapStyle = .round; cpu.lineJoinStyle = .round; cpu.stroke()
    // Network: upload above, download below, mirrored.
    for (i, (up, down)) in [(0.35, 0.55), (0.6, 0.85), (0.25, 0.6), (0.7, 1.0), (0.4, 0.5)].enumerated() {
        let x = 424 + CGFloat(i) * 34, half = (top - bottom) / 2 - 10
        NSBezierPath(roundedRect: NSRect(x: x, y: mid + 5, width: 20, height: half * up), xRadius: 7, yRadius: 7).fill()
        NSBezierPath(roundedRect: NSRect(x: x, y: mid - 5 - half * down, width: 20, height: half * down), xRadius: 7, yRadius: 7).fill()
    }
    // Memory: a vertical gauge, two thirds full.
    let gauge = NSBezierPath(roundedRect: NSRect(x: 622, y: bottom, width: 72, height: top - bottom), xRadius: 22, yRadius: 22)
    gauge.lineWidth = 12; gauge.stroke()
    NSBezierPath(roundedRect: NSRect(x: 640, y: bottom + 18, width: 36, height: (top - bottom - 36) * 0.65), xRadius: 9, yRadius: 9).fill()
    // Disk: a pie, two thirds used.
    let center = NSPoint(x: 806, y: mid)
    let ring = NSBezierPath(ovalIn: NSRect(x: center.x - 66, y: center.y - 66, width: 132, height: 132))
    ring.lineWidth = 12; ring.stroke()
    let slice = NSBezierPath()
    slice.move(to: center)
    slice.appendArc(withCenter: center, radius: 66, startAngle: 90, endAngle: -150, clockwise: true)
    slice.close(); slice.fill()
default:
    // Faint grid lines, like the widget's scale.
    ink.withAlphaComponent(0.14).setStroke()
    for y in stride(from: CGFloat(300), through: 720, by: 140) {
        let line = NSBezierPath()
        line.move(to: NSPoint(x: 190, y: y)); line.line(to: NSPoint(x: 834, y: y))
        line.lineWidth = 6; line.stroke()
    }
    let points = curve(in: NSRect(x: 190, y: 300, width: 644, height: 420), values: load)
    let line = smooth(points)
    line.lineWidth = 32; line.lineCapStyle = .round; line.lineJoinStyle = .round
    ink.setStroke()
    line.stroke()
}

NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: output)
