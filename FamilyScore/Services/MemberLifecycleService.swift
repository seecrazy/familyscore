import Foundation
import SwiftData
import UserNotifications

/// 成员权限与生命周期（v2.1：管理员设置、重新加入、退出体验模式）
extension FamilyService {

    /// 仅创建者可设置/撤销管理员（需求 3）
    @discardableResult
    static func setAdmin(_ member: Member, family: Family, by owner: Member,
                         isAdmin: Bool, context: ModelContext) -> Bool {
        guard owner.id == family.ownerID, owner.role == .admin else { return false }
        guard member.familyID == family.id else { return false }
        guard member.id != family.ownerID else { return false } // 创建者身份不可自除
        member.role = isAdmin ? .admin : .child // 撤销管理员后回到普通成员（孩子）
        AuditService.log(familyID: family.id, actorID: owner.id, action: .config,
                         targetID: member.id,
                         reason: "\(member.name) \(isAdmin ? "成为管理员" : "取消管理员")",
                         context: context)
        try? context.save()
        return true
    }

    /// 已退出成员重新加入（需求 5）：历史积分保留，重新参与排名
    static func rejoin(_ member: Member, context: ModelContext) {
        member.status = .active
        AuditService.log(familyID: member.familyID, actorID: member.id, action: .config,
                         targetID: member.id, reason: "\(member.name) 重新加入", context: context)
        try? context.save()
    }

    /// 退出体验模式（需求 4）：清空演示家庭全部数据，回到引导页。
    /// v3.3：批量删除（逐条 delete 2000+ 对象会阻塞主线程数秒）。
    static func exitDemoMode(context: ModelContext) {
        let demos = (try? context.fetch(FetchDescriptor<Family>(predicate: #Predicate { $0.isDemo == true }))) ?? []
        guard demos.first != nil else { return }
        // 本应用单家庭：全表批量删除等价清演示（毫秒级，不逐条 delete）
        try? context.delete(model: Family.self)
        try? context.delete(model: Member.self)
        try? context.delete(model: Rule.self)
        try? context.delete(model: ScoreRecord.self)
        try? context.delete(model: Reward.self)
        try? context.delete(model: Redemption.self)
        try? context.delete(model: AuditLog.self)
        try? context.delete(model: Badge.self)
        try? context.delete(model: RankSnapshot.self)
        try? context.delete(model: TaskAssignment.self)
        try? context.delete(model: WishListItem.self)
        try? context.delete(model: ScoreLot.self)
        try? context.save()
    }
}

/// 生日（v2.1 需求 6）：提醒只取月日，按家庭时区
enum BirthdayService {

    struct Upcoming: Identifiable {
        let id = UUID()
        let member: Member
        let dateThisYear: Date   // 今年生日（已过则为明年）
        let isToday: Bool
        let daysLeft: Int
    }

    static func upcoming(members: [Member], family: Family,
                         now: Date = .now, withinDays: Int = 7) -> [Upcoming] {
        let cal = FamilyCalendar.calendar(timezoneID: family.timezoneID)
        let today = cal.startOfDay(for: now)
        var result: [Upcoming] = []
        for m in members where m.status == .active {
            guard let bd = m.birthday else { continue }
            var comps = cal.dateComponents([.month, .day], from: bd)
            comps.year = cal.component(.year, from: now)
            guard var thisYear = cal.date(from: comps) else { continue }
            // 已过的生日顺延到明年（今日生日除外）
            if cal.startOfDay(for: thisYear) < today {
                comps.year! += 1
                thisYear = cal.date(from: comps) ?? thisYear
            }
            let days = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: thisYear)).day ?? 0
            if days <= withinDays {
                result.append(Upcoming(member: m, dateThisYear: thisYear,
                                       isToday: days == 0, daysLeft: days))
            }
        }
        return result.sorted { $0.daysLeft < $1.daysLeft }
    }
}
