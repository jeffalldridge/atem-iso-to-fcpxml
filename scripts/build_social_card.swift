// Development-only asset generator: swift scripts/build_social_card.swift
// AppKit typesetting keeps the social card local, lightweight and editable.
import AppKit
let width = 1200, height = 630
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed:r/255, green:g/255, blue:b/255, alpha:1)
}
let bg = color(13,13,18), text = color(232,232,238), muted = color(160,160,176), accent = color(255,138,76)
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ fill: NSColor) {
    fill.setFill(); NSBezierPath(rect:NSRect(x:x, y:CGFloat(height)-y-h, width:w, height:h)).fill()
}
func label(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ ink: NSColor, _ weight: NSFont.Weight = .regular) {
    let attrs: [NSAttributedString.Key: Any] = [.font:NSFont.systemFont(ofSize:size,weight:weight), .foregroundColor:ink]
    (value as NSString).draw(at:NSPoint(x:x,y:CGFloat(height)-y-size*1.25),withAttributes:attrs)
}
rect(0,0,1200,630,bg)
if let icon = NSImage(contentsOfFile: "docs/site/app-icon-1024.png") {
    icon.draw(in: NSRect(x: 72, y: CGFloat(height) - 48 - 72, width: 72, height: 72), from: .zero, operation: .sourceOver, fraction: 1)
}
label("ATEM ISO to FCPXML",160,66,23,accent,.semibold)
label("Your Live Edit.",72,132,72,text,.semibold)
label("Ready for Final Cut.",72,214,72,accent,.semibold)
label("Multicam. Live cuts. Uncompressed WAV audio.",76,324,27,muted)
rect(76,407,300,62,color(112,76,57)); rect(380,407,220,62,color(56,56,69)); rect(604,407,300,62,color(112,76,57)); rect(908,407,216,62,color(56,56,69))
rect(76,407,300,3,accent); rect(604,407,300,3,accent)
label("Camera 1",94,424,18,text); label("Camera 2",398,424,18,text); label("Camera 1",622,424,18,text); label("Camera 2",926,424,18,text)
rect(76,477,1048,35,color(38,62,53)); label("Your selected WAV",94,481,15,color(180,213,197))
label("Free & open source  ·  Made for Mac",76,555,20,muted)
NSGraphicsContext.restoreGraphicsState()
let data = bitmap.representation(using:.png,properties:[:])!
try data.write(to: URL(fileURLWithPath:"docs/site/social-card.png"))
print("Wrote docs/site/social-card.png (1200 × 630)")
