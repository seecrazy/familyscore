import XCTest
@testable import FamilyScore

/// v3.0 到家提醒纯逻辑
final class GeoReminderTests: XCTestCase {

    func testArrivalNeedsOpenTodo() {
        XCTAssertNil(GeoReminder.arrivalMessage(openTodoCount: 0, todoTitle: nil,
                                                geoEnabled: true, minutesSinceLastFire: 60,
                                                lastFireDate: nil))
        let msg = GeoReminder.arrivalMessage(openTodoCount: 2, todoTitle: "倒垃圾",
                                             geoEnabled: true, minutesSinceLastFire: 60,
                                             lastFireDate: nil)
        XCTAssertEqual(msg?.title, "到家啦，顺手打个卡？")
        XCTAssertTrue(msg?.body.contains("倒垃圾") == true)
    }

    func testArrivalRespectsSwitchAndCooldown() {
        XCTAssertNil(GeoReminder.arrivalMessage(openTodoCount: 3, todoTitle: "倒垃圾",
                                                geoEnabled: false, minutesSinceLastFire: 60,
                                                lastFireDate: nil))
        // 30 分钟前刚发过 → 冷却中
        XCTAssertNil(GeoReminder.arrivalMessage(openTodoCount: 3, todoTitle: "倒垃圾",
                                                geoEnabled: true, minutesSinceLastFire: 60,
                                                lastFireDate: Date.now.addingTimeInterval(-1800)))
        // 61 分钟前 → 可发
        XCTAssertNotNil(GeoReminder.arrivalMessage(openTodoCount: 3, todoTitle: "倒垃圾",
                                                    geoEnabled: true, minutesSinceLastFire: 60,
                                                    lastFireDate: Date.now.addingTimeInterval(-3660)))
    }

    func testRegionShape() {
        let r = GeoReminder.region(lat: 31.23, lon: 121.47)
        XCTAssertEqual(r.identifier, "fs-home")
        XCTAssertEqual(r.radius, 100, accuracy: 0.1)
        XCTAssertTrue(r.notifyOnEntry)
        XCTAssertFalse(r.notifyOnExit)
        XCTAssertEqual(r.center.latitude, 31.23, accuracy: 0.001)
    }

    func testHasHome() {
        let f = Family(name: "T", ownerID: UUID())
        XCTAssertFalse(GeoReminder.hasHome(f))
        f.homeLat = 31.2
        XCTAssertFalse(GeoReminder.hasHome(f)) // 需要经纬都齐
        f.homeLon = 121.4
        XCTAssertTrue(GeoReminder.hasHome(f))
    }
}
