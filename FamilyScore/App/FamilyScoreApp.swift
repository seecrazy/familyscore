import SwiftUI
import SwiftData

@main
struct FamilyScoreApp: App {
    let container: ModelContainer
    @StateObject private var app = AppEnvironment()

    init() {
        let schema = Schema([
            Family.self, Member.self, Rule.self, ScoreRecord.self, Reward.self,
            Redemption.self, AuditLog.self, Badge.self, RankSnapshot.self,
            TaskAssignment.self, WishListItem.self, ScoreLot.self,
        ])
        let config = ModelConfiguration(schema: schema)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // 迁移失败兜底：移除无法迁移的本地库后重建（早期版本可接受的数据重置路径）
            let url = config.url
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
            do {
                container = try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("ModelContainer failed even after reset: \(error)")
            }
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
