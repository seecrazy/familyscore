// gen_appicon.swift — 家分宝 App 图标生成（方案 A：房子+星星+心）
// 运行：swift scripts/gen_appicon.swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("cannot create context")
}

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// MARK: 坐标系说明：CGBitmapContext 为 Quartz 标准坐标（原点左下，y 向上），
// 输出 PNG 时行序翻转，因此以下 y 值越大越靠画面顶部（视觉）。

// MARK: 背景：135° 渐变 #FF8A3D → #FFB347（视觉左上 → 右下）
let bgColors = [color(0xFF8A3D), color(0xFFB347)] as CFArray
ctx.drawLinearGradient(
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: bgColors, locations: [0, 1])!,
    start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: CGFloat(size), y: 0), options: [])

// MARK: 房子：白色圆头线条（屋顶 + 两侧墙，开放式无底边）
let house = CGMutablePath()
house.move(to: CGPoint(x: 226, y: 510)); house.addLine(to: CGPoint(x: 512, y: 726)) // 左屋檐→顶
house.addLine(to: CGPoint(x: 798, y: 510))                                          // 顶→右屋檐
house.move(to: CGPoint(x: 288, y: 522)); house.addLine(to: CGPoint(x: 288, y: 208)) // 左墙
house.move(to: CGPoint(x: 736, y: 522)); house.addLine(to: CGPoint(x: 736, y: 208)) // 右墙
ctx.addPath(house)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setLineWidth(62)
ctx.setStrokeColor(color(0xFFFFFF))
ctx.setShadow(offset: .zero, blur: 36, color: color(0xE0702A, 0.55)) // 柔光让白线从渐变里浮起
ctx.strokePath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

// MARK: 心：珊瑚红 #FF5A5F，房子中央
func heartPath(cx: CGFloat, cy: CGFloat, s: CGFloat) -> CGPath {
    let p = CGMutablePath()
    // 经典参数心形 x=16sin³t, y=13cos t − 5cos 2t − 2cos 3t − cos 4t（y 向上坐标系，心尖朝下）
    var first = true
    let n = 96
    for i in 0...n {
        let t = CGFloat(i) / CGFloat(n) * 2 * .pi
        let nx = 16 * pow(sin(t), 3) / 16
        let ny = (13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)) / 16
        let px = cx + nx * s
        let py = cy + (ny - 0.12) * s * 1.15
        if first { p.move(to: CGPoint(x: px, y: py)); first = false } else { p.addLine(to: CGPoint(x: px, y: py)) }
    }
    p.closeSubpath()
    return p
}
ctx.addPath(heartPath(cx: 512, cy: 388, s: 132))
ctx.setFillColor(color(0xFF5A5F))
ctx.setShadow(offset: .zero, blur: 24, color: color(0xC43236, 0.5))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

// MARK: 星：金色 #FFD54F + 外发光，屋顶上方（视觉顶部）
func starPath(cx: CGFloat, cy: CGFloat, outer: CGFloat, inner: CGFloat) -> CGPath {
    let p = CGMutablePath()
    for i in 0..<10 {
        let r = i.isMultiple(of: 2) ? outer : inner
        let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
        let pt = CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
}
ctx.addPath(starPath(cx: 512, cy: 856, outer: 104, inner: 44))
ctx.setFillColor(color(0xFFD54F))
ctx.setShadow(offset: .zero, blur: 56, color: color(0xFFD54F, 0.85)) // 金色外发光
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

// MARK: 导出 PNG
let img = ctx.makeImage()!
let out = URL(fileURLWithPath: "FamilyScore/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon1024.png")
try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("written: \(out.path)")
