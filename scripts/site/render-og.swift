// Renders site/og.png, the 1200×630 share preview: the icon, the name, the
// promise, on white. Dictate renders its own from HTML with Chrome; this one
// needs nothing but AppKit.
//
// Usage: swift scripts/site/render-og.swift <icon.png> <output.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let icon = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write(Data("usage: render-og.swift <icon.png> <output.png>\n".utf8))
    exit(64)
}
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 630, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor.white.setFill()
NSRect(x: 0, y: 0, width: 1200, height: 630).fill()
icon.draw(in: NSRect(x: 90, y: 155, width: 320, height: 320))
let ink = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
NSAttributedString(string: "Stats", attributes: [.font: NSFont.systemFont(ofSize: 96, weight: .bold), .foregroundColor: ink])
    .draw(at: NSPoint(x: 460, y: 330))
let lead = NSMutableParagraphStyle()
lead.lineSpacing = 6
NSAttributedString(string: "CPU, network, memory and disk,\nlive in your Mac's menu bar.\nFree and open source.",
                   attributes: [.font: NSFont.systemFont(ofSize: 38, weight: .regular),
                                .foregroundColor: NSColor(srgbRed: 0.43, green: 0.43, blue: 0.45, alpha: 1),
                                .paragraphStyle: lead])
    .draw(in: NSRect(x: 462, y: 150, width: 700, height: 170))
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
