#!/usr/bin/env swift
// Renders the app's icon as the system draws it (including Liquid Glass on macOS 26) into PNGs for the website.
// Usage: swift scripts/render-icon.swift "build/ATEM ISO to FCPXML.app" docs/site
import AppKit

guard CommandLine.arguments.count == 3 else { fputs("usage: render-icon.swift <App.app> <output dir>\n", stderr); exit(64) }
let app = CommandLine.arguments[1]
let out = URL(fileURLWithPath: CommandLine.arguments[2])
let icon = NSWorkspace.shared.icon(forFile: app)

func png(_ pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                                  hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)!
    bitmap.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    icon.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for (name, size) in [("app-icon-1024.png", 1024), ("favicon-192.png", 192), ("apple-touch-icon.png", 180), ("favicon-32.png", 32)] {
    try png(size).write(to: out.appendingPathComponent(name))
}
print("Rendered app icons into \(out.path)")
