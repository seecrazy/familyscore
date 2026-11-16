import SwiftUI
import SwiftData

/// 根视图：未完成引导 → Onboarding；已完成 → 主 Tab（§12.3 技术要点）
/// 支持 `-demoBoot` 启动参数：直接灌入演示家庭进入主界面（UI 测试/截图走查用）
struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.modelContext) private var context
    @AppStorage("currentMemberID") private var currentMemberID: String = ""

    var body: some View {
        if hasCompletedOnboarding {
            RootTabView()
                .transition(.opacity)
        } else {
            OnboardingView()
                .transition(.opacity)
                .onAppear { bootDemoIfNeeded() }
        }
    }

    private func bootDemoIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-demoBoot"),
              !hasCompletedOnboarding,
              UUID(uuidString: currentMemberID) == nil || currentMemberID.isEmpty else { return }
        let (family, members) = DemoData.build(context: context)
        currentMemberID = members.first { $0.name == "妈妈" }?.id.uuidString
            ?? members[0].id.uuidString
        hasCompletedOnboarding = true
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Family.self, Member.self, Rule.self, ScoreRecord.self], inMemory: true)
}
