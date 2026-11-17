import XCTest
import SwiftData
@testable import FamilyScore

/// v3.0 数据导出/导入：roundtrip、分家子集、幂等合并
final class ExportTests: XCTestCase {

    func testRoundtripAndIdempotentImport() throws {
        // 源家庭
        let src = try TestDB.makeContext()
        let (family, owner, mom, child) = TestDB.makeFamily(context: src)
        let rule = TestDB.makeRule(family, points: 10)
        src.insert(rule)
        _ = try ScoreEngine.submit(member: child, family: family, rule: rule,
                                   at: .testNow, actorIsAdmin: false, context: src)
        let reward = Reward(familyID: family.id, title: "冰淇淋", icon: "icecream", cost: 80)
        src.insert(reward)

        // 导出 → 编码 → 解码
        let bundle = try ExportService.export(family: family, context: src)
        XCTAssertEqual(bundle.members.count, 3)
        XCTAssertEqual(bundle.records.count, 1)
        XCTAssertEqual(bundle.rewards.count, 1)
        let data = try ExportService.encode(bundle)
        let decoded = try ExportService.decode(data)

        // 导入到全新库
        let dst = try TestDB.makeContext()
        let report1 = try ExportService.import(decoded, context: dst)
        XCTAssertEqual(report1.membersImported, 3)
        XCTAssertEqual(report1.recordsImported, 1)
        XCTAssertEqual(report1.rewardsImported, 1)

        // 数据一致：排行视角分数相同
        let dstFamily = try dst.fetch(FetchDescriptor<Family>()).first!
        let dstMembers = try dst.fetch(FetchDescriptor<Member>())
        let board = RankService.leaderboard(family: dstFamily, members: dstMembers,
                                            period: .day, at: .testNow, context: dst)
        XCTAssertEqual(board.first { $0.memberID == child.id }?.score, 12)

        // 幂等：重复导入不产生重复
        let report2 = try ExportService.import(decoded, context: dst)
        XCTAssertEqual(report2.membersImported, 0)
        XCTAssertEqual(report2.recordsImported, 0)
        XCTAssertEqual(report2.skippedExisting, 3 + 1)
        XCTAssertEqual(try dst.fetch(FetchDescriptor<ScoreRecord>()).count, 1)
        _ = owner; _ = mom
    }

    func testPartialExportForSplit() throws {
        let ctx = try TestDB.makeContext()
        let (family, _, _, child) = TestDB.makeFamily(context: ctx)
        let rule = TestDB.makeRule(family, points: 8)
        ctx.insert(rule)
        _ = try ScoreEngine.submit(member: child, family: family, rule: rule,
                                   at: .testNow, actorIsAdmin: false, context: ctx)
        // 只带 child（+隐含家长骨架由调用方处理）
        let bundle = try ExportService.export(family: family, context: ctx, memberFilter: [child.id])
        XCTAssertEqual(bundle.members.count, 1)
        XCTAssertEqual(bundle.records.count, 1) // 只含 child 的记录
        // 导入后 owner 兜底为首个成员
        XCTAssertEqual(bundle.family.ownerID, child.id)
    }
}
