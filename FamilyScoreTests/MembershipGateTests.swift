import XCTest
@testable import FamilyScore

/// v3.0 会员门槛（§17.1）
final class MembershipGateTests: XCTestCase {

    func testFreeState() {
        let free = MembershipState()
        XCTAssertFalse(free.isMember)
        for f in MembershipFeature.allCases {
            XCTAssertEqual(MembershipGate.allows(f, state: free), f.freeAvailable)
        }
        XCTAssertFalse(MembershipGate.canAddMember(currentActive: 3, state: free))
        XCTAssertTrue(MembershipGate.canAddMember(currentActive: 2, state: free))
        XCTAssertNotNil(MembershipGate.historyCutoff(state: free))
        XCTAssertFalse(MembershipGate.isTemplateAllowed(.withElder, state: free))
        XCTAssertTrue(MembershipGate.isTemplateAllowed(.three, state: free))
        XCTAssertTrue(MembershipGate.isTemplateAllowed(.custom, state: free))
    }

    func testMemberState() {
        let member = MembershipState(productID: MembershipGate.yearlyID,
                                     expiresAt: .now.addingTimeInterval(86400))
        XCTAssertTrue(member.isMember)
        for f in MembershipFeature.allCases {
            XCTAssertTrue(MembershipGate.allows(f, state: member))
        }
        XCTAssertTrue(MembershipGate.canAddMember(currentActive: 10, state: member))
        XCTAssertNil(MembershipGate.historyCutoff(state: member))
        XCTAssertTrue(MembershipGate.isTemplateAllowed(.twoKids, state: member))
    }

    func testExpiredMembershipFallsBack() {
        let expired = MembershipState(productID: MembershipGate.monthlyID,
                                      expiresAt: .now.addingTimeInterval(-60))
        XCTAssertFalse(expired.isMember, "过期订阅回退免费")
        XCTAssertNotNil(MembershipGate.historyCutoff(state: expired))
    }

    func testStateRoundtrip() {
        var s = MembershipState(productID: MembershipGate.monthlyID,
                                expiresAt: .now.addingTimeInterval(3600))
        s.save()
        let loaded = MembershipState.load()
        XCTAssertEqual(loaded, s)
        MembershipState().save() // 恢复默认，避免污染
    }
}
