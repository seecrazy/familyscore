import SwiftUI

/// 根视图：未完成引导 → Onboarding；已完成 → 主 Tab（§12.3 技术要点）
struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            RootTabView()
                .transition(.opacity)
        } else {
            OnboardingView()
                .transition(.opacity)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Family.self, Member.self, Rule.self, ScoreRecord.self], inMemory: true)
}
