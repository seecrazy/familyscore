import SwiftUI
import SwiftData

/// 会话上下文：当前成员。
/// v3.3：@AppStorage 在 ObservableObject 内不发布变更通知（创建家庭后首页读旧值的根因），
/// 改为 @Published + UserDefaults 持久化——写入即时广播，重启时恢复。
@MainActor
final class AppEnvironment: ObservableObject {
    private static let memberKey = "currentMemberID"
    @Published var currentMemberID: UUID? {
        didSet { UserDefaults.standard.set(currentMemberID?.uuidString ?? "", forKey: Self.memberKey) }
    }
    @Published var confettiTrigger: Int = 0   // 全屏彩带触发器
    @Published var pendingApprovalCount: Int = 0

    init() {
        currentMemberID = UserDefaults.standard.string(forKey: Self.memberKey).flatMap(UUID.init(uuidString:))
    }

    func celebrate() { confettiTrigger += 1 }

    func currentMember(in context: ModelContext) -> Member? {
        guard let id = currentMemberID else { return nil }
        var d = FetchDescriptor<Member>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    func currentFamily(in context: ModelContext) -> Family? {
        guard let m = currentMember(in: context) else { return nil }
        let fid = m.familyID
        var d = FetchDescriptor<Family>(predicate: #Predicate { $0.id == fid })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }
}
