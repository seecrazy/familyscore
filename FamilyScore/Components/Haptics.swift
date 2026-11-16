import UIKit

/// 触觉反馈（DESIGN.md §11），遵循系统"减弱动态效果"时静音
enum Haptics {
    private static var reduceMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    static func success() {
        guard !reduceMotion else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
    static func light() {
        guard !reduceMotion else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func medium() {
        guard !reduceMotion else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
