import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Native vector drawing. The system applies the outer app-icon mask.
let destination = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("PhotoTinder/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

func ink(_ hex: UInt32) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}

for dark in [false, true] {
    let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(ink(dark ? 0x133f3c : 0x177e73))
    context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))

    // Offset media cards suggest the app's one-at-a-time review loop.
    context.saveGState()
    context.translateBy(x: 480, y: 518)
    context.rotate(by: -.pi / 13)
    context.setFillColor(ink(dark ? 0x31756b : 0x77bcab))
    context.addPath(CGPath(roundedRect: CGRect(x: -228, y: -246, width: 456, height: 492),
                           cornerWidth: 76, cornerHeight: 76, transform: nil))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.translateBy(x: 561, y: 528)
    context.rotate(by: .pi / 22)
    let card = CGRect(x: -228, y: -258, width: 456, height: 516)
    context.setFillColor(ink(0xf5f2e7))
    context.addPath(CGPath(roundedRect: card, cornerWidth: 76, cornerHeight: 76, transform: nil))
    context.fillPath()
    context.setFillColor(ink(0xdeb876))
    context.fillEllipse(in: CGRect(x: 45, y: 83, width: 75, height: 75))
    context.setStrokeColor(ink(dark ? 0x1e6f63 : 0x177e73))
    context.setLineWidth(54)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: CGPoint(x: -122, y: -17))
    context.addLine(to: CGPoint(x: -27, y: -105))
    context.addLine(to: CGPoint(x: 126, y: 56))
    context.strokePath()
    context.restoreGState()

    let image = context.makeImage()!
    let output = destination.appendingPathComponent(dark ? "AppIcon-dark.png" : "AppIcon.png")
    let writer = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(writer, image, nil)
    precondition(CGImageDestinationFinalize(writer))
    print(output.path)
}
