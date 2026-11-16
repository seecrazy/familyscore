// check_shots.swift — 截图像素健康检查（视觉通道故障时的降级目检辅助）
// 用法：swift check_shots.swift <dir>
// 检查：非空白/非纯黑/非单色崩溃页；内容密度；主色出现（品牌橙）
import Foundation
import CoreGraphics
import ImageIO

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/fs_shots"
let files = try FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix(".png") }
var failed = 0

for f in files.sorted() {
    let url = URL(fileURLWithPath: dir).appendingPathComponent(f)
    guard let img = CGImageSourceCreateWithURL(url as CFURL, nil)
        .flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) }) else { continue }
    let w = img.width, h = img.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let data = ctx.data else { continue }
    let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)

    // 抽样网格（步长 6px）
    var histogram: [UInt32: Int] = [:]
    var colorful = 0, samples = 0, white = 0, black = 0, orange = 0
    let step = 6
    for y in stride(from: 0, to: h, by: step) {
        for x in stride(from: 0, to: w, by: step) {
            let i = (y * w + x) * 4
            let r = Int(px[i]), g = Int(px[i+1]), b = Int(px[i+2])
            samples += 1
            let key = UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b)
            histogram[key, default: 0] += 1
            if r > 245 && g > 245 && b > 245 { white += 1 }
            if r < 20 && g < 20 && b < 20 { black += 1 }
            // 品牌橙邻域：暖橙渐变/按钮/卡片
            if r > 220 && g > 90 && g < 200 && b < 130 && r - b > 110 { orange += 1 }
            // 彩色像素（非灰阶）
            if abs(r - g) > 24 || abs(g - b) > 24 { colorful += 1 }
        }
    }

    var issues: [String] = []
    if Double(white) / Double(samples) > 0.85 { issues.append("大面积纯白(疑似空白页)") }
    if Double(black) / Double(samples) > 0.7 { issues.append("大面积纯黑") }
    if histogram.count < 40 { issues.append("颜色数极少(\(histogram.count)，疑似未渲染)") }
    if Double(colorful) / Double(samples) < 0.03 { issues.append("彩色内容占比过低(\(Int(Double(colorful)/Double(samples)*100))%)") }

    let status = issues.isEmpty ? "✅" : "❌"
    if !issues.isEmpty { failed += 1 }
    print("\(status) \(f) 颜色数=\(histogram.count) 彩色=\(Int(Double(colorful)/Double(samples)*100))% 橙色=\(Int(Double(orange)/Double(samples)*100))% \(issues.joined(separator: "; "))")
}
print(failed == 0 ? "\nALL SHOTS HEALTHY" : "\n\(failed) SUSPICIOUS SHOT(S)")
exit(failed == 0 ? 0 : 1)
