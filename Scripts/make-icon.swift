// Renders Watch/Assets.xcassets/AppIcon.appiconset/AppIcon.png (1024x1024).
//
// The glyph is drawn by hand on purpose: Apple's SF Symbols licence does not permit
// using the symbols in app icons, so a mic is composed from primitives instead.
//
//   swift Scripts/make-icon.swift Watch/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit
import CoreGraphics
import Foundation

let side = 1024
let out = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Watch/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(
          data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
else { fatalError("could not create bitmap context") }

let w = CGFloat(side)
let cx = w / 2

// Background: warm coral, matching AccentColor.colorset.
let gradient = CGGradient(
    colorsSpace: space,
    colors: [
        CGColor(srgbRed: 1.00, green: 0.56, blue: 0.42, alpha: 1),
        CGColor(srgbRed: 0.89, green: 0.31, blue: 0.27, alpha: 1),
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: w), end: CGPoint(x: 0, y: 0), options: [])

ctx.setFillColor(.white)
ctx.setStrokeColor(.white)

// Mic glyph, laid out so the cradle ends meet the capsule at its lower half and the
// stem lands inside the cradle's stroke — otherwise the arc reads as ears and the stem
// floats. Everything sits well inside the circular mask watchOS applies.
let bodyWidth: CGFloat = 168
let bodyHeight: CGFloat = 310
let cradleCenterY: CGFloat = 594
let cradleRadius: CGFloat = 190
let strokeWidth: CGFloat = 46

// Capsule.
let body = CGRect(x: cx - bodyWidth / 2, y: 494, width: bodyWidth, height: bodyHeight)
ctx.addPath(CGPath(roundedRect: body, cornerWidth: bodyWidth / 2, cornerHeight: bodyWidth / 2, transform: nil))
ctx.fillPath()

// Cradle: a U passing under the capsule, ending level with its lower half.
ctx.setLineWidth(strokeWidth)
ctx.setLineCap(.round)
ctx.addArc(
    center: CGPoint(x: cx, y: cradleCenterY),
    radius: cradleRadius,
    startAngle: .pi,
    endAngle: 2 * .pi,
    // Counterclockwise in CoreGraphics' y-up space is what sweeps *under* the capsule;
    // clockwise here arcs over the top and reads as ears.
    clockwise: false
)
ctx.strokePath()

// Stem, overlapping the cradle stroke so the two read as one shape.
ctx.fill(CGRect(x: cx - strokeWidth / 2, y: 274, width: strokeWidth, height: 120))

// Base.
ctx.addPath(CGPath(roundedRect: CGRect(x: cx - 132, y: 230, width: 264, height: 50),
                   cornerWidth: 25, cornerHeight: 25, transform: nil))
ctx.fillPath()

guard let image = ctx.makeImage() else { fatalError("could not render image") }
let rep = NSBitmapImageRep(cgImage: image)
rep.size = NSSize(width: w, height: w)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("could not encode PNG") }
try png.write(to: URL(fileURLWithPath: out))
print("wrote \(out) (\(side)x\(side), \(png.count) bytes)")
