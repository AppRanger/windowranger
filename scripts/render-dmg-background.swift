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
            return "Unable to create the background bitmap"
        case .pngEncoding:
            return "Unable to encode the background as PNG"
        }
    }
}

func option(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
        return nil
    }
    return arguments[index + 1]
}

let canvasWidth: CGFloat = 720
let canvasHeight: CGFloat = 450

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
        at: NSPoint(x: (canvasWidth - size.width) / 2, y: y),
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
    path.lineWidth = 4.5
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.move(to: NSPoint(x: 260, y: 229))
    path.line(to: NSPoint(x: 460, y: 229))
    arrowColor.setStroke()
    path.stroke()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: 460, y: 229))
    head.line(to: NSPoint(x: 437.5, y: 246))
    head.line(to: NSPoint(x: 437.5, y: 212))
    head.close()
    arrowColor.setFill()
    head.fill()
}

func drawBetaBadge() {
    let badge = NSRect(x: 623.5, y: 407, width: 63, height: 25)
    let path = NSBezierPath(roundedRect: badge, xRadius: 12.5, yRadius: 12.5)
    NSColor(calibratedRed: 1.0, green: 0.66, blue: 0.13, alpha: 0.96).setFill()
    path.fill()

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11.5, weight: .bold),
        .foregroundColor: NSColor(calibratedWhite: 0.06, alpha: 1),
        .kern: 0.9,
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

func drawLabelBackings(channel: String) {
    let fill = channel == "beta"
        ? NSColor(calibratedRed: 0.92, green: 0.96, blue: 1.0, alpha: 0.9)
        : NSColor(calibratedRed: 0.9, green: 0.95, blue: 1.0, alpha: 0.9)
    let stroke = channel == "beta"
        ? NSColor(calibratedRed: 1.0, green: 0.68, blue: 0.16, alpha: 0.72)
        : NSColor(calibratedRed: 0.17, green: 0.75, blue: 1.0, alpha: 0.72)

    for rect in [
        NSRect(x: 97, y: 128, width: 156, height: 30),
        NSRect(x: 467, y: 128, width: 156, height: 30),
    ] {
        let path = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
        fill.setFill()
        path.fill()
        path.lineWidth = 1
        stroke.setStroke()
        path.stroke()
    }
}

func retinaPath(for outputPath: String) -> String {
    let url = URL(fileURLWithPath: outputPath)
    let stem = url.deletingPathExtension().path
    let pathExtension = url.pathExtension
    return pathExtension.isEmpty ? "\(stem)@2x" : "\(stem)@2x.\(pathExtension)"
}

func render(source: NSImage, channel: String, scale: Int, outputPath: String) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasWidth) * scale,
        pixelsHigh: Int(canvasHeight) * scale,
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
    context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    source.draw(
        in: NSRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight),
        from: NSRect(origin: .zero, size: source.size),
        operation: .copy,
        fraction: 1
    )

    drawLabelBackings(channel: channel)
    drawCenteredText(
        "Drag WindowRanger to Applications",
        y: 410,
        font: NSFont.systemFont(ofSize: 17, weight: .semibold),
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
    let retinaOutputPath = retinaPath(for: outputPath)
    try render(source: source, channel: channel, scale: 1, outputPath: outputPath)
    try render(source: source, channel: channel, scale: 2, outputPath: retinaOutputPath)
    print("Rendered \(channel) DMG backgrounds: \(outputPath), \(retinaOutputPath)")
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
