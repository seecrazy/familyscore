import Foundation
import SwiftData

/// 成员资料维护（v3.3：改名/头像/角色、安全删除）
enum MemberAdminService {

    enum DeleteResult: Equatable {
        case deleted
        case blockedHasRecords(count: Int)   // 有历史记录 → 只能退出，保账本完整（§15）
    }

    /// 删除成员：仅允许删除「从未产生任何记录」的成员（误建清理）；
    /// 有积分/兑换/指派/徽章记录的一律拒绝——历史账本 append-only（§5.2/§13）。
    static func deleteIfClean(_ member: Member, context: ModelContext) -> DeleteResult {
        let mid = member.id
        let records = (try? context.fetch(FetchDescriptor<ScoreRecord>(
            predicate: #Predicate { $0.memberID == mid }))) ?? []
        if !records.isEmpty { return .blockedHasRecords(count: records.count) }

        let redemptions = (try? context.fetch(FetchDescriptor<Redemption>(
            predicate: #Predicate { $0.memberID == mid }))) ?? []
        let lots = (try? context.fetch(FetchDescriptor<ScoreLot>(
            predicate: #Predicate { $0.memberID == mid }))) ?? []
        let badges = (try? context.fetch(FetchDescriptor<Badge>(
            predicate: #Predicate { $0.memberID == mid }))) ?? []
        let assignments = (try? context.fetch(FetchDescriptor<TaskAssignment>(
            predicate: #Predicate { $0.assigneeID == mid }))) ?? []
        guard redemptions.isEmpty, lots.isEmpty, badges.isEmpty, assignments.isEmpty else {
            return .blockedHasRecords(count: records.count + redemptions.count + lots.count
                                      + badges.count + assignments.count)
        }

        for lot in lots { context.delete(lot) }
        for r in redemptions { context.delete(r) }
        for b in badges { context.delete(b) }
        for a in assignments { context.delete(a) }
        context.delete(member)
        try? context.save()
        return .deleted
    }

    /// 改名/头像/角色（创建者角色不可改；系数随角色联动重算默认值，历史不追溯 §3）
    static func updateProfile(_ member: Member, family: Family,
                              name: String, emoji: String, role: MemberRole,
                              context: ModelContext) -> Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        member.name = name.trimmingCharacters(in: .whitespaces)
        member.emoji = emoji
        if member.id != family.ownerID {
            member.role = role
        }
        AuditService.log(familyID: family.id, actorID: family.ownerID, action: .config,
                         targetID: member.id, reason: "修改资料「\(member.name)」", context: context)
        try? context.save()
        return true
    }
}
