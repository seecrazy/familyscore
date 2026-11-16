import XCTest
import SwiftData
@testable import FamilyScore

final class RankServiceTests: XCTestCase {

    var context: ModelContext!

    override func setUpWithError() throws {
        context = try TestDB.makeContext()
    }

    private func seed(_ pointsByMember: [Member: [(offsetSeconds: TimeInterval, points: Int, category: RuleCategory)]],
                      family: Family) throws {
        for (member, entries) in pointsByMember {
            for e in entries {
                context.insert(ScoreRecord(
                    familyID: family.id, memberID: member.id, ruleID: nil,
                    points: e.points, basePoints: e.points, coefficient: 1.0, multiplier: 1.0,
                    category: e.category, status: .approved,
                    createdAt: Date.testNow.addingTimeInterval(e.offsetSeconds)))
            }
        }
        try context.save()
    }

    // MARK: 周期起点按家庭时区（§20.2-7：UTC+8 与 UTC-5 双时区）

    func testWeekStartUsesFamilyTimezone() throws {
        // UTC 周日 2026-11-15 23:00 = 上海周一 07:00 → 上海时区下属于"本周"
        let f = TestDB.makeFamily(context: context, timezoneID: "Asia/Shanghai")
        var comps = DateComponents()
        comps.year = 2026; comps.month = 11; comps.day = 15; comps.hour = 23
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let sundayUTC = cal.date(from: comps)!
        try seed([f.child: [(offsetSeconds: sundayUTC.timeIntervalSince(.testNow), points: 10, category: .chore)]],
                 family: f.family)
        let eff = RankService.effectiveRecords(familyID: f.family.id,
                                               since: FamilyCalendar.periodStart(.week, at: .testNow, timezoneID: f.family.timezoneID),
                                               context: context)
        let week = RankService.leaderboard(family: f.family, members: [f.dad, f.mom, f.child],
                                           period: .week, at: .testNow, context: context)
        print("WKDEBUG tz=\(f.family.timezoneID) start=\(FamilyCalendar.periodStart(.week, at: .testNow, timezoneID: f.family.timezoneID)) effCount=\(eff.count) effPoints=\(eff.map { $0.points }) board=\(week.map { ($0.rank, $0.score) })")
        XCTAssertEqual(week.first { $0.memberID == f.child.id }?.score, 10)

        // 同一时刻在纽约时区还是周日 → 属于"上周"
        let fNY = TestDB.makeFamily(context: context, timezoneID: "America/New_York")
        try seed([fNY.child: [(offsetSeconds: sundayUTC.timeIntervalSince(.testNow), points: 10, category: .chore)]],
                 family: fNY.family)
        let weekNY = RankService.leaderboard(family: fNY.family, members: [fNY.dad, fNY.mom, fNY.child],
                                             period: .week, at: .testNow, context: context)
        XCTAssertEqual(weekNY.first { $0.memberID == fNY.child.id }?.score ?? 0, 0) // 周日记录在纽约属于上周
        let dayNY = RankService.leaderboard(family: fNY.family, members: [fNY.dad, fNY.mom, fNY.child],
                                            period: .day, at: .testNow, context: context)
        XCTAssertEqual(dayNY.first { $0.memberID == fNY.child.id }?.score ?? 0, 0) // 日榜（周一）不含上周日
    }

    func testDayPeriodBoundary() throws {
        let f = TestDB.makeFamily(context: context, timezoneID: "UTC")
        // 昨日 23:00 与今日 01:00
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!   // 家庭时区为 UTC
        let todayStart = cal.startOfDay(for: .testNow)
        try seed([f.child: [((todayStart.addingTimeInterval(-3600)).timeIntervalSince(.testNow), 8, .study),
                            ((todayStart.addingTimeInterval(3600)).timeIntervalSince(.testNow), 6, .study)]],
                 family: f.family)
        let day = RankService.leaderboard(family: f.family, members: [f.dad, f.mom, f.child],
                                          period: .day, at: .testNow, context: context)
        XCTAssertEqual(day.first { $0.memberID == f.child.id }?.score, 6)
    }

    // MARK: 排名与环比（§20.2-8：含并列）

    func testRankAndDeltaWithTie() throws {
        let f = TestDB.makeFamily(context: context, timezoneID: "UTC")
        // 上周（-3d = 上周五）：爸爸 30 妈妈 20 小明 10
        try seed([f.dad: [(-3 * 86400, 30, .chore)], f.mom: [(-3 * 86400, 20, .chore)],
                  f.child: [(-3 * 86400, 10, .chore)]], family: f.family)
        // 本周：小明 40 妈妈 40（并列第 1）爸爸 5
        try seed([f.child: [(-3600, 40, .study)], f.mom: [(-3600, 40, .chore)],
                  f.dad: [(-3600, 5, .health)]], family: f.family)

        let week = RankService.leaderboard(family: f.family, members: [f.dad, f.mom, f.child],
                                           period: .week, at: .testNow, context: context)
        let ming = week.first { $0.memberID == f.child.id }!
        let mom = week.first { $0.memberID == f.mom.id }!
        let dad = week.first { $0.memberID == f.dad.id }!
        XCTAssertEqual(Set([ming.rank, mom.rank]), [1])   // 并列第一
        XCTAssertEqual(dad.rank, 3)
        XCTAssertEqual(ming.delta, 1 - 3)                  // 第 3 → 第 1：delta = -2（上升 2 位）
        XCTAssertEqual(dad.delta, 3 - 1)                   // 第 1 → 第 3：+2
        XCTAssertEqual(mom.delta, 1 - 2)                   // 第 2 → 第 1：-1
    }

    // MARK: 退出成员不参与（§15）

    func testExitedMemberExcluded() throws {
        let f = TestDB.makeFamily(context: context, timezoneID: "UTC")
        try seed([f.child: [(-3600, 40, .study)]], family: f.family)
        f.child.status = .exited
        let day = RankService.leaderboard(family: f.family, members: [f.dad, f.mom, f.child],
                                          period: .day, at: .testNow, context: context)
        XCTAssertFalse(day.contains { $0.memberID == f.child.id })
    }

    // MARK: 进步榜（§14.1：新人不入榜）

    func testProgressBoardExcludesNewcomer() throws {
        let f = TestDB.makeFamily(context: context, timezoneID: "UTC")
        try seed([f.dad: [(-3 * 86400, 10, .chore), (-3600, 30, .chore)],   // 上周 10 → 本周 30
                  f.mom: [(-3 * 86400, 30, .chore), (-3600, 20, .chore)]],  // 上周 30 → 本周 20
                 family: f.family)
        // 小明只在本周有分（新人）
        try seed([f.child: [(-3600, 50, .study)]], family: f.family)
        let board = RankService.progressBoard(family: f.family, members: [f.dad, f.mom, f.child],
                                              period: .week, at: .testNow, context: context)
        XCTAssertEqual(board.count, 2)                       // 新人保护
        XCTAssertEqual(board.first?.memberID, f.dad.id)      // 涨幅 +20 > −10
        XCTAssertEqual(board.first?.score, 20)
    }

    // MARK: 分类冠军（§8.2）

    func testCategoryChampions() throws {
        let f = TestDB.makeFamily(context: context, timezoneID: "UTC")
        try seed([f.mom: [(-3600, 10, .chore), (-7200, 8, .chore)],
                  f.child: [(-3600, 20, .study)],
                  f.dad: [(-3600, 12, .health)]], family: f.family)
        let champions = RankService.categoryChampions(family: f.family, members: [f.dad, f.mom, f.child],
                                                      at: .testNow, context: context)
        XCTAssertEqual(champions.first { $0.category == .chore }?.memberID, f.mom.id)
        XCTAssertEqual(champions.first { $0.category == .study }?.memberID, f.child.id)
        XCTAssertEqual(champions.first { $0.category == .health }?.memberID, f.dad.id)
        XCTAssertNil(champions.first { $0.category == .emotion }?.memberID) // 无人得分 → nil
    }

    // MARK: 团队目标（首页）

    func testFamilyWeeklyScore() throws {
        let f = TestDB.makeFamily(context: context, timezoneID: "UTC")
        try seed([f.dad: [(-3600, 100, .chore)], f.mom: [(-7200, 150, .chore)]], family: f.family)
        let total = RankService.familyScore(family: f.family, period: .week, at: .testNow, context: context)
        XCTAssertEqual(total, 250)
    }
}

final class RewardServiceTests: XCTestCase {

    var context: ModelContext!

    override func setUpWithError() throws {
        context = try TestDB.makeContext()
    }

    // MARK: 兑换（§20.2-9）

    func testRedeemHappyPath() throws {
        let f = TestDB.makeFamily(context: context)
        let child = f.child
        let add = TestDB.makeRule(f.family, points: 100, name: "初始")
        context.insert(add)
        _ = try ScoreEngine.submit(member: child, family: f.family, rule: add,
                                   at: .testNow.addingTimeInterval(-7200), actorIsAdmin: false, context: context)
        let reward = Reward(familyID: f.family.id, title: "冰淇淋", icon: "icecream", cost: 80, stock: 2)
        context.insert(reward)

        let redemption = try RewardService.redeem(member: child, family: f.family, reward: reward,
                                                  at: .testNow, context: context)
        XCTAssertEqual(child.availableScore, 120 - 80)
        XCTAssertEqual(reward.stock, 1)
        XCTAssertTrue(redemption.code.hasPrefix("FS-"))
        XCTAssertEqual(redemption.code.count, 12) // "FS-" + 4 + "-" + 4
        XCTAssertTrue(RewardService.isValidCode(redemption.code))
        // FIFO：批次 120 → 剩 40
        XCTAssertEqual(RewardService.totalAvailable(memberID: child.id, context: context), 40)
    }

    func testRedeemInsufficient() throws {
        let f = TestDB.makeFamily(context: context)
        let reward = Reward(familyID: f.family.id, title: "零花钱", icon: "banknote", cost: 200, stock: -1)
        context.insert(reward)
        XCTAssertThrowsError(try RewardService.redeem(member: f.child, family: f.family, reward: reward,
                                                      context: context)) { e in
            XCTAssertEqual(e as? RewardError, .insufficient(need: 200, have: 0))
        }
    }

    func testRedeemOutOfStock() throws {
        let f = TestDB.makeFamily(context: context)
        let reward = Reward(familyID: f.family.id, title: "限量", icon: "gift", cost: 10, stock: 0)
        context.insert(reward)
        XCTAssertThrowsError(try RewardService.redeem(member: f.dad, family: f.family, reward: reward,
                                                      context: context)) { e in
            XCTAssertEqual(e as? RewardError, .outOfStock)
        }
    }

    func testDiscountCost() throws {
        let f = TestDB.makeFamily(context: context)
        let reward = Reward(familyID: f.family.id, title: "电影", icon: "film", cost: 150,
                            discountCost: 120, discountEndsAt: .testNow.addingTimeInterval(86400), stock: -1)
        context.insert(reward)
        let add = TestDB.makeRule(f.family, points: 120, name: "攒分")
        context.insert(add)
        _ = try ScoreEngine.submit(member: f.dad, family: f.family, rule: add,
                                   at: .testNow.addingTimeInterval(-7200), actorIsAdmin: true, context: context)
        // 折扣期内 120 可兑（原价 150 不够）
        _ = try RewardService.redeem(member: f.dad, family: f.family, reward: reward,
                                     at: .testNow, context: context)
        XCTAssertEqual(f.dad.availableScore, 0)
    }

    // MARK: 核销码（§22.2）

    func testCodeDeterministicAndValid() {
        let a = RewardService.generateCode(seed: 42)
        let b = RewardService.generateCode(seed: 42)
        XCTAssertEqual(a, b)                       // 种子确定 → 可复现
        XCTAssertNotEqual(a, RewardService.generateCode(seed: 43))
        XCTAssertTrue(RewardService.isValidCode(a))
        XCTAssertFalse(RewardService.isValidCode("FS-AAAA-BBBB"))
        XCTAssertFalse(RewardService.isValidCode(a + "X"))
        // 篡改任意一位 → 校验失败（抽查）
        var chars = Array(a)
        let idx = chars.firstIndex(of: "-").map { $0 + 1 } ?? 3
        chars[idx] = chars[idx] == "A" ? "B" : "A"
        XCTAssertFalse(RewardService.isValidCode(String(chars)))
    }

    func testCodeAlphabetExcludesConfusables() {
        for seed in UInt64(0)...50 {
            let code = RewardService.generateCode(seed: seed * 7919)
            XCTAssertFalse(code.contains("I") || code.contains("L") || code.contains("O") || code.contains("U"),
                           "混淆字符出现在 \(code)")
        }
    }

    // MARK: 兑换确认与退分

    func testConfirmAndCancelRedemption() throws {
        let f = TestDB.makeFamily(context: context)
        let add = TestDB.makeRule(f.family, points: 100, name: "初始")
        context.insert(add)
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: add,
                                   at: .testNow.addingTimeInterval(-7200), actorIsAdmin: false, context: context)
        let reward = Reward(familyID: f.family.id, title: "免家务", icon: "figure.wave", cost: 50, stock: -1)
        context.insert(reward)
        let r = try RewardService.redeem(member: f.child, family: f.family, reward: reward,
                                         at: .testNow, context: context)
        XCTAssertEqual(r.status, .pending)
        try RewardService.confirm(r, by: f.mom, context: context)
        XCTAssertEqual(r.status, .confirmed)

        let r2 = try RewardService.redeem(member: f.child, family: f.family, reward: reward,
                                          at: .testNow.addingTimeInterval(60), context: context)
        try RewardService.cancel(r2, family: f.family, context: context)
        XCTAssertEqual(r2.status, .cancelled)
        XCTAssertEqual(f.child.availableScore, 120 - 50) // 第二笔退回
    }

    // MARK: 批次过期：满 12 个月打五折（§20.2-10）

    func testLotExpiryHalvesAfter12Months() throws {
        let f = TestDB.makeFamily(context: context)
        let add = TestDB.makeRule(f.family, points: 100, name: "初始")
        context.insert(add)
        // 13 个月前的批次
        let old = Date.testNow.addingTimeInterval(-13 * 30.4 * 86400)
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: add, at: old,
                                   actorIsAdmin: false, forceRepeated: true, context: context)
        let lots = try context.fetch(FetchDescriptor<ScoreLot>())
        XCTAssertEqual(lots.count, 1)
        let reports = try RewardService.expireLots(member: f.child, at: .testNow,
                                                   timezoneID: "UTC", context: context)
        XCTAssertEqual(reports.first?.keptAmount, 60)   // 120 × 0.5
        XCTAssertEqual(reports.first?.halvedAmount, 60)
        XCTAssertEqual(f.child.availableScore, 60)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ScoreLot>()).first!.isPermanent)
        // 幂等：再跑一次无新报告
        XCTAssertTrue(try RewardService.expireLots(member: f.child, at: .testNow,
                                                   timezoneID: "UTC", context: context).isEmpty)
    }

    func testExpiringReminderWindow() throws {
        let f = TestDB.makeFamily(context: context)
        let add = TestDB.makeRule(f.family, points: 100, name: "初始")
        context.insert(add)
        // 11.5 个月前的批次 → 进入 30 天提醒窗口
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: add,
                                   at: .testNow.addingTimeInterval(-11.5 * 30.4 * 86400),
                                   actorIsAdmin: false, forceRepeated: true, context: context)
        let expiring = RewardService.expiringLots(member: f.child, at: .testNow,
                                                  timezoneID: "UTC", context: context)
        XCTAssertEqual(expiring.count, 1)
        // 新批次不在窗口
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: add,
                                   at: .testNow, actorIsAdmin: false, forceRepeated: true, context: context)
        let expiring2 = RewardService.expiringLots(member: f.child, at: .testNow,
                                                   timezoneID: "UTC", context: context)
        XCTAssertEqual(expiring2.count, 1)
    }

    // MARK: FIFO 扣批次

    func testFIFODeductOldestFirst() throws {
        let f = TestDB.makeFamily(context: context)
        let add = TestDB.makeRule(f.family, points: 100, name: "初始")
        context.insert(add)
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: add,
                                   at: .testNow.addingTimeInterval(-40 * 86400), // 上月批次
                                   actorIsAdmin: false, forceRepeated: true, context: context)
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: add,
                                   at: .testNow.addingTimeInterval(-3600), // 本月批次
                                   actorIsAdmin: false, forceRepeated: true, context: context)
        let reward = Reward(familyID: f.family.id, title: "扣分", icon: "gift", cost: 130, stock: -1)
        context.insert(reward)
        _ = try RewardService.redeem(member: f.child, family: f.family, reward: reward,
                                     at: .testNow, context: context)
        let lots = try context.fetch(FetchDescriptor<ScoreLot>()).sorted { $0.monthKey < $1.monthKey }
        XCTAssertEqual(lots.first?.amount, 0)  // 旧批次扣光
        XCTAssertEqual(lots.last?.amount, 110) // 旧批 120 扣光 + 新批 120 扣 10
    }
}
