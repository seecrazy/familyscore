import SwiftUI
import SwiftData

/// 会话上下文：当前成员（本地单机版通过「切换成员」选择，§8.5）
@MainActor
final class AppEnvironment: ObservableObject {
    @AppStorage("currentMemberID") private var currentMemberIDString: String = ""
    @Published var confettiTrigger: Int = 0   // 全屏彩带触发器
    @Published var pendingApprovalCount: Int = 0

    var currentMemberID: UUID? {
        get { UUID(uuidString: currentMemberIDString) }
        set { currentMemberIDString = newValue?.uuidString ?? "" }
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
