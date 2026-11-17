import XCTest
import SwiftData
@testable import FamilyScore

/// v3.2 指派任务过期机制
final class TaskServiceTests: XCTestCase {

    var context: ModelContext!

    override func setUpWithError() throws {
        context = try TestDB.makeContext()
    }

    private func seedAssignment(dueOffsetDays: Int, status: AssignmentStatus = .open,
                                now: Date = .testNow) throws -> (Family, TaskAssignment) {
        let f = TestDB.makeFamily(context: context)
        let rule = TestDB.makeRule(f.family, points: 5, name: "遛宠物")
        context.insert(rule)
        let due = now.addingTimeInterval(Double(dueOffsetDays) * 86400)
        let a = TaskAssignment(familyID: f.family.id, ruleID: rule.id,
                               assigneeID: f.child.id, assignerID: f.mom.id,
                               dueDay: FamilyCalendar.dayKey(due, timezoneID: "UTC"))
        context.insert(a)
        a.status = status
        try context.save()
        return (f.family, a)
    }

    // MARK: 过期结算

    func testSettleExpired() throws {
        let (family, past) = try seedAssignment(dueOffsetDays: -1)
        let (_, today) = try seedAssignment(dueOffsetDays: 0)
        let (_, donePast) = try seedAssignment(dueOffsetDays: -2, status: .done)

        let settled = TaskService.settleExpired(family: family, context: context, now: .testNow)
        XCTAssertEqual(settled, 1)                        // 只有昨天 open 的被结算
        XCTAssertEqual(past.status, .expired)
        XCTAssertEqual(today.status, .open)               // 今日不动
        XCTAssertEqual(donePast.status, .done)            // 已完成不动

        // 幂等：再跑无新结算
        XCTAssertEqual(TaskService.settleExpired(family: family, context: context, now: .testNow), 0)
    }

    func testExpiredNotInTodayTodoButInRecentList() throws {
        let f = TestDB.makeFamily(context: context)
        let rule = TestDB.makeRule(f.family, points: 5, name: "遛宠物")
        context.insert(rule)
        let yesterday = FamilyCalendar.dayKey(.testNow.addingTimeInterval(-86400), timezoneID: "UTC")
        let a = TaskAssignment(familyID: f.family.id, ruleID: rule.id,
                               assigneeID: f.child.id, assignerID: f.mom.id, dueDay: yesterday)
        context.insert(a)
        a.status = .expired
        try context.save()

        // 近期过期列表包含它
        let recent = TaskService.expiredRecently(family: f.family, rules: [rule],
                                                 members: [f.child, f.mom],
                                                 context: context, now: .testNow)
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.ruleName, "遛宠物")
        XCTAssertEqual(recent.first?.assigneeName, "小明")     // TestDB 默认昵称
        // 今日待办不含过期任务
        let summary = HomeSummary.compute(
            family: f.family, me: f.mom, members: [f.mom, f.child], rules: [rule],
            records: [], assignments: [a], now: .testNow, context: context)
        XCTAssertFalse(summary.todayAssignments.contains { $0.id == a.id })
    }

    func testExpiredOutsideWindowExcluded() throws {
        let (family, _) = try seedAssignment(dueOffsetDays: -10, status: .expired)
        let recent = TaskService.expiredRecently(family: family, rules: [],
                                                 members: [], context: context, now: .testNow)
        XCTAssertTrue(recent.isEmpty)   // 3 天窗口外不再打扰
    }

    // MARK: 截止选项

    func testDueOptionsAndKey() {
        let tz = "UTC"
        let options = TaskService.dueOptions(now: .testNow, timezoneID: tz)
        XCTAssertEqual(options.first?.label, "今天")
        XCTAssertTrue(options.contains { $0.label == "自定义" })
        // 周一（testNow=2026-11-16 周一）→ 本周末=周五 11-20（+4 天）
        let weekend = options.first { $0.label == "本周末" }
        XCTAssertEqual(weekend?.daysFromNow, 4)
        let key = TaskService.dueDayKey(for: weekend!, customDate: nil, timezoneID: tz, now: .testNow)
        XCTAssertEqual(key, "2026-11-20")
        // 自定义
        var comps = DateComponents()
        comps.year = 2026; comps.month = 12; comps.day = 25
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let custom = cal.date(from: comps)!
        let customOpt = options.first { $0.daysFromNow == nil }!
        XCTAssertEqual(TaskService.dueDayKey(for: customOpt, customDate: custom,
                                             timezoneID: tz, now: .testNow), "2026-12-25")
    }
}
