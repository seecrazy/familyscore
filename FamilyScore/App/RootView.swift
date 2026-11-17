import SwiftUI
import SwiftData

/// 根视图：未完成引导 → Onboarding；已完成 → 主 Tab（§12.3 技术要点）
/// 支持 `-demoBoot` 启动参数：直接灌入演示家庭进入主界面（UI 测试/截图走查用）
struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.modelContext) private var context
    @EnvironmentObject var app: AppEnvironment
    @State private var consumedFreshFlag = false

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingView()
                    .transition(.opacity)
            } else {
                RootTabView()
                    .transition(.opacity)
            }
        }
        .onAppear {
            consumeFreshOnboardingFlagIfNeeded()
            bootDemoIfNeeded()
        }
    }

    /// -freshOnboarding：UI 测试辅助，一次性消费——本次启动进引导，之后正常流转
    private func consumeFreshOnboardingFlagIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-freshOnboarding"),
              !consumedFreshFlag else { return }
        consumedFreshFlag = true
        hasCompletedOnboarding = false
    }

    private func bootDemoIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-demoBoot"),
              !hasCompletedOnboarding,
              app.currentMemberID == nil else { return }
        let (_, members) = DemoData.build(context: context)
        app.currentMemberID = members.first { $0.name == "妈妈" }?.id ?? members[0].id
        hasCompletedOnboarding = true
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Family.self, Member.self, Rule.self, ScoreRecord.self], inMemory: true)
}
