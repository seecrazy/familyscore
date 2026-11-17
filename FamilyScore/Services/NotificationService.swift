import Foundation
import SwiftData
import UserNotifications

/// 通知执行层：组装上下文 → Planner 规划 → 排程/发送（§18.4 全量，v3.0）
enum NotificationService {

    static let delegate = ForegroundPresenter()

    /// 前台也展示横幅（目标达成等即时通知）
    final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    willPresent notification: UNNotification) async
            -> UNNotificationPresentationOptions {
            [.banner, .sound]
        }
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current().delegate = delegate
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: 上下文组装（唯一依赖数据库的部分）

    static func assembleContext(family: Family, members: [Member], context: ModelContext,
                                now: Date = .now) -> NotificationContext {
        var ctx = NotificationContext(timezoneID: family.timezoneID)
        let tz = family.timezoneID
        let todayKey = FamilyCalendar.dayKey(now, timezoneID: tz)

        let byID = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
        let activeMembers = members.filter { $0.status == .active }

        // 待办
        let aid = family.id
        let assignments = (try? context.fetch(FetchDescriptor<TaskAssignment>(
            predicate: #Predicate { $0.familyID == aid && $0.dueDay == todayKey }))) ?? []
        let open = assignments.filter { $0.status == .open }
        ctx.openTodoCount = open.count
        if let first = open.first {
            let rid = first.ruleID
            if let rule = (try? context.fetch(FetchDescriptor<Rule>(predicate: #Predicate { $0.id == rid })))?.first {
                ctx.todoExampleTitle = rule.name
            }
        }

        // 生日
        ctx.birthdays = BirthdayService.upcoming(members: activeMembers, family: family,
                                                 now: now, withinDays: 7)
            .map { ($0.member.name, $0.isToday, $0.daysLeft) }

        // 待评审
        let fid = family.id
        let pendingAll = (try? context.fetch(FetchDescriptor<ScoreRecord>(
            predicate: #Predicate { $0.familyID == fid }))) ?? []
        ctx.pendingApprovalCount = pendingAll.filter { $0.status == .pending }.count

        // 积分到期（30 天窗口，按成员聚合）
        var expiring: [String: (amount: Int, daysLeft: Int)] = [:]
        for m in activeMembers {
            for lot in RewardService.expiringLots(member: m, at: now, timezoneID: tz, context: context) {
                // 批次月龄 [11,12) → 到期天数按月近似 30 天内
                guard lot.amount > 0 else { continue }
                let lotDate = FamilyCalendar.date(ofMonthKey: lot.monthKey) ?? now
                let age = now.timeIntervalSince(lotDate) / 86400
                let daysLeft = max(0, Int(365 - age))
                guard daysLeft <= 30 else { continue }
                if let cur = expiring[m.name] {
                    expiring[m.name] = (cur.amount + lot.amount, min(cur.daysLeft, daysLeft))
                } else {
                    expiring[m.name] = (lot.amount, daysLeft)
                }
            }
        }
        ctx.expiringLots = expiring.map { (memberName: $0.key, amount: $0.value.amount, daysLeft: $0.value.daysLeft) }
            .sorted { $0.daysLeft < $1.daysLeft }

        // 周结算
        let entries = RankService.leaderboard(family: family, members: members, period: .week,
                                              at: now, context: context)
        ctx.weeklyChampionName = entries.first.flatMap { byID[$0.memberID]?.name }
        ctx.weeklyFamilyScore = entries.reduce(0) { $0 + $1.score }

        // 打卡保护：当前成员今日未打卡且 streak ≥ 3
        if let me = activeMembers.first(where: { $0.lastCheckInDay != todayKey && $0.streakDays >= 3 }) {
            ctx.protectMemberName = me.name
            ctx.protectStreakDays = me.streakDays
        }
        return ctx
    }

    // MARK: 排程

    static func reschedule(family: Family, members: [Member], context: ModelContext,
                           now: Date = .now, defaults: UserDefaults = .standard) {
        let settings = NotificationSettings.load(defaults: defaults)
        let ctx = assembleContext(family: family, members: members, context: context, now: now)
        let plans = NotificationPlanner.plans(settings: settings, ctx: ctx, now: now)
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { ns in
            guard ns.authorizationStatus == .authorized || ns.authorizationStatus == .provisional
            else { return }
            center.getPendingNotificationRequests { pending in
                // 只移除我们管理的 fs- 前缀，保留其他来源
                let ids = pending.map(\.identifier).filter { $0.hasPrefix("fs-") }
                center.removePendingNotificationRequests(withIdentifiers: ids)
                let tz = TimeZone(identifier: family.timezoneID) ?? .current
                for plan in plans {
                    let content = UNMutableNotificationContent()
                    content.title = plan.title
                    content.body = plan.body
                    content.sound = .default
                    var comps = Calendar.current.dateComponents(in: tz, from: plan.fireDate)
                    comps.timeZone = tz
                    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                    center.add(UNNotificationRequest(identifier: plan.id, content: content, trigger: trigger))
                }
            }
        }
    }

    /// 团队周目标达成：即时横幅（§18.4 目标达成）
    static func celebrateGoal(family: Family, total: Int) {
        guard NotificationSettings.load().master,
              NotificationSettings.load().goalReached else { return }
        let content = UNMutableNotificationContent()
        content.title = "🎉 家庭目标达成！"
        content.body = "全家本周已得 \(total) 分，目标 \(family.settingsData.weeklyGoal) 分——解锁属于全家的奖励时刻"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "fs-goal-\(UUID().uuidString)", content: content, trigger: trigger))
    }
}
