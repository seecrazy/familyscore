import Foundation
import SwiftData

/// UI 数据聚合：一次查询、内存组装（家庭级数据量 <1 万条，§18.5 预算内）
struct HomeSummary {
    var familyToday: Int
    var myToday: Int
    var myRank: Int
    var memberCount: Int
    var streakDays: Int
    var weeklyGoal: Int
    var weeklyScore: Int
    var quickRules: [Rule]
    var pendingRecords: [ScoreRecord]        // 待我（家长）确认
    var todayAssignments: [TaskAssignmentItem]
    var feed: [FeedItem]

    struct TaskAssignmentItem: Identifiable {
        let id: UUID
        let rule: Rule
        let assignee: Member
        let source: String     // 系统 / @指派人
        let done: Bool
    }

    struct FeedItem: Identifiable {
        let id: UUID
        let member: Member
        let text: String
        let points: Int
        let time: Date
    }

    static func compute(family: Family, me: Member, members: [Member],
                        rules: [Rule], records: [ScoreRecord],
                        assignments: [TaskAssignment], now: Date = .now,
                        context: ModelContext) -> HomeSummary {
        let tz = family.timezoneID
        let todayStart = FamilyCalendar.startOfDay(now, timezoneID: tz)
        let effective = records.filter {
            $0.status == .approved || $0.status == .reversed || $0.status == .appealed
        }

        // 今日
        let todayRecords = effective.filter { $0.createdAt >= todayStart }
        let familyToday = todayRecords.reduce(0) { $0 + $1.points }
        let myToday = todayRecords.filter { $0.memberID == me.id }.reduce(0) { $0 + $1.points }

        // 今日排名
        let activeIDs = Set(members.filter { $0.status == .active }.map(\.id))
        var todayByMember: [UUID: Int] = [:]
        for r in todayRecords where activeIDs.contains(r.memberID) {
            todayByMember[r.memberID, default: 0] += r.points
        }
        let myScore = todayByMember[me.id] ?? 0
        let rank = todayByMember.values.filter { $0 > myScore }.count + 1

        // 周目标
        let weekStart = FamilyCalendar.periodStart(.week, at: now, timezoneID: tz)
        let weeklyScore = effective.filter { $0.createdAt >= weekStart }.reduce(0) { $0 + $1.points }

        // 快速加分：加分规则，按"我今日剩余次数多 + 分值适中"排序，取 8 个
        let positive = rules.filter { !$0.isDeduction && $0.isActive }
        let quick = positive.prefix(8)

        // 待我确认（家长视角）
        let pending = records
            .filter { $0.status == .pending && $0.createdAt >= todayStart.addingTimeInterval(-86400 * 2) }
            .sorted { $0.createdAt > $1.createdAt }

        // 今日待办：系统任务（默认日常规则）+ 家长指派
        let todayKey = FamilyCalendar.dayKey(now, timezoneID: tz)
        var items: [TaskAssignmentItem] = []
        let byID = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
        let rulesByID = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })
        for a in assignments where a.dueDay == todayKey && a.status == .open {
            if let rule = rulesByID[a.ruleID], let assignee = byID[a.assigneeID],
               rule.isActive, assignee.status == .active {
                items.append(TaskAssignmentItem(
                    id: a.id, rule: rule, assignee: assignee,
                    source: byID[a.assignerID].map { "@\($0.name) 指派" } ?? "指派", done: false))
            }
        }
        // 指派已完成：今日该成员该规则已 approved
        let doneAssignments = assignments.filter { $0.dueDay == todayKey && $0.status == .done }
        for a in doneAssignments {
            if let rule = rulesByID[a.ruleID], let assignee = byID[a.assigneeID] {
                items.append(TaskAssignmentItem(
                    id: a.id, rule: rule, assignee: assignee, source: "已完成", done: true))
            }
        }
        // 系统任务：无指派时的日常三件（倒垃圾/阅读/运动）
        if items.isEmpty {
            for name in ["倒垃圾", "阅读 30 分钟", "运动 30 分钟"] {
                if let rule = rules.first(where: { $0.name == name && $0.isActive }) {
                    items.append(TaskAssignmentItem(
                        id: UUID(), rule: rule, assignee: me, source: "系统", done: false))
                }
            }
        }

        // 家庭动态：最近 12 条
        let feedRecords = effective.sorted { $0.createdAt > $1.createdAt }.prefix(12)
        let feed = feedRecords.compactMap { r -> FeedItem? in
            guard let m = byID[r.memberID] else { return nil }
            let ruleName = r.ruleID.flatMap { rulesByID[$0]?.name } ?? (r.note ?? "记录")
            return FeedItem(id: r.id, member: m,
                            text: ruleName, points: r.points, time: r.createdAt)
        }

        return HomeSummary(
            familyToday: familyToday, myToday: myToday, myRank: rank,
            memberCount: todayByMember.count, streakDays: me.streakDays,
            weeklyGoal: family.settingsData.weeklyGoal, weeklyScore: weeklyScore,
            quickRules: Array(quick), pendingRecords: pending,
            todayAssignments: items, feed: feed)
    }
}

/// 统计页聚合
struct StatsSummary {
    var weekScore: Int
    var monthRank: Int
    var trend: [(day: String, score: Int)]       // 近 7 天
    var radar: [RuleCategory: Int]               // 本月各类得分
    var radarMax: Int
    var totalActive: Int

    static func compute(family: Family, me: Member, members: [Member],
                        records: [ScoreRecord], now: Date = .now) -> StatsSummary {
        let tz = family.timezoneID
        let effective = records.filter {
            $0.status == .approved || $0.status == .reversed || $0.status == .appealed
        }
        let mine = effective.filter { $0.memberID == me.id }

        let weekStart = FamilyCalendar.periodStart(.week, at: now, timezoneID: tz)
        let weekScore = mine.filter { $0.createdAt >= weekStart }.reduce(0) { $0 + $1.points }

        // 月排名
        let monthStart = FamilyCalendar.periodStart(.month, at: now, timezoneID: tz)
        let monthRecords = effective.filter { $0.createdAt >= monthStart }
        var byMember: [UUID: Int] = [:]
        for r in monthRecords { byMember[r.memberID, default: 0] += r.points }
        let myMonth = byMember[me.id] ?? 0
        let rank = byMember.values.filter { $0 > myMonth }.count + 1

        // 近 7 天趋势（周一~日，手动映射避免 locale 差异）
        let weekdayNames = [1: "日", 2: "一", 3: "二", 4: "三", 5: "四", 6: "五", 7: "六"]
        var trend: [(String, Int)] = []
        let cal = FamilyCalendar.calendar(timezoneID: tz)
        for i in (0..<7).reversed() {
            let day = cal.date(byAdding: .day, value: -i, to: now)!
            let start = cal.startOfDay(for: day)
            let end = start.addingTimeInterval(86400)
            let s = mine.filter { $0.createdAt >= start && $0.createdAt < end }.reduce(0) { $0 + $1.points }
            trend.append((weekdayNames[cal.component(.weekday, from: day)] ?? "", s))
        }

        // 雷达（本月分类）
        var radar: [RuleCategory: Int] = [:]
        for r in mine.filter({ $0.createdAt >= monthStart }) {
            radar[r.category, default: 0] += max(0, r.points)
        }
        let radarMax = max(10, (radar.values.max() ?? 10))

        return StatsSummary(weekScore: weekScore, monthRank: rank,
                            trend: trend, radar: radar, radarMax: radarMax,
                            totalActive: members.filter { $0.status == .active }.count)
    }
}
