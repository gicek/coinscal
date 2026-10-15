// DMG volume icon: the system removable disk icon (the default icon of a mounted DMG) with the center arrow
// erased and the logo mark laid over it.
// Usage: swift scripts/dmg/render-volume-icon.swift <logo PNG with transparent background> <output 1024 PNG>
// The base image comes from the system and its look changes with the macOS version; coordinates were measured
// on the 1024×1024 Removable.icns.

import AppKit
import ImageIO
import UniformTypeIdentifiers

let baseIcon = "/System/Library/Extensions/IOStorageFamily.kext/Contents/Resources/Removable.icns"
let size = 1024

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write("Usage: render-volume-icon.swift <logo.png> <output.png>\n".data(using: .utf8)!)
    exit(2)
}

func cgImage(_ path: String) -> CGImage {
    guard let image = NSImage(contentsOfFile: path) else { fatalError("Cannot read: \(path)") }
    var rect = CGRect(x: 0, y: 0, width: size, height: size)
    guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { fatalError("Cannot decode: \(path)") }
    return cg
}

var pixels = [UInt8](repeating: 0, count: size * size * 4)
let ctx = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .high
ctx.draw(cgImage(baseIcon), in: CGRect(x: 0, y: 0, width: size, height: size))

// Erase the arrow: fill each row of the arrow area by linearly interpolating the disk face colors on the left
// and right (the face is a vertical gradient with slight left/right differences)
// Bitmap row 0 is the top of the image
let erase = (left: 300, right: 724, top: 240, bottom: 690)
for y in erase.top..<erase.bottom {
    let l = (y * size + erase.left) * 4, r = (y * size + erase.right) * 4
    for x in (erase.left + 1)..<erase.right {
        let t = Double(x - erase.left) / Double(erase.right - erase.left)
        for c in 0..<4 {
            let v = Double(pixels[l + c]) * (1 - t) + Double(pixels[r + c]) * t
            pixels[(y * size + x) * 4 + c] = UInt8(v.rounded())
        }
    }
}

// Center the logo mark on the upper part of the disk face (the bottom is the metal strip); CG origin is at
// the lower left
let logoSide: CGFloat = 560
let faceCenter = CGPoint(x: 512, y: CGFloat(size) - 452)
ctx.draw(cgImage(CommandLine.arguments[1]),
         in: CGRect(x: faceCenter.x - logoSide / 2, y: faceCenter.y - logoSide / 2, width: logoSide, height: logoSide))

let out = URL(fileURLWithPath: CommandLine.arguments[2])
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("Write failed: \(out.path)") }
