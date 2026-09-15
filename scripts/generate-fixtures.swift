import AppKit
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Reproducible, disposable test media. These are drawings, never production app content.
// Run from the project root:
// xcrun swiftc -parse-as-library scripts/generate-fixtures.swift -o /tmp/photo-tinder-fixtures
// /tmp/photo-tinder-fixtures

private struct Fixture: Codable {
    let filename: String
    let title: String
    let captureDate: Date
    let latitude: Double?
    let longitude: Double?
    let kind: String
    let width: Int
    let height: Int
}

private func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

private func polygon(_ context: CGContext, _ points: [CGPoint], _ fill: CGColor) {
    guard let first = points.first else { return }
    context.beginPath()
    context.move(to: first)
    points.dropFirst().forEach { context.addLine(to: $0) }
    context.closePath()
    context.setFillColor(fill)
    context.fillPath()
}

private func gradient(_ context: CGContext, rect: CGRect, colors: [CGColor], vertical: Bool = true) {
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
    context.saveGState()
    context.clip(to: rect)
    context.drawLinearGradient(gradient,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: vertical ? rect.midX : rect.maxX, y: rect.minY), options: [])
    context.restoreGState()
}

private func label(_ value: String, context: CGContext, rect: CGRect, size: CGFloat,
                   weight: NSFont.Weight = .medium, ink: NSColor = .white) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    (value as NSString).draw(in: rect, withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: ink
    ])
    NSGraphicsContext.restoreGraphicsState()
}

private func renderScene(width: Int, height: Int, variant: Int, phase: CGFloat = 0,
                         title: String, markDisposable: Bool = true) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let w = CGFloat(width), h = CGFloat(height)
    let rect = CGRect(x: 0, y: 0, width: w, height: h)
    let themes: [[UInt32]] = [
        [0x729fa8, 0xd6dfca, 0x477a7b, 0x215659, 0x163d42],
        [0xc98077, 0xf0c29c, 0xb16d61, 0x7f4e59, 0x393f52],
        [0x7ba7b5, 0xd5dcd0, 0x86a5a2, 0x456e77, 0x254652],
        [0xd9bd91, 0xf5e7c1, 0xdfa878, 0xbe8066, 0x8d5853],
        [0x1f344f, 0x8b9ea3, 0x536e80, 0x284c66, 0x122c41],
        [0x9ca791, 0xdbe1b8, 0x7b9271, 0x466c60, 0x204e49]
    ]
    let theme = themes[variant % themes.count]
    gradient(context, rect: rect, colors: [color(theme[0]), color(theme[1])])
    context.setFillColor(color(0xffedbf, alpha: 0.85))
    let sunX = w * (0.72 + 0.015 * sin(phase * .pi * 2))
    context.fillEllipse(in: CGRect(x: sunX - w * 0.065, y: h * 0.72, width: w * 0.13, height: w * 0.13))

    // Thin cloud wisps soften the sky while retaining crisp thumbnails.
    for index in 0..<7 {
        let y = h * (0.63 + CGFloat(index) * 0.045)
        let x = w * (CGFloat((index * 23 + variant * 17) % 70) / 100 - 0.1)
        context.setFillColor(color(0xffffff, alpha: 0.075))
        context.fillEllipse(in: CGRect(x: x, y: y, width: w * 0.47, height: h * 0.011))
    }

    if variant % 6 == 3 {
        for layer in 0..<5 {
            let baseline = h * (0.35 - CGFloat(layer) * 0.065)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: baseline))
            path.addCurve(to: CGPoint(x: w, y: baseline + h * 0.08),
                          control1: CGPoint(x: w * 0.3, y: baseline + h * 0.38),
                          control2: CGPoint(x: w * 0.65, y: baseline - h * 0.11))
            path.addLine(to: CGPoint(x: w, y: 0))
            path.closeSubpath()
            context.addPath(path)
            context.setFillColor(color(theme[min(4, layer + 1)]))
            context.fillPath()
        }
    } else {
        for layer in 0..<3 {
            let y = h * (0.43 - CGFloat(layer) * 0.105)
            let peak = h * (0.76 - CGFloat(layer) * 0.14)
            polygon(context, [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: y),
                CGPoint(x: w * 0.17, y: peak - h * 0.12), CGPoint(x: w * 0.31, y: y + h * 0.12),
                CGPoint(x: w * 0.54, y: peak), CGPoint(x: w * 0.73, y: y + h * 0.08),
                CGPoint(x: w * 0.89, y: peak - h * 0.09), CGPoint(x: w, y: y + h * 0.1),
                CGPoint(x: w, y: 0)], color(theme[layer + 2]))
            if layer == 0 && variant % 2 == 0 {
                polygon(context, [CGPoint(x: w * 0.47, y: peak - h * 0.10),
                    CGPoint(x: w * 0.54, y: peak), CGPoint(x: w * 0.61, y: peak - h * 0.12),
                    CGPoint(x: w * 0.55, y: peak - h * 0.075), CGPoint(x: w * 0.52, y: peak - h * 0.10)],
                    color(0xecede0, alpha: 0.8))
            }
        }

        let lake = CGRect(x: 0, y: 0, width: w, height: h * 0.30)
        gradient(context, rect: lake, colors: [color(theme[2]), color(theme[4])])
        for index in 0..<36 {
            let fraction = CGFloat(index) / 36
            let y = h * 0.29 * fraction
            let shift = sin(CGFloat(index) * 1.37 + phase * .pi * 2) * w * 0.03
            let x = w * CGFloat((index * 43 + variant * 7) % 97) / 100 + shift
            context.setStrokeColor(color(0xe7e8cc, alpha: 0.1 + 0.1 * fraction))
            context.setLineWidth(1 + (1 - fraction) * 2)
            context.move(to: CGPoint(x: x, y: y))
            context.addLine(to: CGPoint(x: min(w, x + w * 0.15 * (1 - fraction)), y: y))
            context.strokePath()
        }

        // Foreground shore and pine silhouettes.
        polygon(context, [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: h * 0.22),
                          CGPoint(x: w * 0.13, y: h * 0.13), CGPoint(x: w * 0.40, y: 0)],
                color(theme[4]))
        for index in 0..<5 {
            let x = w * CGFloat(index) * 0.036
            let base = h * (0.09 + CGFloat(5 - index) * 0.018)
            let treeHeight = h * (0.16 - CGFloat(index) * 0.018)
            for branch in 0..<3 {
                let bottom = base + CGFloat(branch) * treeHeight * 0.17
                let half = w * (0.032 - CGFloat(branch) * 0.006)
                polygon(context, [CGPoint(x: x - half, y: bottom), CGPoint(x: x, y: bottom + treeHeight * 0.6),
                                  CGPoint(x: x + half, y: bottom)], color(theme[4]))
            }
        }
    }

    if markDisposable {
        context.setFillColor(color(0x10202b, alpha: 0.58))
        context.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.066))
        label("DISPOSABLE FIXTURE  ·  \(title.uppercased())", context: context,
              rect: CGRect(x: w * 0.035, y: h * 0.021, width: w * 0.93, height: h * 0.027),
              size: max(12, w * 0.017))
    }
    return context.makeImage()!
}

private func screenshotGraphic(width: Int, height: Int) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let w = CGFloat(width), h = CGFloat(height)
    context.setFillColor(color(0xf4f1e8))
    context.fill(CGRect(x: 0, y: 0, width: w, height: h))
    label("Field notes", context: context, rect: CGRect(x: w * 0.08, y: h * 0.78, width: w * 0.84, height: h * 0.10),
          size: w * 0.075, weight: .bold, ink: NSColor(cgColor: color(0x253f3c))!)
    label("A quiet weekend outside.", context: context,
          rect: CGRect(x: w * 0.08, y: h * 0.72, width: w * 0.84, height: h * 0.05),
          size: w * 0.037, ink: NSColor(cgColor: color(0x586963))!)
    let scene = renderScene(width: width, height: width, variant: 5, title: "Forest", markDisposable: false)
    context.draw(scene, in: CGRect(x: w * 0.08, y: h * 0.26, width: w * 0.84, height: w * 0.84))
    for index in 0..<3 {
        context.setFillColor(color(0xbdc7ba))
        context.fill(CGRect(x: w * 0.08, y: h * (0.20 - CGFloat(index) * 0.03),
                            width: w * (index == 2 ? 0.55 : 0.84), height: h * 0.006))
    }
    label("DISPOSABLE SCREENSHOT-LIKE GRAPHIC", context: context,
          rect: CGRect(x: w * 0.08, y: h * 0.045, width: w * 0.84, height: h * 0.026),
          size: w * 0.02, ink: NSColor(cgColor: color(0x586963))!)
    return context.makeImage()!
}

private func writeImage(_ image: CGImage, to url: URL, fixture: Fixture) throws {
    let isPNG = url.pathExtension == "png"
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
        (isPNG ? UTType.png.identifier : UTType.jpeg.identifier) as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
    var properties: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: 0.91,
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: formatter.string(from: fixture.captureDate)],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFImageDescription: "Disposable Photo Tinder test drawing: \(fixture.title)",
                                       kCGImagePropertyTIFFDateTime: formatter.string(from: fixture.captureDate)]
    ]
    if let latitude = fixture.latitude, let longitude = fixture.longitude {
        properties[kCGImagePropertyGPSDictionary] = [
            kCGImagePropertyGPSLatitude: abs(latitude), kCGImagePropertyGPSLatitudeRef: latitude >= 0 ? "N" : "S",
            kCGImagePropertyGPSLongitude: abs(longitude), kCGImagePropertyGPSLongitudeRef: longitude >= 0 ? "E" : "W"
        ]
    }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

private func makeVideo(at url: URL, directory: URL) async throws {
    let silentURL = directory.appendingPathComponent("silent-intermediate.mov")
    let audioURL = directory.appendingPathComponent("tone-intermediate.caf")
    for target in [url, silentURL, audioURL] where FileManager.default.fileExists(atPath: target.path) {
        try FileManager.default.removeItem(at: target)
    }
    let writer = try AVAssetWriter(outputURL: silentURL, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 720, AVVideoHeightKey: 1080
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
        sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                                      kCVPixelBufferWidthKey as String: 720,
                                      kCVPixelBufferHeightKey as String: 1080])
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    writer.startSession(atSourceTime: .zero)
    let frameCount = 96
    for index in 0..<frameCount {
        while !input.isReadyForMoreMediaData {
            try await Task.sleep(for: .milliseconds(5))
        }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer) == kCVReturnSuccess,
              let buffer else { throw CocoaError(.fileWriteUnknown) }
        CVPixelBufferLockBaseAddress(buffer, [])
        let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 720, height: 1080,
                                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
        let phase = CGFloat(index) / CGFloat(frameCount)
        context.draw(renderScene(width: 720, height: 1080, variant: 2, phase: phase, title: "Moving water"),
                     in: CGRect(x: 0, y: 0, width: 720, height: 1080))
        // A moving white bird makes active playback easy to verify visually.
        let birdX = 90 + phase * 530
        let birdY = 680 + sin(phase * .pi * 4) * 22
        context.setStrokeColor(color(0xffffff))
        context.setLineWidth(4)
        context.move(to: CGPoint(x: birdX - 15, y: birdY + 6))
        context.addLine(to: CGPoint(x: birdX, y: birdY))
        context.addLine(to: CGPoint(x: birdX + 15, y: birdY + 6))
        context.strokePath()
        label(String(format: "%.1f s", Double(index) / 24), context: context,
              rect: CGRect(x: 590, y: 995, width: 100, height: 40), size: 24)
        CVPixelBufferUnlockBaseAddress(buffer, [])
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 24)) else {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
    }
    input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }

    let sampleRate = 44_100.0
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let frameCapacity = AVAudioFrameCount(sampleRate * 4)
    let audioBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity)!
    audioBuffer.frameLength = frameCapacity
    for frame in 0..<Int(frameCapacity) {
        let t = Double(frame) / sampleRate
        let fade = min(1, t * 5) * min(1, (4 - t) * 5)
        audioBuffer.floatChannelData![0][frame] = Float(0.06 * fade * sin(t * .pi * 2 * 330))
    }
    let audioFile = try AVAudioFile(forWriting: audioURL, settings: format.settings)
    try audioFile.write(from: audioBuffer)
    let composition = AVMutableComposition()
    let videoAsset = AVURLAsset(url: silentURL)
    let audioAsset = AVURLAsset(url: audioURL)
    let duration = try await videoAsset.load(.duration)
    let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first!
    let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first!
    try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        .insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoTrack, at: .zero)
    try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        .insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: audioTrack, at: .zero)
    let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)!
    try await exporter.export(to: url, as: .mov)
    try FileManager.default.removeItem(at: silentURL)
    try FileManager.default.removeItem(at: audioURL)
    let finalAsset = AVURLAsset(url: url)
    let finalDuration = try await finalAsset.load(.duration)
    let videoCount = try await finalAsset.loadTracks(withMediaType: .video).count
    let audioCount = try await finalAsset.loadTracks(withMediaType: .audio).count
    print("Verified video: \(String(format: "%.2f", finalDuration.seconds)) seconds, \(videoCount) video / \(audioCount) audio tracks")
}

@main
private struct GenerateFixtures {
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let directory = root.appendingPathComponent("test-support/media", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let calendar = Calendar(identifier: .gregorian)
        // Relative dates keep the Recent / Older integration fixtures useful after checkout.
        let now = Date()
        let names = ["Alpine morning", "Rose dusk", "Blue ridge", "Desert light", "After the rain", "Forest stillness",
                     "Across the lake", "Last light", "Mountain air", "Warm sand", "Blue hour", "A quiet shore"]
        var fixtures: [Fixture] = []
        for index in 0..<names.count {
            let wide = index == 2 || index == 8
            let panorama = index == 6
            let width = panorama ? 1800 : (wide ? 1440 : 1080)
            let height = panorama ? 720 : (wide ? 960 : 1440)
            let old = index >= 8
            let date = calendar.date(byAdding: .day, value: old ? -(500 + index) : -(index * 3 + 1), to: now)!
            let locationIndex = index % 3
            let latitude: Double? = locationIndex == 2 ? nil : (locationIndex == 0 ? 46.58 : 36.24)
            let longitude: Double? = locationIndex == 2 ? nil : (locationIndex == 0 ? 7.96 : -116.82)
            let filename = String(format: "%02d-disposable-%@.jpg", index + 1, names[index].lowercased().replacingOccurrences(of: " ", with: "-"))
            let fixture = Fixture(filename: filename, title: names[index], captureDate: date,
                                  latitude: latitude, longitude: longitude, kind: "synthetic scenic drawing", width: width, height: height)
            try writeImage(renderScene(width: width, height: height, variant: index, title: names[index]),
                           to: directory.appendingPathComponent(filename), fixture: fixture)
            fixtures.append(fixture)
        }
        let screenshot = Fixture(filename: "13-disposable-screen-like.png", title: "Field notes", captureDate: now,
                                  latitude: nil, longitude: nil, kind: "screenshot-like graphic, not a PhotoKit screenshot subtype",
                                  width: 1170, height: 2532)
        try writeImage(screenshotGraphic(width: screenshot.width, height: screenshot.height),
                       to: directory.appendingPathComponent(screenshot.filename), fixture: screenshot)
        fixtures.append(screenshot)
        try await makeVideo(at: directory.appendingPathComponent("14-disposable-moving-water.mov"), directory: directory)
        fixtures.append(Fixture(filename: "14-disposable-moving-water.mov", title: "Moving water", captureDate: now,
                                latitude: nil, longitude: nil, kind: "playable synthetic video with low-volume tone",
                                width: 720, height: 1080))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(fixtures).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
        print("Generated \(fixtures.count) disposable files in \(directory.path)")
    }
}
