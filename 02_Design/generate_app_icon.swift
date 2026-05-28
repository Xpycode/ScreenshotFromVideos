//
//  generate_app_icon.swift
//  Stills From Video — placeholder app icon generator
//
//  Renders a 1024×1024 PNG and sips-resizes to all 10 macOS AppIcon slot
//  sizes, dropping the results into the AppIcon.appiconset folder.
//
//  Visual:
//   • dark navy → slate vertical gradient on rounded-corner canvas
//   • light-gray film strip (lower center) with sprocket holes punched
//     through and three dark frame windows inside
//   • one frame DETACHED above the strip, warm-amber, slight rotation,
//     soft drop shadow — reads as "this frame just got extracted"
//
//  Run with:  swift 02_Design/generate_app_icon.swift
//
//  This is a placeholder. The polished icon should come from Claude Design
//  or a designer — see CLAUDE_DESIGN_PROMPT.md in this folder.
//

import AppKit
import Foundation

// MARK: - Output paths

let projectRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let iconset = projectRoot
    .appendingPathComponent("01_Project")
    .appendingPathComponent("ScreenshotFromVideos")
    .appendingPathComponent("Assets.xcassets")
    .appendingPathComponent("AppIcon.appiconset")
let masterURL = iconset.appendingPathComponent("icon_512x512@2x.png")

// MARK: - Render 1024 master

let canvas: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

guard let cg = NSGraphicsContext.current?.cgContext else {
    fatalError("No graphics context")
}
let space = CGColorSpaceCreateDeviceRGB()

// 1. Rounded-corner background gradient
let bgRect = CGRect(x: 0, y: 0, width: canvas, height: canvas)
let bgCorner: CGFloat = 180
cg.addPath(CGPath(roundedRect: bgRect, cornerWidth: bgCorner, cornerHeight: bgCorner, transform: nil))
cg.clip()

let bgColors = [
    CGColor(red: 0.10, green: 0.13, blue: 0.20, alpha: 1.0),
    CGColor(red: 0.16, green: 0.20, blue: 0.26, alpha: 1.0),
] as CFArray
let bgGradient = CGGradient(colorsSpace: space, colors: bgColors, locations: [0.0, 1.0])!
cg.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: 0, y: canvas),  // top
    end:   .zero,                     // bottom
    options: []
)

// 2. Filmstrip body (lower-center) with sprocket holes via even-odd fill
let stripWidth:  CGFloat = 540
let stripHeight: CGFloat = 680
let stripCenter = CGPoint(x: canvas / 2, y: 420)
let stripX = stripCenter.x - stripWidth  / 2
let stripY = stripCenter.y - stripHeight / 2     // Y-up — bottom of strip

let stripBody = CGPath(
    roundedRect: CGRect(x: stripX, y: stripY, width: stripWidth, height: stripHeight),
    cornerWidth: 40, cornerHeight: 40, transform: nil
)

// Sprocket holes — 5 per side, evenly spaced
let bandWidth: CGFloat = 70
let holeW:     CGFloat = 32
let holeH:     CGFloat = 56
let holeCount = 5
let firstHoleY = stripY + 60
let lastHoleY  = stripY + stripHeight - 60 - holeH
let yPitch     = (lastHoleY - firstHoleY) / CGFloat(holeCount - 1)
let leftHoleX  = stripX + (bandWidth - holeW) / 2
let rightHoleX = stripX + stripWidth - bandWidth + (bandWidth - holeW) / 2

let combined = CGMutablePath()
combined.addPath(stripBody)
for i in 0 ..< holeCount {
    let y = firstHoleY + CGFloat(i) * yPitch
    combined.addPath(CGPath(
        roundedRect: CGRect(x: leftHoleX,  y: y, width: holeW, height: holeH),
        cornerWidth: 10, cornerHeight: 10, transform: nil
    ))
    combined.addPath(CGPath(
        roundedRect: CGRect(x: rightHoleX, y: y, width: holeW, height: holeH),
        cornerWidth: 10, cornerHeight: 10, transform: nil
    ))
}
cg.setFillColor(CGColor(red: 0.82, green: 0.84, blue: 0.87, alpha: 1.0))  // light gray
cg.addPath(combined)
cg.fillPath(using: .evenOdd)

// 3. Three darker frame windows inside the strip
let frameW:    CGFloat = 340
let frameH:    CGFloat = 170
let frameX     = stripCenter.x - frameW / 2
let frameGap:  CGFloat = 30
let framesTotalH = 3 * frameH + 2 * frameGap
let firstFrameY  = stripY + (stripHeight - framesTotalH) / 2
let frameColor   = CGColor(red: 0.16, green: 0.20, blue: 0.26, alpha: 1.0)  // matches bg bottom
cg.setFillColor(frameColor)
for i in 0 ..< 3 {
    let y = firstFrameY + CGFloat(i) * (frameH + frameGap)
    cg.addPath(CGPath(
        roundedRect: CGRect(x: frameX, y: y, width: frameW, height: frameH),
        cornerWidth: 14, cornerHeight: 14, transform: nil
    ))
}
cg.fillPath()

// 4. Detached "extracted" frame — warm amber, rotated, with soft shadow
let extW:       CGFloat = 380
let extH:       CGFloat = 220
let extCenter   = CGPoint(x: stripCenter.x + 80, y: 880)   // above strip, right of center
let extRect     = CGRect(
    x: extCenter.x - extW / 2,
    y: extCenter.y - extH / 2,
    width: extW, height: extH
)

cg.saveGState()
// Rotate around the detached frame's center for a "just-tossed-out" feel
cg.translateBy(x: extCenter.x, y: extCenter.y)
cg.rotate(by: -.pi / 30)        // ~−6°
cg.translateBy(x: -extCenter.x, y: -extCenter.y)

// Soft shadow under the lifted frame
cg.setShadow(
    offset: CGSize(width: 0, height: -18),
    blur: 32,
    color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55)
)
cg.setFillColor(CGColor(red: 0.96, green: 0.81, blue: 0.36, alpha: 1.0))  // warm amber #f5cf5c
cg.addPath(CGPath(
    roundedRect: extRect,
    cornerWidth: 24, cornerHeight: 24, transform: nil
))
cg.fillPath()
cg.restoreGState()

image.unlockFocus()

// MARK: - Save master + resize via sips

guard let tiff = image.tiffRepresentation,
      let rep  = NSBitmapImageRep(data: tiff),
      let png  = rep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to encode PNG")
}
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try png.write(to: masterURL)
print("Wrote master: \(masterURL.path)")

let slots: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
]

for (px, name) in slots {
    let url = iconset.appendingPathComponent(name)
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    proc.arguments = ["-z", "\(px)", "\(px)", masterURL.path, "--out", url.path]
    proc.standardOutput = Pipe()
    proc.standardError  = Pipe()
    try? proc.run()
    proc.waitUntilExit()
    print(proc.terminationStatus == 0 ? "Wrote \(name) (\(px)px)" : "FAILED \(name)")
}

print("Done.")
