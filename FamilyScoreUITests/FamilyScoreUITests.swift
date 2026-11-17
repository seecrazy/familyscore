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
        app.launchArguments = ["-resetState", "-demoBoot"]
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
        // v3.6：名称可留空（提示文案）+ 预置图标占用徽章可见
        XCTAssertTrue(app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS '不填名称'")).firstMatch.waitForExistence(timeout: 4),
            "应提示名称可留空自动用图标名")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS '已用'")).firstMatch.waitForExistence(timeout: 4),
            "被预置奖励占用的图标应显示已用标记")
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

        // v3.0 新页：通知设置 / 云同步 / 会员（先滚动让入口进可访问树，Form 页再滚动到底部断言）
        app.swipeUp()
        let notifRow = app.staticTexts["通知设置"]
        XCTAssertTrue(notifRow.waitForExistence(timeout: 6), "通知设置入口缺失")
        notifRow.tap()
        sleep(1)
        XCTAssertTrue(app.navigationBars["通知设置"].waitForExistence(timeout: 8), "通知设置页未打开")
        app.swipeUp()
        _ = app.staticTexts["免打扰"].waitForExistence(timeout: 4)
        snap(app, "14_notif_settings")
        app.navigationBars.buttons.firstMatch.tap()
        sleep(1)
        app.swipeDown()   // 滚回中上部，让云同步/会员行可见可点
        sleep(1)
        let cloudRow = app.staticTexts["云同步"]
        XCTAssertTrue(cloudRow.waitForExistence(timeout: 6), "云同步入口缺失")
        cloudRow.tap()
        XCTAssertTrue(app.staticTexts["本地变更队列"].waitForExistence(timeout: 8), "云同步页未打开")
        snap(app, "15_cloud_sync")
        app.buttons["完成"].firstMatch.tap()
        sleep(1)
        let memberRow = app.staticTexts["家分宝会员"]
        XCTAssertTrue(memberRow.waitForExistence(timeout: 6), "会员入口缺失")
        memberRow.tap()
        XCTAssertTrue(app.staticTexts["核心功能永久免费"].waitForExistence(timeout: 8), "会员页未打开")
        snap(app, "16_membership")
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
        app.launchArguments = ["-resetState", "-demoBoot"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 60))
        snap(app, "13_tabbar")
    }

    /// v3.3 端到端：全新安装 → 真实创建家庭 → 先逛逛 → 首页立即可用（问题 1 回归）
    func testRealCreateFlowShowsContentImmediately() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-resetState", "-freshOnboarding"]   // 归一状态+强制欢迎页
        app.launch()
        XCTAssertTrue(app.buttons["创建我的家庭"].waitForExistence(timeout: 15), "全新安装应停在欢迎页")

        // 真实创建：欢迎页 → 价值轮播（跳过）→ 填表
        app.buttons["创建我的家庭"].tap()
        app.buttons["跳过"].tap()
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 6))
        nameField.tap()
        nameField.typeText("陈家")
        // 我的昵称（第二个输入框）
        let nameField2 = app.textFields.element(boundBy: 1)
        nameField2.tap()
        nameField2.typeText("陈爸爸")
        app.buttons["下一步"].tap()
        XCTAssertTrue(app.buttons["开始使用"].waitForExistence(timeout: 6))
        app.buttons["开始使用"].tap()
        XCTAssertTrue(app.staticTexts["家庭创建成功！"].waitForExistence(timeout: 8))
        app.buttons["先逛逛，稍后邀请 →"].tap()

        // 关键断言：不重启，首页立即有内容
        XCTAssertTrue(app.staticTexts["家庭今日总积分"].waitForExistence(timeout: 10),
                      "创建后首页应立即显示总积分卡（问题 1 回归）")
        XCTAssertTrue(app.staticTexts["快速加分"].waitForExistence(timeout: 5), "模板规则应立即可用")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '从第一个'"))
            .firstMatch.waitForExistence(timeout: 5), "新手引导卡应出现")
        snap(app, "17_real_create_home")

        // 邀请入口常驻（问题 3）：我的 → 家庭管理 → 邀请家人
        app.tabBars.buttons["我的"].tap()
        let fm = app.staticTexts["家庭管理"]
        XCTAssertTrue(fm.waitForExistence(timeout: 6))
        fm.tap()
        XCTAssertTrue(app.staticTexts["邀请家人加入"].waitForExistence(timeout: 6), "邀请入口应常驻")
        app.staticTexts["邀请家人加入"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '复制邀请语'"))
            .firstMatch.waitForExistence(timeout: 5))
        snap(app, "18_invite")
    }
}
