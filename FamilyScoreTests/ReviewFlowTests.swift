import XCTest
import SwiftData
@testable import FamilyScore

/// v2.1 评审流：全局评审开关、家长自审、凭证图片与哈希、指派联动、管理员/重加入/生日/退出体验
final class ReviewFlowTests: XCTestCase {

    var context: ModelContext!

    override func setUpWithError() throws {
        context = try TestDB.makeContext()
    }

    // MARK: 全局评审开关（需求 2）

    func testChildCheckInNeedsReviewWhenEnabled() throws {
        let f = TestDB.makeFamily(context: context)
        f.family.settingsData.requireReviewAll = true // 默认策略
        let rule = TestDB.makeRule(f.family, points: 5, requiresApproval: false)
        context.insert(rule)
        let outcome = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                             at: .testNow, actorIsAdmin: false, context: context)
        guard case .pendingApproval(let rec) = outcome else { return XCTFail("儿童打卡应待评审") }
        XCTAssertEqual(f.child.cumulativeScore, 0)
        _ = try ScoreEngine.approve(record: rec, family: f.family, by: f.mom, context: context)
        XCTAssertEqual(f.child.cumulativeScore, 6)
    }

    func testAdminSelfSubmissionAutoApproved() throws {
        let f = TestDB.makeFamily(context: context)
        f.family.settingsData.requireReviewAll = true
        let rule = TestDB.makeRule(f.family, points: 10, requiresApproval: true)
        context.insert(rule)
        // 家长本人打卡：approver 给出 → 当场评审通过（"至少一人评审"= 自己）
        let outcome = try ScoreEngine.submit(member: f.mom, family: f.family, rule: rule,
                                             at: .testNow, actorIsAdmin: true,
                                             approver: f.mom.id, context: context)
        if case .approved(let rec) = outcome {
            XCTAssertEqual(rec.approvedBy, f.mom.id)
            XCTAssertEqual(f.mom.cumulativeScore, 10)
        } else { XCTFail("家长本人提交应直通") }
    }

    func testReviewAllDisabledFallsBackToRuleFlag() throws {
        let f = TestDB.makeFamily(context: context) // requireReviewAll = false
        let plain = TestDB.makeRule(f.family, points: 5, requiresApproval: false, name: "普通")
        let guarded = TestDB.makeRule(f.family, points: 8, requiresApproval: true, name: "需确认")
        context.insert(plain); context.insert(guarded)
        if case .approved = try ScoreEngine.submit(member: f.child, family: f.family, rule: plain,
                                                   at: .testNow, actorIsAdmin: false, context: context) {} else {
            XCTFail("开关关闭且规则不要求确认 → 直通")
        }
        if case .pendingApproval = try ScoreEngine.submit(member: f.child, family: f.family, rule: guarded,
                                                          at: .testNow, actorIsAdmin: false, context: context) {} else {
            XCTFail("规则要求确认 → 待评审")
        }
    }

    // MARK: 拍照凭证（需求 2）：存储缩略 + 内容哈希去重

    private func solidJPEG(_ rgb: (CGFloat, CGFloat, CGFloat)) -> Data {
        let size = CGSize(width: 300, height: 300)
        let r = UIGraphicsImageRenderer(size: size)
        let img = r.image { ctx in
            UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return img.jpegData(compressionQuality: 0.9)!
    }

    func testProofStoredAndDedupedSameDay() throws {
        let f = TestDB.makeFamily(context: context)
        f.family.settingsData.requireReviewAll = true
        let rule = TestDB.makeRule(f.family, points: 5, name: "拍照行为")
        context.insert(rule)
        let proof = solidJPEG((0.2, 0.7, 0.3))
        let out = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                         proofImageData: proof, at: .testNow,
                                         actorIsAdmin: false, context: context)
        guard case .pendingApproval(let rec) = out else { return XCTFail() }
        XCTAssertNotNil(rec.proofImageData, "凭证缩略图应随记录存储")
        XCTAssertLessThanOrEqual(rec.proofImageData!.count, 200_000, "凭证应压缩到 ≤200KB")
        XCTAssertEqual(rec.proofHash, ScoreEngine.contentHash(proof)) // 去重哈希基于原图

        // 同一张图当天二次提交（不同规则）→ A4 实时拒绝
        let other = TestDB.makeRule(f.family, points: 3, name: "另一行为")
        context.insert(other)
        XCTAssertThrowsError(try ScoreEngine.submit(member: f.child, family: f.family, rule: other,
                                                    proofImageData: proof,
                                                    at: .testNow.addingTimeInterval(600),
                                                    actorIsAdmin: false, forceRepeated: true,
                                                    context: context)) { e in
            XCTAssertEqual(e as? ScoreEngineError, .duplicateProof)
        }
        // 家长能看到凭证图
        XCTAssertNotNil(UIImage(data: rec.proofImageData!))
    }

    func testDifferentPhotosAllowed() throws {
        let f = TestDB.makeFamily(context: context)
        f.family.settingsData.requireReviewAll = true
        let rule = TestDB.makeRule(f.family, points: 5, name: "拍照行为")
        context.insert(rule)
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                   proofImageData: solidJPEG((0.9, 0.2, 0.2)),
                                   at: .testNow, actorIsAdmin: false, context: context)
        _ = try ScoreEngine.submit(member: f.dad, family: f.family, rule: rule,
                                   proofImageData: solidJPEG((0.1, 0.2, 0.9)),
                                   at: .testNow, actorIsAdmin: true, approver: f.dad.id,
                                   context: context) // 不同图不拦
    }

    // MARK: 指派任务联动（需求 1）：审批通过自动关待办

    func testApprovalClosesAssignment() throws {
        let f = TestDB.makeFamily(context: context)
        f.family.settingsData.requireReviewAll = true
        let rule = TestDB.makeRule(f.family, points: 8, name: "阅读 30 分钟")
        context.insert(rule)
        let todayKey = FamilyCalendar.dayKey(.testNow, timezoneID: "UTC")
        let assignment = TaskAssignment(familyID: f.family.id, ruleID: rule.id,
                                        assigneeID: f.child.id, assignerID: f.mom.id, dueDay: todayKey)
        context.insert(assignment)

        let out = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                         at: .testNow, actorIsAdmin: false, context: context)
        guard case .pendingApproval(let rec) = out else { return XCTFail() }
        XCTAssertEqual(assignment.status, .open) // 评审前待办保持开放
        _ = try ScoreEngine.approve(record: rec, family: f.family, by: f.mom, context: context)
        XCTAssertEqual(assignment.status, .done, "评审通过后当日指派自动完成")
    }

    // MARK: 管理员设置（需求 3）

    func testSetAdminPermissions() throws {
        let f = TestDB.makeFamily(context: context)
        // 非创建者不能设管理员
        XCTAssertFalse(FamilyService.setAdmin(f.child, family: f.family, by: f.dad,
                                              isAdmin: true, context: context))
        // 创建者是 mom
        XCTAssertTrue(FamilyService.setAdmin(f.child, family: f.family, by: f.mom,
                                             isAdmin: true, context: context))
        XCTAssertEqual(f.child.role, .admin)
        XCTAssertTrue(FamilyService.setAdmin(f.child, family: f.family, by: f.mom,
                                             isAdmin: false, context: context))
        XCTAssertEqual(f.child.role, .child)
        // 创建者不能自除
        XCTAssertFalse(FamilyService.setAdmin(f.mom, family: f.family, by: f.mom,
                                              isAdmin: false, context: context))
    }

    // MARK: 退出成员重新加入（需求 5）

    func testRejoinRestoresActive() throws {
        let f = TestDB.makeFamily(context: context)
        FamilyService.exitMember(f.child, context: context)
        XCTAssertEqual(f.child.status, .exited)
        FamilyService.rejoin(f.child, context: context)
        XCTAssertEqual(f.child.status, .active)
    }

    // MARK: 生日（需求 6）

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var comps = DateComponents(); comps.year = y; comps.month = m; comps.day = d; comps.hour = 12
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: comps)!
    }

    func testBirthdayUpcoming() throws {
        let f = TestDB.makeFamily(context: context)
        let now = date(2026, 11, 16)
        f.mom.birthday = date(1992, 11, 16)      // 今天
        f.child.birthday = date(2015, 11, 19)    // 3 天后
        f.dad.birthday = date(1988, 5, 1)        // 远期，不入列
        let ups = BirthdayService.upcoming(members: [f.dad, f.mom, f.child],
                                           family: f.family, now: now, withinDays: 7)
        XCTAssertEqual(ups.count, 2)
        XCTAssertTrue(ups[0].isToday)
        XCTAssertEqual(ups[0].member.id, f.mom.id)
        XCTAssertEqual(ups[1].daysLeft, 3)
    }

    func testBirthdayWrapYear() throws {
        let f = TestDB.makeFamily(context: context)
        f.dad.birthday = date(1988, 12, 30)
        let now = date(2026, 12, 28)
        let ups = BirthdayService.upcoming(members: [f.dad], family: f.family, now: now, withinDays: 7)
        XCTAssertEqual(ups.first?.daysLeft, 2)
        let after = date(2026, 12, 31) // 已过 → 明年
        let ups2 = BirthdayService.upcoming(members: [f.dad], family: f.family, now: after, withinDays: 400)
        XCTAssertEqual(ups2.first?.daysLeft, 364) // 2026-12-31 → 2027-12-30
    }

    // MARK: 退出体验模式（需求 4）

    func testExitDemoModePurgesEverything() throws {
        let (family, members) = DemoData.build(context: context, now: .testNow)
        XCTAssertGreaterThan(try context.fetch(FetchDescriptor<ScoreRecord>()).count, 100)
        FamilyService.exitDemoMode(context: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Family>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Member>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScoreRecord>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScoreLot>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Redemption>()).count, 0)
        _ = family; _ = members
    }
}
