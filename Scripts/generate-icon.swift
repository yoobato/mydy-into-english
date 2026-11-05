import AppKit
import ImageIO

// Export the approved B artwork and a deterministic social card with real typeset text.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = root.appendingPathComponent("design/app-icon-b.png")
guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil), let icon = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { fatalError("Approved B icon is missing") }
let ivory = NSColor(srgbRed: 0.973, green: 0.965, blue: 0.945, alpha: 1)
let ink = NSColor(srgbRed: 0.208, green: 0.275, blue: 0.231, alpha: 1)
let muted = NSColor(srgbRed: 0.451, green: 0.502, blue: 0.447, alpha: 1)
func render(_ width: Int, _ height: Int, to path: URL, draw: () -> Void) throws {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    guard let image = context.makeImage(), let output = CGImageDestinationCreateWithURL(path as CFURL, "public.png" as CFString, 1, nil) else { fatalError("Could not export image") }
    CGImageDestinationAddImage(output, image, nil)
    guard CGImageDestinationFinalize(output) else { fatalError("Could not save image") }
}
let destination = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : root.appendingPathComponent("IntoEnglishProbe/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
try render(1024, 1024, to: destination) {
    ink.setFill(); NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
    NSGraphicsContext.current!.cgContext.draw(icon, in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
}
try render(180, 180, to: root.appendingPathComponent("docs/assets/app-icon-b.png")) {
    ink.setFill(); NSRect(x: 0, y: 0, width: 180, height: 180).fill()
    NSGraphicsContext.current!.cgContext.draw(icon, in: NSRect(x: 0, y: 0, width: 180, height: 180))
}
try render(1200, 630, to: root.appendingPathComponent("docs/assets/social-preview-v1.png")) {
    ivory.setFill(); NSRect(x: 0, y: 0, width: 1200, height: 630).fill()
    func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ font: NSFont, _ color: NSColor, tracking: CGFloat = 0) {
        NSAttributedString(string: value, attributes: [.font: font, .foregroundColor: color, .kern: tracking]).draw(at: NSPoint(x: x, y: y))
    }
    text("INTO ENGLISH FOR iOS", 72, 544, .systemFont(ofSize: 13, weight: .semibold), muted, tracking: 2.5)
    text("단어 번역부터", 72, 378, .systemFont(ofSize: 58, weight: .semibold), ink, tracking: -2)
    text("문장 교정까지.", 72, 292, .systemFont(ofSize: 58, weight: .semibold), ink, tracking: -2)
    text("한국어와 영어로 입력하고, 어투와 문법을 다듬으세요.", 76, 212, .systemFont(ofSize: 20), muted)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: NSRect(x: 830, y: 232, width: 286, height: 286), xRadius: 62, yRadius: 62).addClip()
    NSGraphicsContext.current!.cgContext.draw(icon, in: NSRect(x: 830, y: 232, width: 286, height: 286))
    NSGraphicsContext.restoreGraphicsState()
    NSColor(srgbRed: 0.87, green: 0.875, blue: 0.83, alpha: 1).setFill()
    NSRect(x: 72, y: 110, width: 1056, height: 1).fill()
    text("into english.", 72, 49, NSFont(name: "Georgia-Bold", size: 30)!, ink, tracking: -1)
    text("into-english.mydy.kr", 904, 58, .systemFont(ofSize: 14), muted)
}
