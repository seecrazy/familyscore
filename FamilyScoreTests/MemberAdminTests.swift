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

// MARK: v3.4 奖励查重复用 + 快捷上下架
extension MemberAdminTests {
    func testFindExistingRewardIncludesUnpublished() throws {
        let f = TestDB.makeFamily(context: context)
        let onSale = Reward(familyID: f.family.id, title: "选今晚的电影", icon: "film", cost: 150)
        let off = Reward(familyID: f.family.id, title: "冰淇淋一个", icon: "icecream", cost: 80)
        off.isActive = false
        context.insert(onSale); context.insert(off)

        // 命中已下架的同名奖励（复用场景）
        let hit = RewardService.findExisting(familyID: f.family.id, title: " 冰淇淋一个 ", context: context)
        XCTAssertEqual(hit?.id, off.id)
        // 在售的也能命中
        XCTAssertEqual(RewardService.findExisting(familyID: f.family.id, title: "选今晚的电影",
                                                  context: context)?.id, onSale.id)
        // 不存在 / 空串
        XCTAssertNil(RewardService.findExisting(familyID: f.family.id, title: "不存在的", context: context))
        XCTAssertNil(RewardService.findExisting(familyID: f.family.id, title: "  ", context: context))
    }

    func testQuickPublishUnpublish() throws {
        let f = TestDB.makeFamily(context: context)
        let r = Reward(familyID: f.family.id, title: "零花钱", icon: "banknote", cost: 200)
        r.isActive = false
        context.insert(r)
        RewardService.setActive(r, true, context: context)
        XCTAssertTrue(r.isActive)
        RewardService.setActive(r, false, context: context)
        XCTAssertFalse(r.isActive)
        // 操作入审计
        let logs = (try? context.fetch(FetchDescriptor<AuditLog>())) ?? []
        XCTAssertTrue(logs.contains { $0.reason?.contains("上架「零花钱」") == true })
    }
}

// MARK: v3.5 图标占用
extension MemberAdminTests {
    func testOccupiedIconMapExcludesSelfAndMerges() throws {
        let f = TestDB.makeFamily(context: context)
        let a = Reward(familyID: f.family.id, title: "冰淇淋", icon: "icecream", cost: 80)
        let b = Reward(familyID: f.family.id, title: "电影", icon: "film", cost: 150)
        context.insert(a); context.insert(b)

        // 新建（无排除）：两个图标都占用
        var map = RewardService.occupiedIconMap(rewards: [a, b], excluding: nil)
        XCTAssertEqual(map["icecream"], "冰淇淋")
        XCTAssertEqual(map["film"], "电影")

        // 编辑 a：排除自身 → 只剩 film 占用
        map = RewardService.occupiedIconMap(rewards: [a, b], excluding: a.id)
        XCTAssertNil(map["icecream"])
        XCTAssertEqual(map["film"], "电影")

        // 同图标多奖励取先出现的
        let c = Reward(familyID: f.family.id, title: "另一个冰淇淋", icon: "icecream", cost: 90)
        map = RewardService.occupiedIconMap(rewards: [a, c], excluding: nil)
        XCTAssertEqual(map["icecream"], "冰淇淋")
    }

    func testIconLibraryUnique() {
        // 图标库内不重复（避免格子重复出现）
        let all = RewardEditSheet.iconLibrary.flatMap(\.icons)
        XCTAssertEqual(all.count, Set(all).count)
        XCTAssertGreaterThanOrEqual(all.count, 28, "图标库应扩充到 30 个上下")
        // 预置奖励的 6 个图标在库中（预置奖励可正常换回原图标语义）
        for preset in RuleTemplateService.defaultRewardDrafts() where preset.icon != "ticket" {
            XCTAssertTrue(all.contains(preset.icon), "预置图标 \\(preset.icon) 应在图标库中")
        }
    }
}
