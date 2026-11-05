import AppKit

let size: CGFloat = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                              bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedRed: 0.98, green: 0.97, blue: 0.94, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
let bubble = NSBezierPath(roundedRect: NSRect(x: 160, y: 220, width: 660, height: 590), xRadius: 175, yRadius: 175)
NSColor(calibratedRed: 0.81, green: 0.45, blue: 0.35, alpha: 1).setFill()
bubble.fill()
let tail = NSBezierPath()
tail.move(to: NSPoint(x: 295, y: 245)); tail.line(to: NSPoint(x: 255, y: 135)); tail.line(to: NSPoint(x: 425, y: 245)); tail.close(); tail.fill()
let font = NSFont(name: "Georgia-Italic", size: 480) ?? NSFont.systemFont(ofSize: 480, weight: .medium)
let letter = NSAttributedString(string: "i", attributes: [.font: font, .foregroundColor: NSColor(calibratedRed: 1, green: 0.96, blue: 0.9, alpha: 1)])
let bounds = letter.size()
letter.draw(at: NSPoint(x: 490 - bounds.width / 2, y: 230))
let star = NSBezierPath()
let cx: CGFloat = 790, cy: CGFloat = 805
star.move(to: NSPoint(x: cx, y: cy + 85))
star.curve(to: NSPoint(x: cx + 85, y: cy), controlPoint1: NSPoint(x: cx + 17, y: cy + 18), controlPoint2: NSPoint(x: cx + 18, y: cy + 17))
star.curve(to: NSPoint(x: cx, y: cy - 85), controlPoint1: NSPoint(x: cx + 18, y: cy - 17), controlPoint2: NSPoint(x: cx + 17, y: cy - 18))
star.curve(to: NSPoint(x: cx - 85, y: cy), controlPoint1: NSPoint(x: cx - 17, y: cy - 18), controlPoint2: NSPoint(x: cx - 18, y: cy - 17))
star.curve(to: NSPoint(x: cx, y: cy + 85), controlPoint1: NSPoint(x: cx - 18, y: cy + 17), controlPoint2: NSPoint(x: cx - 17, y: cy + 18))
NSColor(calibratedRed: 0.53, green: 0.62, blue: 0.43, alpha: 1).setFill(); star.fill()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
