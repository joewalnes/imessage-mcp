#!/usr/bin/env swift

// Generates a macOS .iconset directory of PNGs at all required sizes.
// Pipe through `iconutil -c icns <iconset>` to produce a final .icns.
//
// Usage:
//   swift Scripts/make_icon.swift <output-iconset-dir>
//
// The icon design: rounded-square with an iMessage-blue gradient,
// a white speech bubble centered, and three small dots inside it
// (typing-indicator nod).

import Foundation
import CoreGraphics
import ImageIO
import AppKit

// MARK: - Drawing

func drawIcon(size px: Int) -> CGImage? {
    let s = CGFloat(px)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: px,
        height: px,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // macOS Big Sur+ icon corner radius is ~22.5% of the side length.
    let corner = s * 0.2237

    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let bgPath = CGPath(
        roundedRect: rect,
        cornerWidth: corner,
        cornerHeight: corner,
        transform: nil
    )

    // Background gradient (iMessage-ish blue, top-light → bottom-deep).
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let gradColors = [
        CGColor(red: 0.30, green: 0.78, blue: 1.00, alpha: 1.0), // top
        CGColor(red: 0.04, green: 0.48, blue: 1.00, alpha: 1.0), // bottom
    ] as CFArray
    let gradient = CGGradient(
        colorsSpace: cs,
        colors: gradColors,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: s),
        end: CGPoint(x: 0, y: 0),
        options: []
    )
    ctx.restoreGState()

    // Speech bubble (white, with a small tail).
    let bubbleRect = CGRect(
        x: s * 0.18,
        y: s * 0.30,
        width: s * 0.64,
        height: s * 0.46
    )
    let bubbleCorner = s * 0.13

    let bubble = CGMutablePath()
    bubble.addRoundedRect(
        in: bubbleRect,
        cornerWidth: bubbleCorner,
        cornerHeight: bubbleCorner
    )
    // Tail on the bottom-left.
    let tailTop = CGPoint(x: s * 0.30, y: s * 0.32)
    let tailTip = CGPoint(x: s * 0.20, y: s * 0.20)
    let tailBase = CGPoint(x: s * 0.40, y: s * 0.32)
    bubble.move(to: tailTop)
    bubble.addQuadCurve(to: tailTip, control: CGPoint(x: s * 0.24, y: s * 0.27))
    bubble.addQuadCurve(to: tailBase, control: CGPoint(x: s * 0.34, y: s * 0.27))
    bubble.closeSubpath()

    // Subtle drop shadow for the bubble.
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -s * 0.008),
        blur: s * 0.025,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.18)
    )
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.addPath(bubble)
    ctx.fillPath()
    ctx.restoreGState()

    // Three dots inside the bubble (typing-indicator).
    let dotY = bubbleRect.midY
    let dotR = s * 0.045
    let dotSpacing = s * 0.13
    let centerX = bubbleRect.midX
    let dotColor = CGColor(red: 0.04, green: 0.48, blue: 1.00, alpha: 1.0)
    ctx.setFillColor(dotColor)
    for dx in [-dotSpacing, 0, dotSpacing] {
        let r = CGRect(
            x: centerX + dx - dotR,
            y: dotY - dotR,
            width: dotR * 2,
            height: dotR * 2
        )
        ctx.fillEllipse(in: r)
    }

    return ctx.makeImage()
}

// MARK: - Output

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL,
        "public.png" as CFString,
        1,
        nil
    ) else {
        throw NSError(
            domain: "make_icon",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "CGImageDestinationCreateWithURL failed for \(url.path)"]
        )
    }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) {
        throw NSError(
            domain: "make_icon",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "CGImageDestinationFinalize failed for \(url.path)"]
        )
    }
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: make_icon.swift <output-iconset-dir>\n".utf8))
    exit(2)
}
let outDir = args[1]

let fm = FileManager.default
try? fm.removeItem(atPath: outDir)
try fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// Required entries for `iconutil -c icns`.
let entries: [(name: String, px: Int)] = [
    ("icon_16x16.png",      16),
    ("icon_16x16@2x.png",   32),
    ("icon_32x32.png",      32),
    ("icon_32x32@2x.png",   64),
    ("icon_128x128.png",   128),
    ("icon_128x128@2x.png",256),
    ("icon_256x256.png",   256),
    ("icon_256x256@2x.png",512),
    ("icon_512x512.png",   512),
    ("icon_512x512@2x.png",1024),
]

for (name, px) in entries {
    guard let img = drawIcon(size: px) else {
        FileHandle.standardError.write(Data("failed to render \(name)\n".utf8))
        exit(1)
    }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    try writePNG(img, to: url)
}

print("Wrote \(entries.count) PNGs to \(outDir)")
