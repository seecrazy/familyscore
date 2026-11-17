import XCTest
@testable import FamilyScore

/// v3.0 Widget 桥：摘要/队列编解码、乐观更新、消费清空
final class WidgetBridgeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // 独立 suite，避免污染真实 App Group 数据
        UserDefaults().removePersistentDomain(forName: WidgetBridge.appGroupID)
    }

    func testSummaryRoundtrip() {
        var s = WidgetBridge.Summary()
        s.familyName = "王家"; s.myName = "小明"; s.myTodayScore = 45
        s.quickRules = [.init(ruleID: UUID(), name: "洗碗", icon: "fork.knife", points: 6)]
        WidgetBridge.writeSummary(s)
        let read = WidgetBridge.readSummary()
        XCTAssertEqual(read, s)
        XCTAssertEqual(read.quickRules.first?.name, "洗碗")
    }

    func testCheckInQueueEnqueueDrainAndOptimistic() {
        var s = WidgetBridge.Summary()
        s.myTodayScore = 10; s.familyTodayScore = 100
        WidgetBridge.writeSummary(s)

        let rule = WidgetBridge.QuickRule(ruleID: UUID(), name: "倒垃圾", icon: "trash", points: 3)
        WidgetBridge.optimisticApply(rule: rule, memberName: "小明", memberID: UUID())
        // 乐观更新生效
        XCTAssertEqual(WidgetBridge.readSummary().myTodayScore, 13)
        XCTAssertEqual(WidgetBridge.readSummary().familyTodayScore, 103)
        // 队列有一条
        let q = WidgetBridge.readQueue()
        XCTAssertEqual(q.count, 1)
        XCTAssertEqual(q.first?.ruleName, "倒垃圾")

        var drained: [WidgetBridge.CheckInRequest] = []
        WidgetBridge.drainQueue { drained.append($0) }
        XCTAssertEqual(drained.count, 1)
        XCTAssertTrue(WidgetBridge.readQueue().isEmpty, "drain 后清空")
    }

    func testCachedMemberID() {
        let id = UUID()
        WidgetBridge.cachedMemberID = id
        XCTAssertEqual(WidgetBridge.cachedMemberID, id)
        WidgetBridge.cachedMemberID = nil
        XCTAssertNil(WidgetBridge.cachedMemberID)
    }
}
