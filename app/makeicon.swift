// Generate a native macOS squircle app icon from icon.png.
// The source is a green disc with a white "y"; this repaints the background as a
// rounded-square (Apple grid: 824/1024 safe area) and keeps the white glyph.
//   swift app/makeicon.swift icon.png out.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let srcPath = args[1], outPath = args[2]
let S = 1024

guard let srcURL = CGImageSourceCreateWithURL(URL(fileURLWithPath: srcPath) as CFURL, nil),
    let srcCG = CGImageSourceCreateImageAtIndex(srcURL, 0, nil)
else { fatalError("cannot load \(srcPath)") }

let w = srcCG.width, h = srcCG.height
let cs = CGColorSpaceCreateDeviceRGB()
let bpr = w * 4
var buf = [UInt8](repeating: 0, count: h * bpr)
let read = CGContext(
    data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr, space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
read.draw(srcCG, in: CGRect(x: 0, y: 0, width: w, height: h))

// White "y" alpha = contrast on the min channel (white -> high, green -> low).
// Average the opaque non-white pixels to recover the brand green.
var ymask = [UInt8](repeating: 0, count: h * bpr)
var gr = 0.0, gg = 0.0, gb = 0.0, gn = 0.0
for i in 0..<(w * h) {
    let r = Double(buf[i * 4]), g = Double(buf[i * 4 + 1]), b = Double(buf[i * 4 + 2]),
        a = Double(buf[i * 4 + 3])
    let mn = min(r, min(g, b))
    let ya = max(0, min(1, (mn - 80) / (255 - 80))) * (a / 255)
    ymask[i * 4] = 255; ymask[i * 4 + 1] = 255; ymask[i * 4 + 2] = 255
    ymask[i * 4 + 3] = UInt8(ya * 255)
    if a > 200, !(r > 200 && g > 200 && b > 200) { gr += r; gg += g; gb += b; gn += 1 }
}
let green: (CGFloat, CGFloat, CGFloat) =
    gn > 0 ? (CGFloat(gr / gn / 255), CGFloat(gg / gn / 255), CGFloat(gb / gn / 255)) : (0.55, 0.78, 0.24)
FileHandle.standardError.write("green=\(green)\n".data(using: .utf8)!)

let ymCG = CGContext(
    data: &ymask, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr, space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!

let out = CGContext(
    data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let inset = CGFloat(S) * 100.0 / 1024.0
let side = CGFloat(S) - 2 * inset
let rect = CGRect(x: inset, y: inset, width: side, height: side)
let radius = side * 0.2237  // Apple squircle corner ratio
out.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
out.setFillColor(red: green.0, green: green.1, blue: green.2, alpha: 1)
out.fillPath()
// The glyph filled the source disc; draw it slightly inset inside the squircle.
let gInset = side * 0.16
let gRect = rect.insetBy(dx: gInset, dy: gInset)
out.draw(ymCG, in: gRect)

let img = out.makeImage()!
let dst = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dst, img, nil)
CGImageDestinationFinalize(dst)
FileHandle.standardError.write("wrote \(outPath)\n".data(using: .utf8)!)
