// SPDX-License-Identifier: GPL-3.0-or-later
//
// Draws Akvavit's app icon (option C from the design canvas: a game controller
// filled with a wireframe grid), 1024 × 1024 PNGs:
//
//   swift scripts/make-app-icon.swift App
//
// - App/AppIcon.icon/Assets: the controller alone on transparent ground, light
//   and dark, as the Icon Composer file's layers (iOS 26 and later draws icons
//   from it; its icon.json holds the background and which layer shows when);
// - App/Assets.xcassets/AppIcon.appiconset: the whole icon in the three
//   appearances, the fallback for older systems.
//
// The drawing is in the canvas's units: the controller in a 200 × 140 box,
// scaled by 4 and placed at (112, 232) in the 1024 square, y pointing down.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Look {
    let top: UInt32, bottom: UInt32       // background, top to bottom
    let mesh: UInt32, meshAlpha: CGFloat
    let line: UInt32
    let detailFill: UInt32
}

let looks: [(file: String, look: Look)] = [
    ("AppIcon-Light.png", Look(top: 0xFBF8FF, bottom: 0xE9E0FF, mesh: 0xA88AE8, meshAlpha: 1,
                               line: 0x4F24A8, detailFill: 0xF3EEFF)),
    ("AppIcon-Dark.png", Look(top: 0x2D1361, bottom: 0x150930, mesh: 0x8F5CFF, meshAlpha: 0.8,
                              line: 0xE6D4FF, detailFill: 0x1F0D46)),
    // Tinted: grey levels only; iOS colours them with the person's tint.
    ("AppIcon-Tinted.png", Look(top: 0x000000, bottom: 0x000000, mesh: 0x6E6E6E, meshAlpha: 1,
                                line: 0xFFFFFF, detailFill: 0x000000)),
]

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// The controller's outline.
func body() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 62, y: 22))
    p.addLine(to: CGPoint(x: 138, y: 22))
    p.addCurve(to: CGPoint(x: 189, y: 72), control1: CGPoint(x: 168, y: 22), control2: CGPoint(x: 184, y: 42))
    p.addLine(to: CGPoint(x: 195, y: 106))
    p.addCurve(to: CGPoint(x: 164, y: 123), control1: CGPoint(x: 198, y: 126), control2: CGPoint(x: 178, y: 136))
    p.addLine(to: CGPoint(x: 143, y: 102))
    p.addLine(to: CGPoint(x: 57, y: 102))
    p.addLine(to: CGPoint(x: 36, y: 123))
    p.addCurve(to: CGPoint(x: 5, y: 106), control1: CGPoint(x: 22, y: 136), control2: CGPoint(x: 2, y: 126))
    p.addLine(to: CGPoint(x: 11, y: 72))
    p.addCurve(to: CGPoint(x: 62, y: 22), control1: CGPoint(x: 16, y: 42), control2: CGPoint(x: 32, y: 22))
    p.closeSubpath()
    return p
}

/// D-pad, the four buttons and the two sticks.
func details() -> CGPath {
    let p = CGMutablePath()
    p.addLines(between: [(52, 42), (64, 42), (64, 48), (70, 48), (70, 60), (64, 60), (64, 66),
                         (52, 66), (52, 60), (46, 60), (46, 48), (52, 48)].map { CGPoint(x: $0.0, y: $0.1) })
    p.closeSubpath()
    for (x, y) in [(142.0, 41.0), (155, 54), (142, 67), (129, 54)] {
        p.addEllipse(in: CGRect(x: x - 5.5, y: y - 5.5, width: 11, height: 11))
    }
    for (x, y) in [(83.0, 79.0), (117, 79)] {
        p.addEllipse(in: CGRect(x: x - 9.5, y: y - 9.5, width: 19, height: 19))
    }
    return p
}

/// The grid inside the outline.
func mesh() -> CGPath {
    let p = CGMutablePath()
    for y in stride(from: 31.0, through: 130, by: 9) {
        p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: 200, y: y))
    }
    for x in stride(from: 10.0, through: 190, by: 10) {
        p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: 140))
    }
    return p
}

/// The whole icon, or only the controller on transparent ground (`background` false).
func draw(_ look: Look, background: Bool = true, to url: URL) throws {
    let size = 1024
    let alpha = background ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: alpha.rawValue) else {
        throw CocoaError(.fileWriteUnknown)
    }
    // y down, as on the canvas.
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: 1, y: -1)

    if background {
        let gradient = CGGradient(colorsSpace: nil, colors: [color(look.top), color(look.bottom)] as CFArray,
                                  locations: [0, 1])!
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size), options: [])
    }

    context.translateBy(x: 112, y: 232)
    context.scaleBy(x: 4, y: 4)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    context.saveGState()
    context.addPath(body())
    context.clip()
    context.addPath(mesh())
    context.setStrokeColor(color(look.mesh, look.meshAlpha))
    context.setLineWidth(1.1)
    context.strokePath()
    context.restoreGState()

    context.addPath(body())
    context.setStrokeColor(color(look.line))
    context.setLineWidth(3.4)
    context.strokePath()

    context.addPath(details())
    context.setFillColor(color(look.detailFill))
    context.setStrokeColor(color(look.line))
    context.setLineWidth(2.6)
    context.drawPath(using: .fillStroke)

    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

let app = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "App")
let catalog = app.appendingPathComponent("Assets.xcassets/AppIcon.appiconset")
let layers = app.appendingPathComponent("AppIcon.icon/Assets")
for folder in [catalog, layers] {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
}
for (file, look) in looks {
    try draw(look, to: catalog.appendingPathComponent(file))
    print("wrote", file)
}
for (file, look) in [("controller-light.png", looks[0].look), ("controller-dark.png", looks[1].look)] {
    try draw(look, background: false, to: layers.appendingPathComponent(file))
    print("wrote", file)
}
