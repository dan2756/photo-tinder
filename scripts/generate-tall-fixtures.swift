import AppKit
import ImageIO
import UniformTypeIdentifiers
let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("test-support/generated/tall-thumbnails", isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for index in 1...3 {
    let width = 300, height = 3000
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for band in 0..<10 {
        context.setFillColor(NSColor(calibratedHue: CGFloat(band) / 10, saturation: 0.7, brightness: 0.9, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: band * 300, width: width, height: 300))
    }
    let url = directory.appendingPathComponent("tall-\(index).png")
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
}
