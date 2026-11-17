import XCTest
@testable import FamilyScore

/// v3.0 通知规划器（纯函数）：触发时刻 / 免打扰顺延 / 各类条件
final class NotificationPlannerTests: XCTestCase {

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d; comps.hour = h; comps.minute = min
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: comps)!
    }

    // MARK: 基础

    func testMasterOffKillsAll() {
        var s = NotificationSettings(); s.master = false
        var ctx = NotificationContext(timezoneID: "UTC")
        ctx.openTodoCount = 3; ctx.pendingApprovalCount = 5; ctx.protectMemberName = "小明"
        ctx.protectStreakDays = 5; ctx.weeklyChampionName = "妈妈"
        XCTAssertTrue(NotificationPlanner.plans(settings: s, ctx: ctx, now: .testNow).isEmpty)
    }

    // MARK: 待办 19:00

    func testTodoAt19() {
        var ctx = NotificationContext(timezoneID: "UTC")
        ctx.openTodoCount = 2; ctx.todoExampleTitle = "倒垃圾"
        let plans = NotificationPlanner.plans(settings: NotificationSettings(), ctx: ctx,
                                              now: date(2026, 11, 16, 10)) // 周一 10:00
        let todo = plans.first { $0.id == "fs-todo" }
        XCTAssertEqual(todo?.fireDate, date(2026, 11, 16, 19))
        XCTAssertTrue(todo?.title.contains("2 件") == true)
    }

    func testTodoSkippedIfPast19() {
        var ctx = NotificationContext(timezoneID: "UTC"); ctx.openTodoCount = 1
        let plans = NotificationPlanner.plans(settings: NotificationSettings(), ctx: ctx,
                                              now: date(2026, 11, 16, 20))
        XCTAssertNil(plans.first { $0.id == "fs-todo" })
    }

    func testTodoOffByCategory() {
        var s = NotificationSettings(); s.todo = false
        var ctx = NotificationContext(timezoneID: "UTC"); ctx.openTodoCount = 1
        let plans = NotificationPlanner.plans(settings: s, ctx: ctx, now: date(2026, 11, 16, 10))
        XCTAssertNil(plans.first { $0.id == "fs-todo" })
    }

    // MARK: 生日（当天/前一天 9:00）

    func testBirthdayTodayAndTomorrow() {
        var ctx = NotificationContext(timezoneID: "UTC")
        ctx.birthdays = [("妈妈", true, 0), ("小明", false, 1), ("爸爸", false, 10)]
        let plans = NotificationPlanner.plans(settings: NotificationSettings(), ctx: ctx,
                                              now: date(2026, 11, 16, 8))
        XCTAssertEqual(plans.filter { $0.id.hasPrefix("fs-birthday") }.count, 2) // 10 天的不排
        XCTAssertTrue(plans.contains { $0.title.contains("今天是妈妈的生日") })
        XCTAssertTrue(plans.contains { $0.title.contains("明天是小明的生日") })
    }

    // MARK: 审批聚合（2 小时后）

    func testApprovalAggregatedIn2h() {
        var ctx = NotificationContext(timezoneID: "UTC"); ctx.pendingApprovalCount = 7
        let now = date(2026, 11, 16, 14)
        let plans = NotificationPlanner.plans(settings: NotificationSettings(), ctx: ctx, now: now)
        XCTAssertEqual(plans.first { $0.id == "fs-approval" }?.fireDate,
                       date(2026, 11, 16, 16))
        XCTAssertTrue(plans.first { $0.id == "fs-approval" }?.title.contains("7 条") == true)
    }

    // MARK: 周五 20:00 结算

    func testWeeklyFriday20() {
        var ctx = NotificationContext(timezoneID: "UTC")
        ctx.weeklyChampionName = "小明"; ctx.weeklyFamilyScore = 512
        // 周一 11-16 → 本周五 = 11-20
        let plans = NotificationPlanner.plans(settings: NotificationSettings(), ctx: ctx,
                                              now: date(2026, 11, 16, 10))
        XCTAssertEqual(plans.first { $0.id == "fs-weekly" }?.fireDate, date(2026, 11, 20, 20))
        // 周五当天 19:00 看 → 当晚 20:00 仍可排
        let plans2 = NotificationPlanner.plans(settings: NotificationSettings(), ctx: ctx,
                                               now: date(2026, 11, 20, 19))
        XCTAssertEqual(plans2.first { $0.id == "fs-weekly" }?.fireDate, date(2026, 11, 20, 20))
        // 周五 21:00 看 → 下周五
        let plans3 = NotificationPlanner.plans(settings: NotificationSettings(), ctx: ctx,
                                               now: date(2026, 11, 20, 21))
        XCTAssertEqual(plans3.first { $0.id == "fs-weekly" }?.fireDate, date(2026, 11, 27, 20))
    }

    // MARK: 打卡保护（streak≥3，21:00）

    func testStreakProtectRequires3Days() {
        var ctx = NotificationContext(timezoneID: "UTC")
        ctx.protectMemberName = "小明"; ctx.protectStreakDays = 2
        var plans = NotificationPlanner.plans(settings: NotificationSettings(), ctx: ctx,
                                              now: date(2026, 11, 16, 10))
        XCTAssertNil(plans.first { $0.id == "fs-streak" })

        ctx.protectStreakDays = 3
        plans = NotificationPlanner.plans(settings: NotificationSettings(), ctx: ctx,
                                          now: date(2026, 11, 16, 10))
        XCTAssertEqual(plans.first { $0.id == "fs-streak" }?.fireDate, date(2026, 11, 16, 21))
    }

    // MARK: 积分到期三档

    func testExpiryTiers() {
        var ctx = NotificationContext(timezoneID: "UTC")
        ctx.expiringLots = [("小明", amount: 120, daysLeft: 25),
                            ("妈妈", amount: 60, daysLeft: 5),
                            ("爸爸", amount: 30, daysLeft: 1),
                            ("弟弟", amount: 90, daysLeft: 45)]
        let plans = NotificationPlanner.plans(settings: NotificationSettings(), ctx: ctx,
                                              now: date(2026, 11, 16, 8))
        let expiry = plans.filter { $0.id.hasPrefix("fs-expiry") }
        XCTAssertEqual(expiry.count, 3) // 45 天的不排
        XCTAssertTrue(expiry.contains { $0.title.contains("一个月内到期") })
        XCTAssertTrue(expiry.contains { $0.title.contains("一周内到期") })
        XCTAssertTrue(expiry.contains { $0.title.contains("明天就到期") })
        // 到期当天 10:00 触发
        XCTAssertEqual(expiry.first { $0.title.contains("爸爸") }?.fireDate, date(2026, 11, 17, 10))
    }

    // MARK: 免打扰顺延（默认 22:00–07:00）

    func testQuietHoursDefer() {
        var s = NotificationSettings()
        s.approval = true
        var ctx = NotificationContext(timezoneID: "UTC"); ctx.pendingApprovalCount = 1
        // 23:00 有 pending → 2h 后是 01:00（免打扰）→ 顺延到 07:00
        let now = date(2026, 11, 16, 23)
        let plans = NotificationPlanner.plans(settings: s, ctx: ctx, now: now)
        XCTAssertEqual(plans.first { $0.id == "fs-approval" }?.fireDate, date(2026, 11, 17, 7))
        // 15:00 → 17:00 正常
        let plans2 = NotificationPlanner.plans(settings: s, ctx: ctx, now: date(2026, 11, 16, 15))
        XCTAssertEqual(plans2.first { $0.id == "fs-approval" }?.fireDate, date(2026, 11, 16, 17))
    }

    func testQuietAdjustedCrossMidnightAndSameDay() {
        let s = NotificationSettings() // 22:00–07:00
        // 23:30 → 次日 07:00
        XCTAssertEqual(NotificationPlanner.quietAdjusted(date(2026, 11, 16, 23, 30), settings: s, timezoneID: "UTC"),
                       date(2026, 11, 17, 7))
        // 06:00 → 当天 07:00
        XCTAssertEqual(NotificationPlanner.quietAdjusted(date(2026, 11, 16, 6), settings: s, timezoneID: "UTC"),
                       date(2026, 11, 16, 7))
        // 12:00 不动
        XCTAssertEqual(NotificationPlanner.quietAdjusted(date(2026, 11, 16, 12), settings: s, timezoneID: "UTC"),
                       date(2026, 11, 16, 12))
        // 不跨午夜配置 13:00–15:00：14:00 → 15:00
        var s2 = NotificationSettings()
        s2.quietStartMinutes = 13 * 60; s2.quietEndMinutes = 15 * 60
        XCTAssertEqual(NotificationPlanner.quietAdjusted(date(2026, 11, 16, 14), settings: s2, timezoneID: "UTC"),
                       date(2026, 11, 16, 15))
        // 边界：22:00 整点算免打扰；07:00 整点已放出
        XCTAssertEqual(NotificationPlanner.quietAdjusted(date(2026, 11, 16, 22), settings: s, timezoneID: "UTC"),
                       date(2026, 11, 17, 7))
        XCTAssertEqual(NotificationPlanner.quietAdjusted(date(2026, 11, 16, 7), settings: s, timezoneID: "UTC"),
                       date(2026, 11, 16, 7))
    }

    // MARK: 设置存取 roundtrip

    func testSettingsRoundtrip() {
        var s = NotificationSettings()
        s.todo = false; s.quietStartMinutes = 23 * 60; s.quietEndMinutes = 8 * 60
        s.save()
        let loaded = NotificationSettings.load()
        XCTAssertEqual(loaded, s)
        // 恢复默认
        var fresh = NotificationSettings()
        fresh.save()
    }
}
