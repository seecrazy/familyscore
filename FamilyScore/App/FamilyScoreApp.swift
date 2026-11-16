import SwiftUI
import SwiftData

@main
struct FamilyScoreApp: App {
    let container: ModelContainer
    @StateObject private var app = AppEnvironment()

    init() {
        do {
            container = try ModelContainer(
                for: Family.self, Member.self, Rule.self, ScoreRecord.self, Reward.self,
                    Redemption.self, AuditLog.self, Badge.self, RankSnapshot.self,
                    TaskAssignment.self, WishListItem.self, ScoreLot.self)
        } catch {
            fatalError("ModelContainer failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
        }
        .modelContainer(container)
    }
}
