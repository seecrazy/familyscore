import XCTest
import SwiftData
@testable import FamilyScore

/// v3.3 成员资料维护与安全删除
final class MemberAdminTests: XCTestCase {

    var context: ModelContext!

    override func setUpWithError() throws {
        context = try TestDB.makeContext()
    }

    func testDeleteCleanMember() throws {
        let f = TestDB.makeFamily(context: context)
        let fresh = FamilyService.addMember(to: f.family, name: "误加的", role: .child,
                                            emoji: "👦", context: context)
        XCTAssertEqual(MemberAdminService.deleteIfClean(fresh, context: context), .deleted)
        let mid = fresh.id
        let left = (try? context.fetch(FetchDescriptor<Member>(
            predicate: #Predicate { $0.id == mid }))) ?? []
        XCTAssertTrue(left.isEmpty)
    }

    func testDeleteBlockedWhenHasRecords() throws {
        let f = TestDB.makeFamily(context: context)
        let rule = TestDB.makeRule(f.family, points: 5)
        context.insert(rule)
        _ = try ScoreEngine.submit(member: f.child, family: f.family, rule: rule,
                                   at: .testNow, actorIsAdmin: false, context: context)
        if case .blockedHasRecords(let n) = MemberAdminService.deleteIfClean(f.child, context: context) {
            XCTAssertGreaterThanOrEqual(n, 1)
        } else { XCTFail("有记录的成员应拒绝删除") }
        // 成员仍在
        let mid = f.child.id
        let left = (try? context.fetch(FetchDescriptor<Member>(
            predicate: #Predicate { $0.id == mid }))) ?? []
        XCTAssertEqual(left.count, 1)
    }

    func testUpdateProfile() throws {
        let f = TestDB.makeFamily(context: context)
        XCTAssertTrue(MemberAdminService.updateProfile(f.child, family: f.family,
                                                       name: "小明改", emoji: "🧑",
                                                       role: .elder, context: context))
        XCTAssertEqual(f.child.name, "小明改")
        XCTAssertEqual(f.child.role, .elder)
        // 创建者角色不可改
        XCTAssertTrue(MemberAdminService.updateProfile(f.mom, family: f.family,
                                                       name: "妈妈", emoji: "👩",
                                                       role: .child, context: context))
        XCTAssertEqual(f.mom.role, .admin, "创建者角色应保持 admin")
        // 空名拒绝
        XCTAssertFalse(MemberAdminService.updateProfile(f.child, family: f.family,
                                                        name: "  ", emoji: "👦",
                                                        role: .child, context: context))
    }
}
