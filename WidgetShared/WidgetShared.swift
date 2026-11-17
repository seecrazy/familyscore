import Foundation

/// App 与 Widget 扩展共享的轻量桥（App Group UserDefaults，双 target 编译，§18.2 模块约束下的务实方案）
///
/// 数据流：
/// - App → Widget：引擎每次入账后 `WidgetBridge.updateSummary` 写入摘要 JSON
/// - Widget → App：锁屏一键打卡把请求追加进队列并乐观更新摘要；App 下次前台
///   `WidgetBridge.consumeCheckInQueue` 逐条走积分引擎（评审规则照常产生 pending）
enum WidgetBridge {

    static let appGroupID = "group.com.sanshi.familyscore"
    static let summaryKey = "fs.widget.summary"
    static let queueKey = "fs.widget.checkin.queue"
    static let memberKey = "fs.widget.memberID"

    /// App 写摘要时缓存的当前成员 ID（Widget intent 结算归属用）
    static var cachedMemberID: UUID? {
        get { defaults.string(forKey: memberKey).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString ?? "", forKey: memberKey) }
    }

    /// App Group 存储；模拟器/无签名环境回退 standard（功能不中断，跨进程仅真机生效）
    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    // MARK: 摘要（Widget 渲染输入）

    struct Summary: Codable, Equatable {
        var familyName: String = ""
        var myName: String = ""
        var myEmoji: String = "🙂"
        var myTodayScore: Int = 0
        var familyTodayScore: Int = 0
        var weeklyScore: Int = 0
        var weeklyGoal: Int = 500
        var openTodoCount: Int = 0
        var streakDays: Int = 0
        var level: Int = 1
        var levelTitle: String = "新芽"
        var pointsToNext: Int?
        /// 锁屏一键打卡候选（正序取前 3 个正向规则）
        var quickRules: [QuickRule] = []
        /// 待家长评审条数（家长视角提示）
        var pendingApprovals: Int = 0
        var updatedAt: Date = .now
    }

    struct QuickRule: Codable, Equatable {
        var ruleID: UUID
        var name: String
        var icon: String      // SF Symbol
        var points: Int       // 已按系数计算好的预览分
    }

    static func writeSummary(_ s: Summary) {
        if let data = try? JSONEncoder().encode(s) {
            defaults.set(data, forKey: summaryKey)
        }
    }

    static func readSummary() -> Summary {
        guard let data = defaults.data(forKey: summaryKey),
              let s = try? JSONDecoder().decode(Summary.self, from: data) else {
            return Summary()
        }
        return s
    }

    // MARK: 一键打卡队列（Widget → App）

    struct CheckInRequest: Codable, Equatable {
        var memberID: UUID
        var memberName: String
        var ruleID: UUID
        var ruleName: String
        var points: Int       // 乐观展示分（真实以引擎结算为准）
        var createdAt: Date
    }

    static func enqueueCheckIn(_ req: CheckInRequest) {
        var q = readQueue()
        q.append(req)
        if let data = try? JSONEncoder().encode(q) {
            defaults.set(data, forKey: queueKey)
        }
    }

    static func readQueue() -> [CheckInRequest] {
        guard let data = defaults.data(forKey: queueKey),
              let q = try? JSONDecoder().decode([CheckInRequest].self, from: data) else {
            return []
        }
        return q
    }

    /// App 侧消费：逐条出队（回调交给引擎处理），全部处理后清空
    static func drainQueue(_ handle: (CheckInRequest) -> Void) {
        let q = readQueue()
        for req in q { handle(req) }
        defaults.removeObject(forKey: queueKey)
    }

    /// Widget 乐观更新：立即加分 + 待评审 +1（App 下次结算校正）
    static func optimisticApply(rule: QuickRule, memberName: String, memberID: UUID) {
        var s = readSummary()
        s.myTodayScore += rule.points
        s.familyTodayScore += rule.points
        s.updatedAt = .now
        writeSummary(s)
        enqueueCheckIn(CheckInRequest(memberID: memberID, memberName: memberName,
                                      ruleID: rule.ruleID, ruleName: rule.name,
                                      points: rule.points, createdAt: .now))
    }
}
