import SwiftUI

/// 主 Tab（§7.3）：首页/排行/统计/商城/我的；切换弹跳 + 轻震；顶层彩带
struct RootTabView: View {
    @EnvironmentObject var app: AppEnvironment
    @State private var tab = 0

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        ZStack {
            TabView(selection: tabBinding) {
                HomeView().tabItem { Label("首页", systemImage: "house.fill") }.tag(0)
                RankView().tabItem { Label("排行", systemImage: "trophy.fill") }.tag(1)
                StatsView().tabItem { Label("统计", systemImage: "chart.bar.fill") }.tag(2)
                RewardsView().tabItem { Label("商城", systemImage: "gift.fill") }.tag(3)
                ProfileView().tabItem { Label("我的", systemImage: "person.crop.circle") }.tag(4)
            }
            .tint(Theme.primary)

            ConfettiOverlay()
        }
    }

    /// 切换时图标弹跳 + 轻震（§11）
    private var tabBinding: Binding<Int> {
        Binding(get: { tab }, set: { newValue in
            if newValue != tab { Haptics.light() }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { tab = newValue }
        })
    }
}
