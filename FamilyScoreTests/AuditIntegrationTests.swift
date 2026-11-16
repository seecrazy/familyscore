import XCTest
import SwiftData
@testable import FamilyScore

final class AuditServiceTests: XCTestCase {

    var context: ModelContext!

    override func setUpWithError() throws {
        context = try TestDB.makeContext()
    }

    // MARK: A1 单日得分突增（§13.1）

    func testA1SpikeDetected() throws {
        let f = TestDB.makeFamily(context: context)
        // 家庭日常：每天 20 分 × 10 天（日均 20 → 阈值 max(50, 60) = 60）
        let add = TestDB.makeRule(f.family, points: 10, name: "日常")
        context.insert(add)
        for d in 1...10 {
            _ = try ScoreEngine.submit(member: f.dad, family: f.family, rule: add,
                                       at: .testNow.addingTimeInterval(Double(-d) * 86400),
                                       actorIsAdmin: true, forceRepeated: true, context: context)
            _ = try ScoreEngine.submit(member: f.mom, family: f.family, rule: add,
                                       at: .testNow.addingTimeInterval(Double(-d) * 86400 + 3600),
                                       actorIsAdmin: true, forceRepeated: true, context: context)
        }
        // 小明爆分一天 +120
        let big = TestDB.makeRule(f.family, points: 120, name: "爆分")
        context.insert(big)
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: big,
                                   at: .testNow.addingTimeInterval(-3600), actorIsAdmin: false,
                                   context: context)
        let anomalies = AuditService.detectAnomalies(family: f.family, members: [f.dad, f.mom, f.child],
                                                     at: .testNow, context: context)
        XCTAssertTrue(anomalies.contains { $0.code == "A1" && $0.memberID == f.child.id })
        // 日常记录不误报
        XCTAssertFalse(anomalies.contains { $0.code == "A1" && $0.memberID == f.dad.id })
    }

    // MARK: A2 规则高频（同规则 ≥25 次/30 天）

    func testA2HighFrequencyRule() throws {
        let f = TestDB.makeFamily(context: context)
        let rule = TestDB.makeRule(f.family, points: 2, dailyLimit: 0, name: "高频行为")
        context.insert(rule)
        for i in 0..<26 {
            _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                       at: .testNow.addingTimeInterval(Double(-i) * 3600),
                                       actorIsAdmin: false, forceRepeated: true, context: context)
        }
        let anomalies = AuditService.detectAnomalies(family: f.family, members: [f.dad, f.mom, f.child],
                                                     at: .testNow, context: context)
        XCTAssertTrue(anomalies.contains { $0.code == "A2" && $0.detail.contains("高频行为") })
    }

    // MARK: A3 确认人单日超限（漏网统计）

    func testA3ApproverOverLimit() throws {
        let f = TestDB.makeFamily(context: context)
        let rule = TestDB.makeRule(f.family, points: 1, name: "微行为")
        context.insert(rule)
        // 21 条当天记录由妈妈确认（绕过 approve 的硬拦截直接写 approvedBy 模拟历史数据）
        for _ in 0..<21 {
            context.insert(ScoreRecord(
                familyID: f.family.id, memberID: f.child.id, ruleID: rule.id,
                points: 1, basePoints: 1, coefficient: 1.0, multiplier: 1.0,
                category: .chore, status: .approved, createdAt: .testNow.addingTimeInterval(-3600),
                approvedBy: f.mom.id))
        }
        try context.save()
        let anomalies = AuditService.detectAnomalies(family: f.family, members: [f.dad, f.mom, f.child],
                                                     at: .testNow, context: context)
        XCTAssertTrue(anomalies.contains { $0.code == "A3" })
    }

    // MARK: A4 凭证哈希重复（历史报告）

    func testA4DuplicateProof() throws {
        let f = TestDB.makeFamily(context: context)
        let rule = TestDB.makeRule(f.family, points: 5, name: "拍照行为")
        context.insert(rule)
        // 不同日期用同一 hash（绕过实时拦截）
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                   proofHash: "dup-1", at: .testNow.addingTimeInterval(-5 * 86400),
                                   actorIsAdmin: false, context: context)
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                   proofHash: "dup-1", at: .testNow.addingTimeInterval(-4 * 86400),
                                   actorIsAdmin: false, forceRepeated: true, context: context)
        let anomalies = AuditService.detectAnomalies(family: f.family, members: [f.dad, f.mom, f.child],
                                                     at: .testNow, context: context)
        XCTAssertTrue(anomalies.contains { $0.code == "A4" })
    }

    // MARK: A5 补录集中

    func testA5BackfillSpike() throws {
        let f = TestDB.makeFamily(context: context)
        let rule = TestDB.makeRule(f.family, points: 5, name: "补录行为")
        context.insert(rule)
        for i in 0..<6 {
            let rec = ScoreRecord(
                familyID: f.family.id, memberID: f.child.id, ruleID: rule.id,
                points: 6, basePoints: 5, coefficient: 1.2, multiplier: 1.0,
                category: .chore, status: .approved,
                createdAt: .testNow.addingTimeInterval(Double(-i) * 86400),
                backfilledAt: .testNow)
            context.insert(rec)
        }
        try context.save()
        let anomalies = AuditService.detectAnomalies(family: f.family, members: [f.dad, f.mom, f.child],
                                                     at: .testNow, context: context)
        XCTAssertTrue(anomalies.contains { $0.code == "A5" })
    }

    // MARK: A6 减分集中（关系健康）

    func testA6DeductionConcentration() throws {
        let f = TestDB.makeFamily(context: context)
        let deduct = TestDB.makeRule(f.family, points: -2, name: "小减分")
        context.insert(deduct)
        for i in 0..<15 {
            _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: deduct,
                                       at: .testNow.addingTimeInterval(Double(-i) * 86400),
                                       actorIsAdmin: true, approver: f.mom.id,
                                       forceRepeated: true, context: context)
        }
        let anomalies = AuditService.detectAnomalies(family: f.family, members: [f.dad, f.mom, f.child],
                                                     at: .testNow, context: context)
        print("A6DEBUG anomalies=\(anomalies.map { $0.code })")
        XCTAssertTrue(anomalies.contains { $0.code == "A6" && $0.memberID == f.child.id })
    }

    // MARK: 审计留痕

    func testAuditLogsWritten() throws {
        let f = TestDB.makeFamily(context: context)
        let rule = TestDB.makeRule(f.family, points: 5, name: "行为")
        context.insert(rule)
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                   at: .testNow, actorIsAdmin: false, context: context)
        let logs = AuditService.logs(familyID: f.family.id, context: context)
        XCTAssertTrue(logs.contains { $0.action == .add })
        try context.save()
    }
}

// MARK: - 集成：全链路（创建家庭 → 打卡 → 排行 → 兑换 → 撤销，§20.1）

final class IntegrationTests: XCTestCase {

    func testFullLoop() throws {
        let context = try TestDB.makeContext()

        // 1. 创建家庭（有老人模板）
        let (family, owner) = FamilyService.createFamily(
            name: "李家", myName: "李爸爸", myRole: .admin, myEmoji: "👨",
            template: .withElder, timezoneID: "Asia/Shanghai", context: context)
        XCTAssertEqual(family.name, "李家")
        XCTAssertEqual(owner.role, .admin)

        // 2. 规则与奖励模板就位
        let rules = FamilyService.activeRules(of: family, context: context)
        XCTAssertGreaterThanOrEqual(rules.count, 24) // 20 核心 + 4 老人包
        XCTAssertTrue(rules.contains { $0.name == "陪伴老人 30 分钟" })
        let rewards = FamilyService.rewards(of: family, context: context)
        XCTAssertEqual(rewards.count, 6)

        // 3. 加成员
        let kid = FamilyService.addMember(to: family, name: "小李", role: .child, emoji: "👧",
                                          context: context)
        XCTAssertEqual(kid.coefficient, 1.2, accuracy: 0.001)

        // 4. 打卡 → 家长确认 → 排行
        let dishRule = rules.first { $0.name == "洗碗" }!
        let outcome = try ScoreEngine.submit(member: kid, family: family, rule: dishRule,
                                             at: .testNow, actorIsAdmin: false, context: context)
        guard case .pendingApproval(let pending) = outcome else { return XCTFail("洗碗应待审批") }
        _ = try ScoreEngine.approve(record: pending, family: family, by: owner, context: context)
        let board = RankService.leaderboard(family: family, members: [owner, kid],
                                            period: .day, at: .testNow, context: context)
        XCTAssertEqual(board.first { $0.memberID == kid.id }?.score, 6)

        // 5. 兑换
        let ice = rewards.first { $0.title.contains("冰淇淋") }!
        XCTAssertThrowsError(try RewardService.redeem(member: kid, family: family, reward: ice,
                                                      context: context)) // 分不够
        let big = TestDB.makeRule(family, points: 200, name: "攒大分")
        context.insert(big)
        // createFamily 默认开启"全部打卡需评审"：儿童提交 → 家长评审后入账
        let bigOut = try ScoreEngine.submit(member: kid, family: family, rule: big,
                                            at: .testNow.addingTimeInterval(-60), actorIsAdmin: false,
                                            forceRepeated: true, context: context)
        if case .pendingApproval(let pendingBig) = bigOut {
            _ = try ScoreEngine.approve(record: pendingBig, family: family, by: owner, context: context)
        }
        let redemption = try RewardService.redeem(member: kid, family: family, reward: ice,
                                                  context: context)
        XCTAssertTrue(RewardService.isValidCode(redemption.code))

        // 6. 撤销误加分
        let rec = try context.fetch(FetchDescriptor<ScoreRecord>()).first { $0.points > 100 }!
        _ = try ScoreEngine.reverse(record: rec, family: family, by: owner, reason: "录错了",
                                    context: context)
        // 6 + 240 − 80(兑换) − 240(撤销) = −74：欠账如实记账，且 Σ批次 = 快照
        XCTAssertEqual(kid.availableScore, -74)
        XCTAssertEqual(RewardService.totalAvailable(memberID: kid.id, context: context), -74)

        // 7. 退出成员 → 不再参与排行
        FamilyService.exitMember(kid, context: context)
        let board2 = RankService.leaderboard(family: family, members: [owner, kid],
                                             period: .day, at: .testNow, context: context)
        XCTAssertFalse(board2.contains { $0.memberID == kid.id })
    }

    // MARK: 演示数据（体验模式）

    func testDemoDataBuild() throws {
        let context = try TestDB.makeContext()
        let (family, members) = DemoData.build(context: context, now: .testNow)
        XCTAssertEqual(family.isDemo, true)
        XCTAssertEqual(members.count, 5)
        XCTAssertEqual(family.name, "王家")

        let records = try context.fetch(FetchDescriptor<ScoreRecord>())
        XCTAssertGreaterThan(records.count, 150)   // 30 天 × 5 人 × 2-4 条
        // 排行榜可直接计算且非空
        let board = RankService.leaderboard(family: family, members: members,
                                            period: .month, at: .testNow, context: context)
        XCTAssertEqual(board.count, 5)
        // 有人有可用分可看商城
        XCTAssertTrue(members.contains { $0.availableScore > 0 })
        // 待办/兑换/心愿单就位
        XCTAssertFalse(try context.fetch(FetchDescriptor<TaskAssignment>()).isEmpty)
        XCTAssertFalse(try context.fetch(FetchDescriptor<Redemption>()).isEmpty)
        XCTAssertFalse(try context.fetch(FetchDescriptor<WishListItem>()).isEmpty)
    }

    // MARK: 模板包差异（§6.5）

    func testTemplateVariants() {
        XCTAssertEqual(RuleTemplateService.rules(for: .three).count, 20)
        XCTAssertEqual(RuleTemplateService.rules(for: .withElder).count, 24)
        XCTAssertEqual(RuleTemplateService.rules(for: .twoKids).count, 24)
        XCTAssertEqual(RuleTemplateService.rules(for: .custom).count, 0)
        XCTAssertTrue(RuleTemplateService.rules(for: .twoKids).contains { $0.name == "辅导弟弟妹妹功课" })
        XCTAssertEqual(RuleTemplateService.deductionRules.count, 6)
    }

    // MARK: 等级引擎（§6.2.1）

    func testLevelEngine() {
        XCTAssertEqual(LevelEngine.level(forCumulative: 0), 1)
        XCTAssertEqual(LevelEngine.level(forCumulative: 99), 1)
        XCTAssertEqual(LevelEngine.level(forCumulative: 100), 2)
        XCTAssertEqual(LevelEngine.level(forCumulative: 1500), 5)
        XCTAssertEqual(LevelEngine.level(forCumulative: 20000), 10)
        XCTAssertEqual(LevelEngine.level(forCumulative: 99999), 10)
        XCTAssertEqual(LevelEngine.title(forLevel: 5), "榜样星")
        XCTAssertEqual(LevelEngine.pointsToNext(score: 120), 180)
        XCTAssertNil(LevelEngine.pointsToNext(score: 25000))
        XCTAssertEqual(LevelEngine.progress(score: 200), 0.5, accuracy: 0.001)  // Lv2: 100→300 过半
        XCTAssertEqual(LevelEngine.progress(score: 1600), 100.0 / 1500, accuracy: 0.001) // Lv5: 1500→3000
    }
}
