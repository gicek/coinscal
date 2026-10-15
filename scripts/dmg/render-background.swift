// DMG window background: Bitcoin monthly candlesticks (log price scale) plus a "rising candlesticks" drag
// illustration in the middle.
// Usage: swift scripts/dmg/render-background.swift <output directory>
// Writes background.png (1x) and background@2x.png; make-dmg.sh combines them into a multi-resolution TIFF.
// Canvas and icon coordinates must match the Finder layout in make-dmg.sh (top-left origin, in pt).

import AppKit
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvas = CGSize(width: 660, height: 420)
let appIcon = CGPoint(x: 180, y: 250)      // Coinscal.app: lower left
let folderIcon = CGPoint(x: 480, y: 170)   // Applications: upper right

// Price axis on the right (log scale)
let axisX: CGFloat = 598
let priceTicks: [Double] = [3_000, 20_000, 60_000, 120_000, 300_000, 500_000, 800_000, 1_000_000]
let priceTop: CGFloat = 22, priceBottom: CGFloat = 392
func priceY(_ p: Double) -> CGFloat {
    let lo = log10(3_000.0), hi = log10(1_000_000.0)
    return priceBottom - CGFloat((log10(p) - lo) / (hi - lo)) * (priceBottom - priceTop)
}

// BTC/USD monthly closes (approximate, from 2019-01); each open is the previous close, wicks are estimated
// from the monthly range
let monthlyCloses: [Double] = [
    3_450, 3_820, 4_100, 5_320, 8_570, 10_820, 10_080, 9_600, 8_290, 9_150, 7_560, 7_190,          // 2019
    9_350, 8_600, 6_420, 8_650, 9_450, 9_140, 11_350, 11_650, 10_780, 13_800, 19_700, 29_000,     // 2020
    33_100, 45_200, 58_900, 57_700, 37_300, 35_000, 41_500, 47_100, 43_800, 61_300, 57_000, 46_300, // 2021
    38_500, 43_200, 45_500, 37_700, 31_800, 19_900, 23_300, 20_000, 19_400, 20_500, 17_200, 16_500, // 2022
    23_100, 23_100, 28_500, 29_200, 27_200, 30_500, 29_200, 26_000, 27_000, 34_500, 37_700, 42_300, // 2023
    42_600, 61_200, 71_300, 60_600, 67_500, 62_700, 64_600, 59_000, 63_300, 70_200, 96_400, 93_400, // 2024
    102_400, 84_300, 82_500, 94_200, 104_600, 107_100, 115_700, 108_200, 114_000, 109_500, 90_400, 87_600, // 2025
]
let firstOpen: Double = 3_740
let firstYear = 2019

// Brand color #5546F5 (matches the icon)
func brand(_ alpha: CGFloat) -> CGColor { rgb(0x5546F5, alpha) }
func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }

func smoothstep(_ e0: CGFloat, _ e1: CGFloat, _ x: CGFloat) -> CGFloat {
    let t = min(max((x - e0) / (e1 - e0), 0), 1)
    return t * t * (3 - 2 * t)
}

// Opacity mask for the background candlesticks: fades out around the icons, file names, and illustration, and
// stays faintly visible elsewhere
func maskValue(_ p: CGPoint) -> CGFloat {
    var v: CGFloat = 1
    let label = CGPoint(x: 0, y: 18)   // Cutout center is 18pt below the icon so it covers the file name too
    for (c, r, depth) in [(appIcon + label, 128.0, 0.9), (folderIcon + label, 128.0, 0.9),
                          // The illustration runs diagonally; two circles cover all of it
                          (CGPoint(x: 300, y: 242), 105.0, 0.95), (CGPoint(x: 372, y: 196), 105.0, 0.95)] as [(CGPoint, CGFloat, CGFloat)] {
        let d = hypot(p.x - c.x, p.y - c.y)
        v *= 1 - depth * (1 - smoothstep(r * 0.4, r, d))
    }
    return v
}

func makeMask(scale: CGFloat) -> CGImage {
    let w = Int(canvas.width * scale), h = Int(canvas.height * scale)
    var pixels = [UInt8](repeating: 0, count: w * h)
    for py in 0..<h {
        for px in 0..<w {
            let p = CGPoint(x: (CGFloat(px) + 0.5) / scale, y: (CGFloat(py) + 0.5) / scale)
            pixels[py * w + px] = UInt8(min(max(maskValue(p), 0), 1) * 255)
        }
    }
    let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    return ctx.makeImage()!
}

// point.y is the vertical center of the text
func drawText(_ ctx: CGContext, _ text: String, font: NSFont, color: CGColor, at point: CGPoint, alignRight: Bool) {
    let attr = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor(cgColor: color)!])
    let line = CTLineCreateWithAttributedString(attr)
    let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    ctx.saveGState()
    ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)   // The coordinate system is already flipped to a top-left origin
    ctx.textPosition = CGPoint(x: alignRight ? point.x - width : point.x, y: point.y + font.capHeight / 2)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

// Grid: horizontal lines on the price ticks, vertical lines on each January
func drawGrid(_ ctx: CGContext, monthX: (Int) -> CGFloat) {
    ctx.setStrokeColor(brand(0.09))
    ctx.setLineWidth(0.75)
    for p in priceTicks {
        ctx.move(to: CGPoint(x: 0, y: priceY(p)))
        ctx.addLine(to: CGPoint(x: axisX, y: priceY(p)))
    }
    for year in 0..<(monthlyCloses.count / 12) {
        let x = monthX(year * 12) - 3.5
        ctx.move(to: CGPoint(x: x, y: 0))
        ctx.addLine(to: CGPoint(x: x, y: canvas.height))
    }
    ctx.strokePath()
}

func drawHistory(_ ctx: CGContext, monthX: (Int) -> CGFloat) {
    let bodyWidth: CGFloat = 3.6
    var open = firstOpen
    for (i, close) in monthlyCloses.enumerated() {
        // Monthly range: part of the open-close difference plus a base amount; up months get longer upper wicks,
// down months longer lower wicks
        let up = close >= open
        let swing = abs(close - open)
        let high = max(open, close) + swing * 0.18 + max(open, close) * (up ? 0.07 : 0.04)
        let low = min(open, close) - swing * 0.18 - min(open, close) * (up ? 0.04 : 0.07)
        let x = monthX(i)
        let color = up ? brand(0.30) : brand(0.24)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(0.8)
        ctx.move(to: CGPoint(x: x, y: priceY(high)))
        ctx.addLine(to: CGPoint(x: x, y: priceY(low)))
        ctx.strokePath()
        let top = priceY(max(open, close)), bottom = priceY(min(open, close))
        let body = CGRect(x: x - bodyWidth / 2, y: top, width: bodyWidth, height: max(bottom - top, 1))
        if up {
            ctx.setFillColor(color)
            ctx.fill(body)
        } else {
            // Down months are hollow: fill the inside with the background color first so the wick does not show through
            ctx.setFillColor(rgb(0xF6F5FE))
            ctx.fill(body)
            ctx.stroke(body.insetBy(dx: 0.4, dy: 0.4))
        }
        open = close
    }
}

func drawAxis(_ ctx: CGContext, monthX: (Int) -> CGFloat) {
    // Price axis backing and divider
    ctx.setFillColor(rgb(0xFFFFFF, 0.55))
    ctx.fill(CGRect(x: axisX, y: 0, width: canvas.width - axisX, height: canvas.height))
    ctx.setStrokeColor(brand(0.16))
    ctx.setLineWidth(0.75)
    ctx.move(to: CGPoint(x: axisX, y: 0))
    ctx.addLine(to: CGPoint(x: axisX, y: canvas.height))
    ctx.strokePath()

    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = Locale(identifier: "en_US")
    let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
    for p in priceTicks {
        let y = priceY(p)
        ctx.setStrokeColor(brand(0.30))
        ctx.move(to: CGPoint(x: axisX, y: y))
        ctx.addLine(to: CGPoint(x: axisX + 3, y: y))
        ctx.strokePath()
        drawText(ctx, formatter.string(from: NSNumber(value: p))!, font: font, color: rgb(0x5B5A7A, 0.75),
                 at: CGPoint(x: canvas.width - 7, y: y), alignRight: true)
    }

    // Latest close: brand-color price tag with a horizontal dashed line
    let last = monthlyCloses.last!
    let y = priceY(last)
    ctx.saveGState()
    ctx.setStrokeColor(brand(0.35))
    ctx.setLineWidth(0.75)
    ctx.setLineDash(phase: 0, lengths: [2, 2.5])
    ctx.move(to: CGPoint(x: monthX(monthlyCloses.count - 1) + 4, y: y))
    ctx.addLine(to: CGPoint(x: axisX, y: y))
    ctx.strokePath()
    ctx.restoreGState()
    let tag = CGRect(x: axisX + 2, y: y - 7, width: canvas.width - axisX - 5, height: 14)
    ctx.addPath(CGPath(roundedRect: tag, cornerWidth: 3, cornerHeight: 3, transform: nil))
    ctx.setFillColor(brand(0.9))
    ctx.fillPath()
    drawText(ctx, formatter.string(from: NSNumber(value: last))!,
             font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
             color: rgb(0xFFFFFF), at: CGPoint(x: canvas.width - 7, y: y), alignRight: true)

    // Years
    let yearFont = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .medium)
    for year in 0..<(monthlyCloses.count / 12) {
        drawText(ctx, String(firstYear + year), font: yearFont, color: rgb(0x5B5A7A, 0.45),
                 at: CGPoint(x: monthX(year * 12) - 1, y: canvas.height - 9), alignRight: false)
    }
}

// Catmull-Rom to cubic Bezier, giving a smooth curve through every point
func smoothPath(_ pts: [CGPoint]) -> CGMutablePath {
    let path = CGMutablePath()
    path.move(to: pts[0])
    for i in 0..<(pts.count - 1) {
        let p0 = pts[max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(i + 2, pts.count - 1)]
        let t: CGFloat = 1 / 6
        path.addCurve(to: p2,
                      control1: CGPoint(x: p1.x + (p2.x - p0.x) * t, y: p1.y + (p2.y - p0.y) * t),
                      control2: CGPoint(x: p2.x - (p3.x - p1.x) * t, y: p2.y - (p3.y - p1.y) * t))
    }
    return path
}

// Foreground illustration: candlesticks rising from the app (lower left) to the folder (upper right), with a
// smooth trend line ending in an arrow
func drawIllustration(_ ctx: CGContext) {
    struct Bar { var x, open, close, high, low: CGFloat }
    let bars: [Bar] = [
        Bar(x: 266, open: 274, close: 262, high: 256, low: 279),
        Bar(x: 287, open: 262, close: 251, high: 245, low: 266),
        Bar(x: 308, open: 251, close: 257, high: 247, low: 262),   // One pullback
        Bar(x: 329, open: 257, close: 238, high: 232, low: 260),
        Bar(x: 350, open: 238, close: 222, high: 215, low: 242),
        Bar(x: 371, open: 222, close: 205, high: 198, low: 226),
        Bar(x: 392, open: 205, close: 186, high: 178, low: 209),
    ]
    let width: CGFloat = 11

    // The trend line sweeps over the wicks (skipping the pullback to stay smooth), with a fading area fill below
    let curvePoints = [CGPoint(x: 246, y: 262)]
        + bars.enumerated().filter { $0.offset != 2 }.map { CGPoint(x: $0.element.x, y: $0.element.high - 7) }
        + [CGPoint(x: 408, y: 162)]
    let curve = smoothPath(curvePoints)
    let area = curve.mutableCopy()!
    area.addLine(to: CGPoint(x: 408, y: 290))
    area.addLine(to: CGPoint(x: 246, y: 290))
    area.closeSubpath()
    ctx.saveGState()
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.addPath(area)
    ctx.clip()
    let areaGradient = CGGradient(colorsSpace: sRGB, colors: [brand(0.18), brand(0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(areaGradient, start: CGPoint(x: 0, y: 165), end: CGPoint(x: 0, y: 285), options: [])
    // Fade out horizontally at both ends so there is no vertical cut edge
    ctx.setBlendMode(.destinationIn)
    let edges = CGGradient(colorsSpace: sRGB, colors: [brand(0), brand(1), brand(1), brand(0)] as CFArray,
                           locations: [0, 0.3, 0.75, 1])!
    ctx.drawLinearGradient(edges, start: CGPoint(x: 246, y: 0), end: CGPoint(x: 408, y: 0), options: [])
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    for (i, b) in bars.enumerated() {
        let up = b.close <= b.open      // Top-left origin: smaller y means higher price
        let strength = 0.45 + 0.55 * CGFloat(i) / CGFloat(bars.count - 1)  // Solider toward the right, so the direction reads
        let top = min(b.open, b.close), bottom = max(b.open, b.close)
        let body = CGRect(x: b.x - width / 2, y: top, width: width, height: bottom - top)

        ctx.setLineCap(.round)
        ctx.setLineWidth(1.6)
        ctx.setStrokeColor(brand(0.55 * strength + 0.1))
        ctx.move(to: CGPoint(x: b.x, y: b.high))
        ctx.addLine(to: CGPoint(x: b.x, y: top))
        ctx.move(to: CGPoint(x: b.x, y: bottom))
        ctx.addLine(to: CGPoint(x: b.x, y: b.low))
        ctx.strokePath()

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 5, color: brand(0.25 * strength))
        ctx.addPath(CGPath(roundedRect: body, cornerWidth: 2.5, cornerHeight: 2.5, transform: nil))
        if up {
            ctx.clip()
            let fill = CGGradient(colorsSpace: sRGB,
                                  colors: [rgb(0x7B6FFF, strength), rgb(0x5546F5, strength)] as CFArray,
                                  locations: [0, 1])!
            ctx.drawLinearGradient(fill, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom), options: [])
        } else {
            ctx.setFillColor(rgb(0xFFFFFF))
            ctx.fillPath()
            ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 0.75, dy: 0.75), cornerWidth: 2, cornerHeight: 2, transform: nil))
            ctx.setStrokeColor(brand(0.7 * strength))
            ctx.setLineWidth(1.5)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    // Trend line: fades in on the left, full color on the right
    ctx.saveGState()
    ctx.addPath(curve)
    ctx.setLineWidth(2.75)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let lineGradient = CGGradient(colorsSpace: sRGB,
                                  colors: [brand(0), rgb(0x8F84FF), rgb(0x5546F5)] as CFArray,
                                  locations: [0, 0.3, 1])!
    ctx.drawLinearGradient(lineGradient, start: curvePoints.first!, end: curvePoints.last!, options: [])
    ctx.restoreGState()

    // Arrow: a stroked V shape along the direction of the last trend segment
    let tip = CGPoint(x: 416, y: 157)
    let angle = atan2(tip.y - curvePoints[curvePoints.count - 2].y, tip.x - curvePoints[curvePoints.count - 2].x)
    let len: CGFloat = 11, spread: CGFloat = .pi / 4.6
    ctx.setStrokeColor(brand(1))
    ctx.setLineWidth(2.75)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: curvePoints.last!)
    ctx.addLine(to: tip)
    ctx.move(to: CGPoint(x: tip.x - len * cos(angle - spread), y: tip.y - len * sin(angle - spread)))
    ctx.addLine(to: tip)
    ctx.addLine(to: CGPoint(x: tip.x - len * cos(angle + spread), y: tip.y - len * sin(angle + spread)))
    ctx.strokePath()
}

func render(scale: CGFloat, to url: URL) {
    let w = Int(canvas.width * scale), h = Int(canvas.height * scale)
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // Base color: near white to a very light brand purple
    let base = CGGradient(colorsSpace: sRGB, colors: [rgb(0xFCFCFF), rgb(0xF3F2FE)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(base, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: 0), options: [])

    // Flip to a top-left origin
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: scale, y: -scale)

    let chartLeft: CGFloat = 12, chartRight = axisX - 10
    let step = (chartRight - chartLeft) / CGFloat(monthlyCloses.count - 1)
    let monthX = { (i: Int) in chartLeft + CGFloat(i) * step }

    ctx.saveGState()
    // The mask image is stored in bitmap row order, so flip back temporarily in the flipped coordinate system
    ctx.translateBy(x: 0, y: canvas.height)
    ctx.scaleBy(x: 1, y: -1)
    ctx.clip(to: CGRect(origin: .zero, size: canvas), mask: makeMask(scale: scale))
    ctx.translateBy(x: 0, y: canvas.height)
    ctx.scaleBy(x: 1, y: -1)
    drawGrid(ctx, monthX: monthX)
    drawHistory(ctx, monthX: monthX)
    ctx.restoreGState()

    drawAxis(ctx, monthX: monthX)
    drawIllustration(ctx)

    let image = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, [kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { fatalError("Write failed: \(url.path)") }
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("Usage: render-background.swift <output directory>\n".data(using: .utf8)!)
    exit(2)
}
let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
render(scale: 1, to: out.appendingPathComponent("background.png"))
render(scale: 2, to: out.appendingPathComponent("background@2x.png"))
