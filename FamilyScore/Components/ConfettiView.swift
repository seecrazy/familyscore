import SwiftUI
import UIKit

/// 全屏彩带（CAEmitterLayer，§11 加分成功/兑换成功）；尊重"减弱动态效果"
struct ConfettiView: UIViewRepresentable {
    let trigger: Int

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard trigger > 0, !UIAccessibility.isReduceMotionEnabled else { return }
        // 旧发射器清理
        uiView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }

        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: uiView.bounds.midX, y: -10)
        emitter.emitterSize = CGSize(width: uiView.bounds.width, height: 1)
        emitter.emitterShape = .line

        let colors: [UIColor] = [
            UIColor(red: 1.00, green: 0.54, blue: 0.24, alpha: 1),   // 主橙
            UIColor(red: 1.00, green: 0.70, blue: 0.28, alpha: 1),   // 浅橙
            UIColor(red: 0.20, green: 0.78, blue: 0.48, alpha: 1),   // 薄荷绿
            UIColor(red: 0.29, green: 0.62, blue: 1.00, alpha: 1),   // 天蓝
            UIColor(red: 1.00, green: 0.84, blue: 0.31, alpha: 1),   // 金
        ]
        emitter.emitterCells = (0..<5).map { i in
            let cell = CAEmitterCell()
            cell.birthRate = 14
            cell.lifetime = 6
            cell.velocity = CGFloat.random(in: 180...340)
            cell.velocityRange = 60
            cell.emissionRange = .pi          // 向下扇形
            cell.emissionLongitude = .pi      // 往下
            cell.spin = CGFloat.random(in: -4...4)
            cell.spinRange = 3
            cell.scale = 0.55
            cell.scaleRange = 0.5
            cell.color = colors[i % colors.count].cgColor
            cell.contents = ConfettiView.pieceImage(i: i).cgImage
            return cell
        }
        uiView.layer.addSublayer(emitter)
        // 1.6s 后停止发射，4.5s 后移除
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) {
            emitter.birthRate = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            emitter.removeFromSuperlayer()
        }
    }

    /// 五种纸屑形状（矩形/圆点/三角条）
    private static func pieceImage(i: Int) -> UIImage {
        let size = CGSize(width: 12, height: 18)
        let r = UIGraphicsImageRenderer(size: size)
        return r.image { ctx in
            UIColor.white.setFill()
            let cg = ctx.cgContext
            switch i % 3 {
            case 0: cg.fill(CGRect(origin: .zero, size: size))
            case 1:
                cg.fillEllipse(in: CGRect(origin: .zero, size: CGSize(width: 12, height: 12)))
            default:
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 6, y: 0)); p.addLine(to: CGPoint(x: 12, y: 18)); p.addLine(to: CGPoint(x: 0, y: 18))
                p.closeSubpath()
                cg.addPath(p); cg.fillPath()
            }
        }
    }
}

/// 挂在根视图的彩带覆盖层（trigger 变化时发射）
struct ConfettiOverlay: View {
    @EnvironmentObject var app: AppEnvironment
    var body: some View {
        ConfettiView(trigger: app.confettiTrigger)
            .allowsHitTesting(false)
            .ignoresSafeArea()
    }
}
