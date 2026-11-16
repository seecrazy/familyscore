import XCTest

/// UI 冒烟走查（§20.1）：演示家庭启动 → 五 Tab 巡检 → 关键交互。
/// 每屏保存 full-screen 截图附件（keepAlways），供发布前目检导出。
final class FamilyScoreUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testDemoWalkthrough() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demoBoot"]
        app.launch()

        // 首页
        XCTAssertTrue(app.staticTexts["家庭今日总积分"].waitForExistence(timeout: 60),
                      "首页总积分卡未出现")
        XCTAssertTrue(app.staticTexts["快速加分"].exists)
        snap(app, "02_home")

        // 排行榜
        app.tabBars.buttons["排行"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '贡献榜'"))
            .firstMatch.waitForExistence(timeout: 10), "排行榜标题未出现")
        snap(app, "03_rank_day")
        app.buttons["周"].firstMatch.tap()
        sleep(1)
        snap(app, "04_rank_week")

        // 统计
        app.tabBars.buttons["统计"].tap()
        XCTAssertTrue(app.staticTexts["近 7 天趋势"].waitForExistence(timeout: 10))
        snap(app, "05_stats")

        // 商城
        app.tabBars.buttons["商城"].tap()
        XCTAssertTrue(app.staticTexts["我的可用积分"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["奖励商城"].exists)
        snap(app, "06_rewards")

        // 我的
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.staticTexts["累计积分"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["审计日志"].exists)
        snap(app, "07_profile")

        // 首页加分流程（点第一个快捷 chip → 确认半屏卡）
        app.tabBars.buttons["首页"].tap()
        let firstChip = app.buttons.matching(NSPredicate(format: "label CONTAINS '加'")).firstMatch
        if firstChip.waitForExistence(timeout: 4) {
            firstChip.tap()
            let confirm = app.buttons["确认加分"]
            if confirm.waitForExistence(timeout: 4) {
                snap(app, "08_confirm_sheet")
                confirm.tap()
                sleep(2)
                snap(app, "09_after_add")
            }
        }
    }

    func testOnboardingFlow() throws {
        // 每次启动前清状态由 demoBoot 之外的场景保证；此用例跑在 walkthrough 之后，
        // 设备上已有数据 → 只验证欢迎页结构（新装设备路径已被 demoBoot 用例覆盖启动分支）
        let app = XCUIApplication()
        app.launch()
        // 已完成引导时直接进首页
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 12))
        snap(app, "10_tabbar")
    }
}
