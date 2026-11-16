import SwiftUI

/// 品牌设计令牌（DESIGN.md §1.3 / §7）
enum Theme {
    // 色板
    static let primary = Color(hex: 0xFF8A3D)        // 暖橙
    static let primaryLight = Color(hex: 0xFFB347)
    static let rankBlue = Color(hex: 0x4A9EFF)       // 辅色-排行
    static let addGreen = Color(hex: 0x34C77B)       // 辅色-加分
    static let deductRed = Color(hex: 0xFF5A5F)      // 辅色-减分
    static let gold = Color(hex: 0xFFD54F)
    static let bgCream = Color(hex: 0xFFF8F0)        // 背景浅（浅色）
    static let bgGray = Color(hex: 0xF7F7FA)
    static let cardDark = Color(hex: 0x2C2C2E)       // 深色卡片
    static let textSecondary = Color(hex: 0x8E8E93)

    // 深色模式自适应背景
    static var appBackground: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: 0x1C1C1E) : UIColor(hex: 0xFFF8F0)
        })
    }
    static var cardBackground: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: 0x2C2C2E) : .white
        })
    }

    // 主渐变（积分卡/品牌）
    static let brandGradient = LinearGradient(
        colors: [primary, primaryLight], startPoint: .topLeading, endPoint: .bottomTrailing)

    // 圆角
    static let radiusCard: CGFloat = 20
    static let radiusButton: CGFloat = 14

    // 卡片阴影
    static func cardShadow() -> some View {
        // shadow modifier 在 extension 中统一
        EmptyView()
    }

    // 字号（数字用 rounded 设计）
    static let numberFont = Font.system(.title, design: .rounded, weight: .bold)
}

extension View {
    /// 卡片统一样式：圆角 + 阴影（§7.1）
    @ViewBuilder
    func scoreCard() -> some View {
        self
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
