import Foundation
import SwiftData

/// 指派任务生命周期（§5.2 TaskAssignment + v3.2 过期机制）：
/// 过期 = 截止日已过且未完成。原则：**不自动减分**（避免待办焦虑），
/// 状态转为 expired 留痕，家长可在首页过期卡片选择发起「未完成约定任务 −5」人工确认。
enum TaskService {

    /// 过期结算：dueDay < 今天 且 status == open → expired。
    /// App 前台刷新时调用（无需后台任务）；幂等，返回本次结算的条数。
    @discardableResult
    static func settleExpired(family: Family, context: ModelContext, now: Date = .now) -> Int {
        let todayKey = FamilyCalendar.dayKey(now, timezoneID: family.timezoneID)
        let fid = family.id
        let desc = FetchDescriptor<TaskAssignment>(predicate: #Predicate {
            $0.familyID == fid && $0.dueDay < todayKey
        })
        var settled = 0
        for a in ((try? context.fetch(desc)) ?? []) where a.status == .open {
            a.status = .expired
            settled += 1
        }
        if settled > 0 {
            try? context.save()
        }
        return settled
    }

    struct ExpiredItem: Identifiable {
        let id = UUID()
        let assignment: TaskAssignment
        let ruleName: String
        let ruleID: UUID?
        let assigneeName: String
        let assigneeEmoji: String
        let dueDay: String
    }

    /// 近 `withinDays` 天内过期的任务（含刚结算的），供首页过期卡片展示
    static func expiredRecently(family: Family, rules: [Rule], members: [Member],
                                context: ModelContext, now: Date = .now,
                                withinDays: Int = 3) -> [ExpiredItem] {
        let cal = FamilyCalendar.calendar(timezoneID: family.timezoneID)
        let todayStart = cal.startOfDay(for: now)
        let boundary = FamilyCalendar.dayKey(todayStart.addingTimeInterval(Double(-withinDays + 1) * 86400),
                                             timezoneID: family.timezoneID)
        let fid = family.id
        let desc = FetchDescriptor<TaskAssignment>(
            predicate: #Predicate { $0.familyID == fid && $0.dueDay >= boundary },
            sortBy: [SortDescriptor(\.dueDay, order: .reverse)])
        let rulesByID = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })
        let membersByID = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
        return ((try? context.fetch(desc)) ?? [])
            .filter { $0.status == .expired }
            .compactMap { a in
                guard let rule = rulesByID[a.ruleID], let m = membersByID[a.assigneeID] else { return nil }
                return ExpiredItem(assignment: a, ruleName: rule.name, ruleID: rule.id,
                                   assigneeName: m.name, assigneeEmoji: m.emoji, dueDay: a.dueDay)
            }
    }

    /// 截止日选项（v3.2：今天/明天/后天/本周末/自定义）
    struct DueOption: Identifiable, Hashable {
        let label: String
        let daysFromNow: Int?      // nil = 自定义（由调用方给日期）
        var id: String { label }
    }

    static func dueOptions(now: Date = .now, timezoneID: String) -> [DueOption] {
        let cal = FamilyCalendar.calendar(timezoneID: timezoneID)
        let weekend = nextWeekendDay(now: now, cal: cal)
        let daysToWeekend = cal.dateComponents([.day],
                                               from: cal.startOfDay(for: now),
                                               to: cal.startOfDay(for: weekend)).day ?? 0
        var options: [DueOption] = [
            .init(label: "今天", daysFromNow: 0),
            .init(label: "明天", daysFromNow: 1),
            .init(label: "后天", daysFromNow: 2),
        ]
        if daysToWeekend > 2 {
            options.append(.init(label: "本周末", daysFromNow: daysToWeekend))
        }
        options.append(.init(label: "自定义", daysFromNow: nil))
        return options
    }

    private static func nextWeekendDay(now: Date, cal: Calendar) -> Date {
        var d = cal.startOfDay(for: now)
        for _ in 0..<7 {
            let wd = cal.component(.weekday, from: d)
            if wd == 6 || wd == 7 { return d }   // 周五或周六
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return d
    }

    /// 计算实际截止 key
    static func dueDayKey(for option: DueOption, customDate: Date?,
                          timezoneID: String, now: Date = .now) -> String {
        if let days = option.daysFromNow {
            let cal = FamilyCalendar.calendar(timezoneID: timezoneID)
            let date = cal.date(byAdding: .day, value: days, to: now) ?? now
            return FamilyCalendar.dayKey(date, timezoneID: timezoneID)
        }
        return FamilyCalendar.dayKey(customDate ?? now, timezoneID: timezoneID)
    }
}
