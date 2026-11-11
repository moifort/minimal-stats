// Renders the Mac App Store screenshot of one locale, 2880×1800: a dark
// desktop, the menu bar with the four widgets, the popover open under them,
// and the promise on the left. The widgets and the popover are captures of
// the App Store build itself (docs/app-store.md tells how to retake them).
//
// Usage: swift scripts/app-store/render-screenshots.swift <widgets.png> <popover.png> <title> <subtitle> <output.jpg>
import AppKit

let args = CommandLine.arguments
guard args.count == 6,
      let widgets = NSImage(contentsOfFile: args[1]),
      let popover = NSImage(contentsOfFile: args[2])
else {
    FileHandle.standardError.write(Data("usage: render-screenshots.swift <widgets.png> <popover.png> <title> <subtitle> <output.jpg>\n".utf8))
    exit(64)
}
let size = NSSize(width: 2880, height: 1800)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Desktop: graphite, a little lighter towards the popover.
NSGradient(colors: [NSColor(white: 0.17, alpha: 1), NSColor(white: 0.07, alpha: 1)])!
    .draw(in: NSRect(origin: .zero, size: size), angle: -90)
NSGradient(colors: [NSColor(white: 1, alpha: 0.07), NSColor(white: 1, alpha: 0)])!
    .draw(fromCenter: NSPoint(x: 2150, y: 1100), radius: 0, toCenter: NSPoint(x: 2150, y: 1100), radius: 1100, options: [])

// Menu bar, 24 points at 2x.
let bar = NSRect(x: 0, y: size.height - 48, width: size.width, height: 48)
NSColor(white: 0.12, alpha: 0.92).setFill()
bar.fill()
let clock = NSAttributedString(string: "9:41", attributes: [.font: NSFont.systemFont(ofSize: 27, weight: .medium), .foregroundColor: NSColor.white])
clock.draw(at: NSPoint(x: size.width - 60 - clock.size().width, y: bar.minY + 9))
let widgetsRect = NSRect(x: size.width - 200 - widgets.size.width * 2, y: bar.minY + 2, width: widgets.size.width * 2, height: 44)
NSColor(white: 1, alpha: 0.16).setFill()
NSBezierPath(roundedRect: widgetsRect.insetBy(dx: -10, dy: 2), xRadius: 10, yRadius: 10).fill()
widgets.draw(in: widgetsRect)

// The popover hangs under the widgets, right-aligned with them; the capture
// carries its own shadow margin (about 40 px each side at 2x).
let pop = NSSize(width: popover.size.width * 2, height: popover.size.height * 2)
let shadowMargin: CGFloat = 46
popover.draw(in: NSRect(x: widgetsRect.maxX + 10 + shadowMargin - pop.width, y: bar.minY - pop.height + 22, width: pop.width, height: pop.height))

// The promise.
let title = NSMutableParagraphStyle()
title.lineSpacing = 4
NSAttributedString(string: args[3], attributes: [.font: NSFont.systemFont(ofSize: 150, weight: .bold), .foregroundColor: NSColor.white, .paragraphStyle: title])
    .draw(in: NSRect(x: 200, y: 820, width: 1500, height: 420))
NSAttributedString(string: args[4], attributes: [.font: NSFont.systemFont(ofSize: 58, weight: .regular), .foregroundColor: NSColor(white: 0.72, alpha: 1), .paragraphStyle: title])
    .draw(in: NSRect(x: 204, y: 520, width: 1250, height: 260))

let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!
try jpeg.write(to: URL(fileURLWithPath: args[5]))
