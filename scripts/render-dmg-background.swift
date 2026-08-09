#!/usr/bin/swift

import AppKit
import Foundation

enum RenderError: Error, CustomStringConvertible {
    case usage
    case invalidChannel(String)
    case unreadableImage(String)
    case bitmapCreation
    case pngEncoding

    var description: String {
        switch self {
        case .usage:
            return "Usage: render-dmg-background.swift --input SOURCE.png --output BACKGROUND.png --channel stable|beta"
        case let .invalidChannel(channel):
            return "Channel must be stable or beta, not: \(channel)"
        case let .unreadableImage(path):
            return "Unable to read source image: \(path)"
        case .bitmapCreation:
            return "Unable to create the Retina background bitmap"
        case .pngEncoding:
            return "Unable to encode the Retina background as PNG"
        }
    }
}

func option(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
        return nil
    }
    return arguments[index + 1]
}

func drawCenteredText(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.72)
    shadow.shadowBlurRadius = 8
    shadow.shadowOffset = NSSize(width: 0, height: -2)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .shadow: shadow,
    ]
    let size = text.size(withAttributes: attributes)
    text.draw(
        at: NSPoint(x: (1_440 - size.width) / 2, y: y),
        withAttributes: attributes
    )
}

func drawArrow(channel: String) {
    let arrowColor = channel == "beta"
        ? NSColor(calibratedRed: 1.0, green: 0.68, blue: 0.16, alpha: 0.94)
        : NSColor(calibratedRed: 0.17, green: 0.75, blue: 1.0, alpha: 0.94)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.58)
    shadow.shadowBlurRadius = 8
    shadow.shadowOffset = NSSize(width: 0, height: -2)
    shadow.set()

    let path = NSBezierPath()
    path.lineWidth = 9
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.move(to: NSPoint(x: 520, y: 458))
    path.line(to: NSPoint(x: 920, y: 458))
    arrowColor.setStroke()
    path.stroke()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: 920, y: 458))
    head.line(to: NSPoint(x: 875, y: 492))
    head.line(to: NSPoint(x: 875, y: 424))
    head.close()
    arrowColor.setFill()
    head.fill()
}

func drawBetaBadge() {
    let badge = NSRect(x: 1_247, y: 814, width: 126, height: 50)
    let path = NSBezierPath(roundedRect: badge, xRadius: 25, yRadius: 25)
    NSColor(calibratedRed: 1.0, green: 0.66, blue: 0.13, alpha: 0.96).setFill()
    path.fill()

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 23, weight: .bold),
        .foregroundColor: NSColor(calibratedWhite: 0.06, alpha: 1),
        .kern: 1.8,
    ]
    let text = "BETA"
    let size = text.size(withAttributes: attributes)
    text.draw(
        at: NSPoint(
            x: badge.midX - size.width / 2,
            y: badge.midY - size.height / 2 + 1
        ),
        withAttributes: attributes
    )
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard
        let inputPath = option("--input", in: arguments),
        let outputPath = option("--output", in: arguments),
        let channel = option("--channel", in: arguments)
    else {
        throw RenderError.usage
    }
    guard channel == "stable" || channel == "beta" else {
        throw RenderError.invalidChannel(channel)
    }
    guard let source = NSImage(contentsOfFile: inputPath) else {
        throw RenderError.unreadableImage(inputPath)
    }
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 1_440,
        pixelsHigh: 900,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw RenderError.bitmapCreation
    }
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw RenderError.bitmapCreation
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    source.draw(
        in: NSRect(x: 0, y: 0, width: 1_440, height: 900),
        from: NSRect(origin: .zero, size: source.size),
        operation: .copy,
        fraction: 1
    )

    drawCenteredText(
        "Drag WindowRanger to Applications",
        y: 820,
        font: NSFont.systemFont(ofSize: 34, weight: .semibold),
        color: .white
    )
    drawArrow(channel: channel)
    if channel == "beta" {
        drawBetaBadge()
    }
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw RenderError.pngEncoding
    }
    try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
    print("Rendered \(channel) DMG background: \(outputPath)")
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
