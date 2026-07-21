import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1_024
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: size * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fatalError("Could not create icon context")
}

let canvas = CGRect(x: 0, y: 0, width: size, height: size)
context.setFillColor(CGColor(red: 0.025, green: 0.075, blue: 0.060, alpha: 1))
context.fill(canvas)

let ringRect = CGRect(x: 142, y: 142, width: 740, height: 740)
context.setStrokeColor(CGColor(red: 0.31, green: 0.98, blue: 0.58, alpha: 1))
context.setLineWidth(76)
context.strokeEllipse(in: ringRect)

context.setLineCap(.round)
context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.setLineWidth(34)
context.move(to: CGPoint(x: 512, y: 512))
context.addLine(to: CGPoint(x: 512, y: 678))
context.move(to: CGPoint(x: 512, y: 512))
context.addLine(to: CGPoint(x: 648, y: 423))
context.strokePath()

context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.fillEllipse(in: CGRect(x: 476, y: 476, width: 72, height: 72))

context.setStrokeColor(CGColor(red: 0.31, green: 0.98, blue: 0.58, alpha: 1))
context.setLineWidth(30)
context.move(to: CGPoint(x: 512, y: 800))
context.addLine(to: CGPoint(x: 512, y: 744))
context.strokePath()

// Three small bars suggest split times without relying on a font at generation time.
let barWidths: [CGFloat] = [260, 200, 140]
for (index, width) in barWidths.enumerated() {
    let y = CGFloat(310 - (index * 54))
    let rect = CGRect(x: (CGFloat(size) - width) / 2, y: y, width: width, height: 20)
    context.fill(rect)
}

guard let image = context.makeImage() else {
    fatalError("Could not create icon image")
}

let destinationURL = URL(fileURLWithPath: "MilePace/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
guard let destination = CGImageDestinationCreateWithURL(
    destinationURL as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    fatalError("Could not create PNG destination")
}

CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("Could not write app icon")
}
