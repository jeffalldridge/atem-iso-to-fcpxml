#!/usr/bin/env swift
// Renders the app icon (same shapes and palette as docs/site/favicon.svg) as an .icns.
// Usage: swift scripts/make-icon.swift build/AppIcon.icns
import AppKit

guard CommandLine.arguments.count == 2 else { fputs("usage: make-icon.swift <output.icns>\n", stderr); exit(64) }
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

func render(_ pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                                  hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(pixels) / 64
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    // macOS icons leave a margin: draw the 64-unit artwork inset by 5 units on each side.
    let inset: CGFloat = 5
    let canvas = NSRect(x: inset, y: inset, width: 64 - 2 * inset, height: 64 - 2 * inset)
    let shrink = NSAffineTransform()
    shrink.translateX(by: inset, yBy: inset)
    shrink.scale(by: (64 - 2 * inset) / 64)
    shrink.concat()
    _ = canvas
    NSColor(srgbRed: 13/255, green: 13/255, blue: 18/255, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 64, height: 64), xRadius: 14, yRadius: 14).fill()
    NSColor(srgbRed: 146/255, green: 146/255, blue: 164/255, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 8, y: 18, width: 22, height: 28), xRadius: 4, yRadius: 4).fill()
    let orange = NSColor(srgbRed: 1, green: 138/255, blue: 76/255, alpha: 1)
    orange.setStroke(); orange.setFill()
    let line = NSBezierPath(); line.move(to: NSPoint(x: 34, y: 32)); line.line(to: NSPoint(x: 46, y: 32))
    line.lineWidth = 5; line.lineCapStyle = .round; line.stroke()
    let arrow = NSBezierPath(); arrow.move(to: NSPoint(x: 43, y: 24)); arrow.line(to: NSPoint(x: 53, y: 32)); arrow.line(to: NSPoint(x: 43, y: 40)); arrow.close(); arrow.fill()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try task.run()
task.waitUntilExit()
exit(task.terminationStatus)
