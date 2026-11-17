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

    /// 退出体验模式（需求 4）：清空演示家庭全部数据，回到引导页
    static func exitDemoMode(context: ModelContext) {
        let demos = (try? context.fetch(FetchDescriptor<Family>(predicate: #Predicate { $0.isDemo == true }))) ?? []
        guard let demo = demos.first else { return }
        let fid = demo.id
        func purgeAll<T: PersistentModel>(_ type: T.Type) {
            let all = (try? context.fetch(FetchDescriptor<T>())) ?? []
            for obj in all { context.delete(obj) }
        }
        context.delete(demo)
        purgeAll(Member.self); purgeAll(Rule.self); purgeAll(ScoreRecord.self)
        purgeAll(Reward.self); purgeAll(Redemption.self); purgeAll(AuditLog.self)
        purgeAll(Badge.self); purgeAll(RankSnapshot.self); purgeAll(TaskAssignment.self)
        purgeAll(WishListItem.self); purgeAll(ScoreLot.self)
        _ = fid
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
