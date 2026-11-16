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

/// 本地通知（§18.4 不依赖推送服务的子集，v2.1）：生日当天 09:00 + 每日待办 19:00 汇总
enum NotificationService {

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func reschedule(family: Family, members: [Member], assignments: [TaskAssignment],
                           now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            else { return }
            center.removePendingNotificationRequests(withIdentifiers:
                pendingBirthdayIDs(members: members) + ["daily-todo"])
            scheduleBirthdays(family: family, members: members, now: now)
            scheduleDailyTodo(family: family, assignments: assignments, now: now)
        }
    }

    private static func pendingBirthdayIDs(members: [Member]) -> [String] {
        members.map { "birthday-\($0.id.uuidString)" }
    }

    private static func scheduleBirthdays(family: Family, members: [Member], now: Date) {
        let tz = TimeZone(identifier: family.timezoneID) ?? .current
        for up in BirthdayService.upcoming(members: members, family: family, now: now,
                                           withinDays: 400) where up.daysLeft <= 1 {
            var comps = Calendar.current.dateComponents(in: tz, from: up.dateThisYear)
            comps.hour = 9; comps.minute = 0
            comps.timeZone = tz
            let content = UNMutableNotificationContent()
            content.title = up.isToday ? "🎂 今天是\(up.member.name)的生日" : "明天是\(up.member.name)的生日"
            content.body = up.isToday
                ? "记得给\(up.member.name)一个大大的拥抱，也可以准备生日专属奖励 ✨"
                : "提前准备起来，给\(up.member.name)一个惊喜 🎁"
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let req = UNNotificationRequest(identifier: "birthday-\(up.member.id.uuidString)",
                                            content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(req)
        }
    }

    private static func scheduleDailyTodo(family: Family, assignments: [TaskAssignment], now: Date) {
        let tz = TimeZone(identifier: family.timezoneID) ?? .current
        let cal = FamilyCalendar.calendar(timezoneID: family.timezoneID)
        let todayKey = FamilyCalendar.dayKey(now, timezoneID: family.timezoneID)
        let openCount = assignments.filter { $0.dueDay == todayKey && $0.status == .open }.count
        guard openCount > 0 else { return }
        var fire = cal.dateComponents([.year, .month, .day], from: now)
        fire.hour = 19; fire.minute = 0; fire.timeZone = tz
        let content = UNMutableNotificationContent()
        content.title = "今日待办还剩 \(openCount) 件"
        content.body = "睡前一起清个零吧，每一分都是爱 💛"
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: fire, repeats: false)
        let req = UNNotificationRequest(identifier: "daily-todo", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }
}
