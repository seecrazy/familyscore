import XCTest
import SwiftData
@testable import FamilyScore

/// 测试基建：内存库 + 标准家庭脚手架（§20.2）
enum TestDB {
    static func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Family.self, Member.self, Rule.self, ScoreRecord.self, Reward.self,
                Redemption.self, AuditLog.self, Badge.self, RankSnapshot.self,
                TaskAssignment.self, WishListItem.self, ScoreLot.self,
            configurations: config)
        return ModelContext(container)
    }

    /// 标准五口家庭（UTC 时区便于跨时区断言）。
    /// 默认关闭"全部打卡需评审"，引擎行为测试在免评审语境跑；评审流见 ReviewFlowTests。
    static func makeFamily(context: ModelContext,
                           timezoneID: String = "UTC") -> (family: Family, dad: Member, mom: Member, child: Member) {
        let familyID = UUID()
        let family = Family(name: "测试家", ownerID: UUID(), timezoneID: timezoneID)
        family.settingsData.requireReviewAll = false
        let dad = Member(familyID: familyID, name: "爸爸", emoji: "👨", role: .admin)
        let mom = Member(familyID: familyID, name: "妈妈", emoji: "👩", role: .admin)
        let child = Member(familyID: familyID, name: "小明", emoji: "👦", role: .child)
        family.ownerID = mom.id
        family.id = familyID
        context.insert(family); context.insert(dad); context.insert(mom); context.insert(child)
        return (family, dad, mom, child)
    }

    @discardableResult
    static func makeRule(_ family: Family, points: Int = 5, dailyLimit: Int = 0,
                         requiresApproval: Bool = false, category: RuleCategory = .chore,
                         name: String = "测试行为") -> Rule {
        let r = Rule(familyID: family.id, category: category, name: name, icon: "star",
                     points: points, dailyLimit: dailyLimit, requiresApproval: requiresApproval)
        return r
    }
}

/// 固定基准时间：2026-11-16 12:00 UTC（周一）
extension Date {
    static let testNow: Date = {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 11; comps.day = 16; comps.hour = 12
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: comps)!
    }()
}

final class ScoreEngineTests: XCTestCase {

    var context: ModelContext!

    override func setUpWithError() throws {
        context = try TestDB.makeContext()
    }

    // MARK: 计分公式（§20.2-1）

    func testFormulaRounding() {
        XCTAssertEqual(ScoreEngine.computedPoints(base: 5, coefficient: 1.0, multiplier: 1.0), 5)
        XCTAssertEqual(ScoreEngine.computedPoints(base: 5, coefficient: 1.2, multiplier: 1.0), 6)   // 6.0
        XCTAssertEqual(ScoreEngine.computedPoints(base: -5, coefficient: 1.2, multiplier: 1.0), -6) // 负分同规则
        XCTAssertEqual(ScoreEngine.computedPoints(base: 8, coefficient: 1.0, multiplier: 1.5), 12)
        XCTAssertEqual(ScoreEngine.computedPoints(base: 3, coefficient: 1.2, multiplier: 1.0), 4)   // 3.6 → 4
        XCTAssertEqual(ScoreEngine.computedPoints(base: 2, coefficient: 1.2, multiplier: 1.0), 2)   // 2.4 → 2
    }

    // MARK: 双轨入账（§20.2-5）

    func testDualTrackPositive() throws {
        let f = TestDB.makeFamily(context: context)
        let rule = TestDB.makeRule(f.family, points: 10)
        context.insert(rule)
        let outcome = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                             at: .testNow, actorIsAdmin: false, context: context)
        if case .approved(let rec) = outcome {
            XCTAssertEqual(rec.points, 12)                      // 10 × 1.2
            XCTAssertEqual(rec.basePoints, 10)                   // 快照
            XCTAssertEqual(rec.coefficient, 1.2, accuracy: 0.001)
            XCTAssertEqual(f.child.cumulativeScore, 12)
            XCTAssertEqual(f.child.availableScore, 12)
            XCTAssertEqual(f.child.streakDays, 1)
        } else { XCTFail("应当直接入账") }
    }

    func testDeductionOnlyAffectsAvailable() throws {
        let f = TestDB.makeFamily(context: context)
        let add = TestDB.makeRule(f.family, points: 30)
        let deduct = TestDB.makeRule(f.family, points: -6, name: "乱扔物品")
        context.insert(add); context.insert(deduct)
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: add,
                                   at: .testNow.addingTimeInterval(-3600), actorIsAdmin: false, context: context)
        try ScoreEngine.submit(member: f.child, family: f.family, rule: deduct,
                               at: .testNow, actorIsAdmin: true, approver: f.mom.id, context: context)
        // 儿童 −6×1.2 = −7.2 → −7
        XCTAssertEqual(f.child.cumulativeScore, 36)  // 只增不减
        XCTAssertEqual(f.child.availableScore, 29)   // 36 − 7
    }

    func testChildCannotDeduct() throws {
        let f = TestDB.makeFamily(context: context)
        let deduct = TestDB.makeRule(f.family, points: -3, name: "减分")
        context.insert(deduct)
        XCTAssertThrowsError(try ScoreEngine.submit(member: f.child, family: f.family, rule: deduct,
                                                    at: .testNow, actorIsAdmin: false, context: context)) { error in
            XCTAssertEqual(error as? ScoreEngineError, .onlyAdminCanDeduct)
        }
    }

    // MARK: 每日规则上限（§20.2-2）

    func testDailyRuleLimit() throws {
        let f = TestDB.makeFamily(context: context)
        let rule = TestDB.makeRule(f.family, points: 5, dailyLimit: 2)
        context.insert(rule)
        let t = Date.testNow
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                   at: t.addingTimeInterval(-7200), actorIsAdmin: false, context: context)
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                   at: t.addingTimeInterval(-3600), actorIsAdmin: false, context: context)
        XCTAssertThrowsError(try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                                    at: t, actorIsAdmin: false, context: context)) { error in
            if case .dailyLimitReached = error as? ScoreEngineError {} else {
                XCTFail("错误类型不对: \(error)")
            }
        }
        // 次日窗口重置
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                   at: t.addingTimeInterval(86400), actorIsAdmin: false, context: context)
        XCTAssertEqual(f.child.cumulativeScore, 6 * 3) // 儿童系数：round(5×1.2)=6
    }

    // MARK: 减分日上限 −20（§20.2-3）

    func testDeductionDailyCap() throws {
        let f = TestDB.makeFamily(context: context)
        // 先加分保证可用余额为正
        let add = TestDB.makeRule(f.family, points: 100, name: "初始")
        context.insert(add)
        _ = try ScoreEngine.submit(member: f.dad, family: f.family, rule: add,
                                   at: .testNow.addingTimeInterval(-4000), actorIsAdmin: true, context: context)
        let big = TestDB.makeRule(f.family, points: -15, name: "大减分")
        let small = TestDB.makeRule(f.family, points: -8, name: "小减分")
        context.insert(big); context.insert(small)
        try ScoreEngine.submit(member: f.dad, family: f.family, rule: big,
                               at: .testNow.addingTimeInterval(-2000), actorIsAdmin: true,
                               approver: f.dad.id, context: context) // −15
        // 再 −8 时只剩 5 额度 → 截断为 −5
        let outcome = try ScoreEngine.submit(member: f.dad, family: f.family, rule: small,
                                             at: .testNow, actorIsAdmin: true, approver: f.dad.id, context: context)
        if case .approved(let rec) = outcome {
            XCTAssertEqual(rec.points, -5)
            XCTAssertTrue(rec.note?.contains("每日减分上限") == true)
        } else { XCTFail("应入账") }
        XCTAssertEqual(f.dad.availableScore, 100 - 15 - 5)
    }

    // MARK: 5 分钟重复（§20.2-4）

    func testRepeatWindow() throws {
        let f = TestDB.makeFamily(context: context)
        let rule = TestDB.makeRule(f.family, points: 5)
        context.insert(rule)
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                   at: .testNow.addingTimeInterval(-120), actorIsAdmin: false, context: context)
        XCTAssertThrowsError(try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                                    at: .testNow, actorIsAdmin: false, context: context)) { error in
            if case .repeatWindow(let m) = error as? ScoreEngineError {
                XCTAssertEqual(m, 5)
            } else { XCTFail("错误类型不对: \(error)") }
        }
        // 二次确认放行
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                   at: .testNow, actorIsAdmin: false, forceRepeated: true, context: context)
    }

    // MARK: 凭证哈希当日去重（A4 实时拦截）

    func testDuplicateProofRejected() throws {
        let f = TestDB.makeFamily(context: context)
        let rule = TestDB.makeRule(f.family, points: 5)
        context.insert(rule)
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                   proofHash: "hash-abc", at: .testNow.addingTimeInterval(-6000),
                                   actorIsAdmin: false, context: context)
        // 不同规则、同人、同 hash、同日 → 拒绝
        let other = TestDB.makeRule(f.family, points: 3, name: "另一行为")
        context.insert(other)
        XCTAssertThrowsError(try ScoreEngine.submit(member: f.child, family: f.family, rule: other,
                                                    proofHash: "hash-abc", at: .testNow,
                                                    actorIsAdmin: false, forceRepeated: true, context: context)) { error in
            XCTAssertEqual(error as? ScoreEngineError, .duplicateProof)
        }
        // 次日同 hash 放行
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: other,
                                   proofHash: "hash-abc", at: .testNow.addingTimeInterval(86400),
                                   actorIsAdmin: false, forceRepeated: true, context: context)
    }

    // MARK: 待审批（§6.3）

    func testApprovalFlow() throws {
        let f = TestDB.makeFamily(context: context)
        let rule = TestDB.makeRule(f.family, points: 10, requiresApproval: true)
        context.insert(rule)
        let outcome = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                             at: .testNow, actorIsAdmin: false, context: context)
        guard case .pendingApproval(let rec) = outcome else { return XCTFail("应待审批") }
        XCTAssertEqual(rec.status, .pending)
        XCTAssertEqual(f.child.cumulativeScore, 0) // 未入账

        let approved = try ScoreEngine.approve(record: rec, family: f.family, by: f.mom, context: context)
        XCTAssertEqual(approved.status, .approved)
        XCTAssertEqual(f.child.cumulativeScore, 12) // 10×1.2

        // 拒绝路径
        let rec2 = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                          at: .testNow.addingTimeInterval(60), actorIsAdmin: false,
                                          forceRepeated: true, context: context)
        guard case .pendingApproval(let p2) = rec2 else { return XCTFail() }
        try ScoreEngine.reject(record: p2, family: f.family, by: f.mom, context: context)
        XCTAssertEqual(p2.status, .rejected)
        XCTAssertEqual(f.child.cumulativeScore, 12)
    }

    func testApproverDailyLimit() throws {
        let f = TestDB.makeFamily(context: context)
        let rule = TestDB.makeRule(f.family, points: 10, requiresApproval: true)
        context.insert(rule)
        var t = Date.testNow.addingTimeInterval(-41400) // 当日 00:30 UTC，20 条全在今日
        for _ in 0..<20 {
            let out = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule, at: t,
                                             actorIsAdmin: false, forceRepeated: true, context: context)
            if case .pendingApproval(let rec) = out {
                _ = try ScoreEngine.approve(record: rec, family: f.family, by: f.mom,
                                            at: t, context: context)
            }
            t.addTimeInterval(600)
        }
        // 第 21 条：妈妈已达上限
        let out21 = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                           at: t, actorIsAdmin: false, forceRepeated: true, context: context)
        guard case .pendingApproval(let rec21) = out21 else { return XCTFail() }
        XCTAssertThrowsError(try ScoreEngine.approve(record: rec21, family: f.family, by: f.mom, context: context)) { e in
            XCTAssertEqual(e as? ScoreEngineError, .approverDailyLimitReached)
        }
        // 爸爸未达上限，可确认
        _ = try ScoreEngine.approve(record: rec21, family: f.family, by: f.dad, context: context)
    }

    // MARK: 撤销（§20.2-5 反向记录）

    func testReverseGeneratesReversalRecord() throws {
        let f = TestDB.makeFamily(context: context)
        let rule = TestDB.makeRule(f.family, points: 10)
        context.insert(rule)
        let out = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                         at: .testNow, actorIsAdmin: false, context: context)
        guard case .approved(let rec) = out else { return XCTFail() }
        XCTAssertEqual(f.child.cumulativeScore, 12)

        let reversal = try ScoreEngine.reverse(record: rec, family: f.family, by: f.mom,
                                               reason: "误操作", context: context)
        XCTAssertEqual(reversal.points, -12)
        XCTAssertEqual(rec.status, .reversed)
        XCTAssertEqual(f.child.cumulativeScore, 0)   // 加分被回滚
        XCTAssertEqual(f.child.availableScore, 0)
        // 排行视角天然抵消：approved(12) + reversal(-12) = 0
        let effective = RankService.effectiveRecords(familyID: f.family.id, since: nil, context: context)
        XCTAssertEqual(effective.reduce(0) { $0 + $1.points }, 0)
    }

    func testReverseDeductionRestoresAvailable() throws {
        let f = TestDB.makeFamily(context: context)
        let add = TestDB.makeRule(f.family, points: 50, name: "加分")
        let deduct = TestDB.makeRule(f.family, points: -10, name: "减分")
        context.insert(add); context.insert(deduct)
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: add,
                                   at: .testNow.addingTimeInterval(-7000), actorIsAdmin: false, context: context)
        let out = try ScoreEngine.submit(member: f.child, family: f.family, rule: deduct,
                                         at: .testNow.addingTimeInterval(-6000), actorIsAdmin: true,
                                         approver: f.mom.id, context: context)
        guard case .approved(let drec) = out else { return XCTFail() }
        XCTAssertEqual(f.child.availableScore, 60 - 12) // 50×1.2=60；−10×1.2=−12
        _ = try ScoreEngine.reverse(record: drec, family: f.family, by: f.mom,
                                    reason: "和解", context: context)
        XCTAssertEqual(f.child.availableScore, 60)     // 撤销减分恢复 12 分
        XCTAssertEqual(f.child.cumulativeScore, 60)    // 加分 60；减分与撤销都不动累计
    }

    // MARK: 连续打卡（§20.2-6）

    func testStreakMilestones() throws {
        let f = TestDB.makeFamily(context: context)
        let rule = TestDB.makeRule(f.family, points: 3)
        context.insert(rule)
        var day = Date.testNow.addingTimeInterval(Double(-7) * 86400)
        for _ in 0..<7 { // 连续 7 天
            _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule, at: day,
                                       actorIsAdmin: false, forceRepeated: true, context: context)
            day.addTimeInterval(86400)
        }
        XCTAssertEqual(f.child.streakDays, 7)
        // 7 天奖励 +20：日分 3×1.2=4 → 28，+20 → 48
        XCTAssertEqual(f.child.cumulativeScore, 4 * 7 + 20)
        let badges = try context.fetch(FetchDescriptor<Badge>())
        XCTAssertTrue(badges.contains { $0.badgeKey == "streak7" })
        // 第 8 天再来不会重复发
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                   at: day, actorIsAdmin: false, forceRepeated: true, context: context)
        XCTAssertEqual(f.child.cumulativeScore, 4 * 8 + 20)
    }

    func testStreakBreaksOnGap() throws {
        let f = TestDB.makeFamily(context: context)
        let rule = TestDB.makeRule(f.family, points: 3)
        context.insert(rule)
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                   at: .testNow.addingTimeInterval(-2 * 86400),
                                   actorIsAdmin: false, context: context)
        XCTAssertEqual(f.child.streakDays, 1)
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                   at: .testNow, actorIsAdmin: false, context: context) // 隔了一天 → 重新计
        XCTAssertEqual(f.child.streakDays, 1)
    }

    func testStreakSameDayIdempotent() throws {
        let f = TestDB.makeFamily(context: context)
        let rule = TestDB.makeRule(f.family, points: 3)
        context.insert(rule)
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                   at: .testNow.addingTimeInterval(-3600),
                                   actorIsAdmin: false, context: context)
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                   at: .testNow, actorIsAdmin: false, forceRepeated: true, context: context)
        XCTAssertEqual(f.child.streakDays, 1) // 同日不叠加
    }
}
