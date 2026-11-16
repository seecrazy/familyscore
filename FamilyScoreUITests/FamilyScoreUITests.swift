import XCTest

/// UI 冒烟走查（§20.1）：演示家庭启动 → 五 Tab 巡检 → 新功能（评审/指派/生日/体验退出/奖励管理）。
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

        // 首页（含 v2.1 新元素：体验 banner、生日卡、待评审）
        XCTAssertTrue(app.staticTexts["家庭今日总积分"].waitForExistence(timeout: 60),
                      "首页总积分卡未出现")
        XCTAssertTrue(app.staticTexts["快速加分"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '体验模式'"))
            .firstMatch.exists, "体验模式 banner 缺失")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '妈妈的生日'"))
            .firstMatch.exists, "生日提醒卡缺失")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '待我评审'"))
            .firstMatch.exists, "待评审区缺失")
        XCTAssertTrue(app.buttons["退出体验"].exists)
        snap(app, "02_home")

        // 指派任务 sheet
        let assignBtn = app.buttons["指派"].firstMatch
        if assignBtn.exists {
            assignBtn.tap()
            XCTAssertTrue(app.staticTexts["指派给谁"].waitForExistence(timeout: 6))
            snap(app, "03_assign_sheet")
            app.buttons["取消"].firstMatch.tap()
        }

        // 排行榜
        app.tabBars.buttons["排行"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '贡献榜'"))
            .firstMatch.waitForExistence(timeout: 10), "排行榜标题未出现")
        snap(app, "04_rank_day")
        app.buttons["周"].firstMatch.tap()
        sleep(1)
        snap(app, "05_rank_week")

        // 统计
        app.tabBars.buttons["统计"].tap()
        XCTAssertTrue(app.staticTexts["近 7 天趋势"].waitForExistence(timeout: 10))
        snap(app, "06_stats")

        // 商城
        app.tabBars.buttons["商城"].tap()
        XCTAssertTrue(app.staticTexts["我的可用积分"].waitForExistence(timeout: 10))
        snap(app, "07_rewards")

        // 我的（管理员工具）+ 奖励管理
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.staticTexts["累计积分"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["奖励商城管理"].exists)
        XCTAssertTrue(app.staticTexts["审计日志"].exists)
        app.staticTexts["奖励商城管理"].tap()
        XCTAssertTrue(app.navigationBars["奖励商城管理"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["plus.circle.fill"].exists)
        snap(app, "08_reward_admin")
        app.buttons["plus.circle.fill"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["奖励内容"].waitForExistence(timeout: 6))
        snap(app, "09_reward_edit")
        app.navigationBars.buttons.firstMatch.tap() // 取消编辑
        sleep(1)
        app.buttons["完成"].firstMatch.tap()          // 关闭奖励管理 sheet
        sleep(1)

        // 家庭管理（管理员设置/重新加入/生日）
app.staticTexts["家庭管理"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '成员（'"))
            .firstMatch.waitForExistence(timeout: 6), "家庭管理成员列表缺失")
        XCTAssertTrue(app.staticTexts["奶奶"].exists || app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS '奶奶'")).firstMatch.exists)
        snap(app, "10_family_manage")
        app.buttons["完成"].firstMatch.tap()
        sleep(1)

        // 首页评审：通过小明的洗碗
        app.tabBars.buttons["首页"].tap()
        sleep(1)
        let approve = app.buttons.matching(NSPredicate(format: "label CONTAINS '确认' OR label CONTAINS 'checkmark'")).firstMatch
        _ = approve.waitForExistence(timeout: 3)

        // 儿童视角：切到小明打卡 → 提示需评审
        app.buttons["切换成员"].firstMatch.tap() // 首页右上头像（accessibilityLabel）
        let ming = app.buttons.containing(NSPredicate(format: "label CONTAINS '小明'")).firstMatch
        if ming.waitForExistence(timeout: 4) {
            ming.tap()
            let chip = app.buttons.matching(NSPredicate(format: "label CONTAINS '，加'")).firstMatch
            if chip.waitForExistence(timeout: 4) {
                chip.tap()
                XCTAssertTrue(app.staticTexts.containing(
                    NSPredicate(format: "label CONTAINS '家长评审'")).firstMatch
                    .waitForExistence(timeout: 5), "儿童打卡应提示需评审")
                XCTAssertTrue(app.staticTexts.containing(
                    NSPredicate(format: "label CONTAINS '相册'")).firstMatch.exists,
                    "凭证相册按钮缺失")
                snap(app, "11_child_confirm")
                app.buttons["确认加分"].tap()
                sleep(2)
                snap(app, "12_child_submitted")
                // 切回妈妈（保持下次启动为管理员视角）
                app.buttons["切换成员"].firstMatch.tap()
                let mom = app.buttons.containing(NSPredicate(format: "label CONTAINS '妈妈'")).firstMatch
                if mom.waitForExistence(timeout: 4) { mom.tap() }
            }
        }
    }

    func testOnboardingFlow() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 60))
        snap(app, "13_tabbar")
    }
}
