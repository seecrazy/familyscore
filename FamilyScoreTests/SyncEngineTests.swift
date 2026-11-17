import XCTest
import SwiftData
@testable import FamilyScore

/// v3.0 同步：变更记账（审计埋点联动）、幂等合并、冲突检测
final class SyncEngineTests: XCTestCase {

    var context: ModelContext!

    override func setUpWithError() throws {
        context = try TestDB.makeContext()
    }

    func testChangeLogRecordedViaAuditHook() throws {
        let f = TestDB.makeFamily(context: context)
        let rule = TestDB.makeRule(f.family, points: 5)
        context.insert(rule)
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                   at: .testNow, actorIsAdmin: false, context: context)
        let logs = SyncEngine.unsynced(context: context)
        XCTAssertGreaterThanOrEqual(logs.count, 1, "引擎操作应经审计埋点产生变更记录")
        XCTAssertTrue(logs.contains { $0.entityName == "ScoreRecord" })
        XCTAssertEqual(logs.first?.deviceID, SyncEngine.deviceID)
    }

    func testMarkAllSynced() throws {
        let f = TestDB.makeFamily(context: context)
        let rule = TestDB.makeRule(f.family, points: 5)
        context.insert(rule)
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                   at: .testNow, actorIsAdmin: false, context: context)
        XCTAssertFalse(SyncEngine.unsynced(context: context).isEmpty)
        SyncEngine.markAllSynced(context: context)
        XCTAssertTrue(SyncEngine.unsynced(context: context).isEmpty)
    }

    func testApplyRemoteIdempotentMerge() throws {
        let f = TestDB.makeFamily(context: context)
        let rule = TestDB.makeRule(f.family, points: 10)
        context.insert(rule)
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                   at: .testNow, actorIsAdmin: false, context: context)
        let bundle = try ExportService.export(family: f.family, context: context)

        // 远端包两次应用 → 幂等（本地已存在即跳过）
        let r1 = try SyncEngine.applyRemote(bundle, context: context)
        XCTAssertEqual(r1.recordsImported, 0)
        let r2 = try SyncEngine.applyRemote(bundle, context: context)
        XCTAssertEqual(r2.recordsImported, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScoreRecord>()).count, 1)
    }

    func testConflictDetection() {
        let id = UUID()
        let env = [
            SyncEngine.Envelope(entity: "Rule", entityID: id, deviceID: "dev-A",
                                changedAt: .now, operation: "update"),
            SyncEngine.Envelope(entity: "Rule", entityID: id, deviceID: "dev-B",
                                changedAt: .now.addingTimeInterval(1), operation: "update"),
            SyncEngine.Envelope(entity: "Rule", entityID: UUID(), deviceID: "dev-A",
                                changedAt: .now, operation: "update"), // 单设备 → 无冲突
        ]
        let conflicts = SyncEngine.conflicts(in: env)
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts.first?.entityID, id)
        XCTAssertEqual(conflicts.first?.devices, ["dev-A", "dev-B"])
    }

    func testDeviceIDStable() {
        let a = SyncEngine.deviceID
        let b = SyncEngine.deviceID
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.hasPrefix("dev-"))
    }
}
