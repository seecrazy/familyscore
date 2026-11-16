import Foundation
import SwiftData

// MARK: - 枚举（全部 String rawValue，SwiftData 直接存储）

enum MemberRole: String, Codable, CaseIterable { case admin, child, elder }
enum MemberStatus: String, Codable { case active, exited }
enum RuleCategory: String, Codable, CaseIterable {
    case chore, study, health, emotion, special
    var label: String {
        switch self {
        case .chore: "家务"; case .study: "学习"; case .health: "健康"; case .emotion: "情绪"; case .special: "特别"
        }
    }
}
enum RecordStatus: String, Codable { case pending, approved, rejected, appealed, reversed }
enum AuditAction: String, Codable { case add, deduct, approve, reject, reverse, config, redeem }
enum RedemptionStatus: String, Codable { case pending, confirmed, cancelled }
enum RankPeriod: String, Codable, CaseIterable { case day, week, month, year, all }
enum AssignmentStatus: String, Codable { case open, done, expired, cancelled }

// MARK: - Family

@Model
final class Family {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var ownerID: UUID
    var timezoneID: String            // 家庭主时区，排名计算基准（§5.2）
    var settingsData: FamilySettings  // 全局设置（Codable 结构体存储）
    var isDemo: Bool                  // 体验模式家庭

    init(name: String, ownerID: UUID, timezoneID: String = TimeZone.current.identifier,
         settings: FamilySettings = FamilySettings(), isDemo: Bool = false, createdAt: Date = .now) {
        self.id = UUID()
        self.name = name
        self.createdAt = createdAt
        self.ownerID = ownerID
        self.timezoneID = timezoneID
        self.settingsData = settings
        self.isDemo = isDemo
    }
}

struct FamilySettings: Codable {
    var dailyDeductionCap: Int = 20        // 每日减分上限（绝对值）
    var weeklyGoal: Int = 500              // 团队周目标
    var doublePointsMultiplier: Double = 1 // 活动倍率 1.0–3.0
    var approverDailyLimit: Int = 20       // 同一确认人每日确认上限
    var repeatWindowMinutes: Int = 5       // 同成员同规则重复窗口
    var requireDoubleParentForDeduction: Bool = true // 减分双家长确认
}

// MARK: - Member

@Model
final class Member {
    @Attribute(.unique) var id: UUID
    var familyID: UUID
    var name: String
    var emoji: String                    // 头像 emoji（儿童图形化，免上传）
    var role: MemberRole
    var coefficient: Double              // 积分系数（儿童默认 1.2）
    var cumulativeScore: Int             // 累计积分（只增不减，映射等级）
    var availableScore: Int              // 可用积分（冗余快照 = Σ 未过期批次）
    var joinedAt: Date
    var status: MemberStatus
    var streakDays: Int                  // 当前连续打卡天数
    var lastCheckInDay: String?          // 最近打卡日 yyyy-MM-dd（家庭时区）
    var pinCode: String?                 // 家长锁 PIN（admin）

    init(familyID: UUID, name: String, emoji: String, role: MemberRole,
         coefficient: Double? = nil, joinedAt: Date = .now) {
        self.id = UUID()
        self.familyID = familyID
        self.name = name
        self.emoji = emoji
        self.role = role
        self.coefficient = coefficient ?? (role == .child ? 1.2 : 1.0)
        self.cumulativeScore = 0
        self.availableScore = 0
        self.joinedAt = joinedAt
        self.status = .active
        self.streakDays = 0
        self.lastCheckInDay = nil
        self.pinCode = nil
    }

    var level: Int { LevelEngine.level(forCumulative: cumulativeScore) }
}

// MARK: - Rule

@Model
final class Rule {
    @Attribute(.unique) var id: UUID
    var familyID: UUID
    var category: RuleCategory
    var name: String
    var icon: String                     // SF Symbol 名
    var points: Int                      // 正加负减
    var dailyLimit: Int                  // 每日上限（0=不限）
    var requiresProof: Bool
    var requiresApproval: Bool
    var isActive: Bool
    var sortOrder: Int

    init(familyID: UUID, category: RuleCategory, name: String, icon: String, points: Int,
         dailyLimit: Int = 0, requiresProof: Bool = false, requiresApproval: Bool = false,
         isActive: Bool = true, sortOrder: Int = 0) {
        self.id = UUID()
        self.familyID = familyID
        self.category = category
        self.name = name
        self.icon = icon
        self.points = points
        self.dailyLimit = dailyLimit
        self.requiresProof = requiresProof
        self.requiresApproval = requiresApproval
        self.isActive = isActive
        self.sortOrder = sortOrder
    }

    var isDeduction: Bool { points < 0 }
}

// MARK: - ScoreRecord（append-only，含计分上下文快照，§5.2/§6.1）

@Model
final class ScoreRecord {
    @Attribute(.unique) var id: UUID
    var familyID: UUID
    var memberID: UUID
    var ruleID: UUID?
    var points: Int          // 实际得分 = round(base × coefficient × multiplier)
    var basePoints: Int      // 规则基础分快照
    var coefficient: Double  // 成员系数快照
    var multiplier: Double   // 活动倍率快照
    var category: RuleCategory
    var note: String?
    var proofHash: String?   // 凭证感知哈希（pHash 去重）
    var status: RecordStatus
    var createdAt: Date
    var approvedBy: UUID?
    var reversedRecordID: UUID? // 本记录被哪条反向记录撤销
    var deviceID: String?
    var backfilledAt: Date?     // 补录的实际录入时刻（A5 审计用，正常提交为 nil）
    var isReversal: Bool        // 反向记录（撤销生成，不参与累计/streak 正向语义）

    init(familyID: UUID, memberID: UUID, ruleID: UUID?, points: Int, basePoints: Int,
         coefficient: Double, multiplier: Double, category: RuleCategory,
         note: String? = nil, proofHash: String? = nil, status: RecordStatus,
         createdAt: Date = .now, approvedBy: UUID? = nil, deviceID: String? = nil,
         backfilledAt: Date? = nil, isReversal: Bool = false) {
        self.id = UUID()
        self.familyID = familyID
        self.memberID = memberID
        self.ruleID = ruleID
        self.points = points
        self.basePoints = basePoints
        self.coefficient = coefficient
        self.multiplier = multiplier
        self.category = category
        self.note = note
        self.proofHash = proofHash
        self.status = status
        self.createdAt = createdAt
        self.approvedBy = approvedBy
        self.deviceID = deviceID
        self.backfilledAt = backfilledAt
        self.isReversal = isReversal
    }
}

// MARK: - Reward / Redemption / WishListItem

@Model
final class Reward {
    @Attribute(.unique) var id: UUID
    var familyID: UUID
    var title: String
    var icon: String
    var cost: Int
    var discountCost: Int?    // 限时折扣价（v2）
    var discountEndsAt: Date?
    var stock: Int            // -1=无限
    var isActive: Bool

    init(familyID: UUID, title: String, icon: String, cost: Int, discountCost: Int? = nil,
         discountEndsAt: Date? = nil, stock: Int = -1, isActive: Bool = true) {
        self.id = UUID()
        self.familyID = familyID
        self.title = title
        self.icon = icon
        self.cost = cost
        self.discountCost = discountCost
        self.discountEndsAt = discountEndsAt
        self.stock = stock
        self.isActive = isActive
    }

    var effectiveCost: Int { effectiveCost(at: .now) }

    func effectiveCost(at date: Date) -> Int {
        if let d = discountCost, let end = discountEndsAt, end > date { return d }
        return cost
    }
}

@Model
final class Redemption {
    @Attribute(.unique) var id: UUID
    var rewardID: UUID
    var memberID: UUID
    var familyID: UUID
    var cost: Int
    var code: String          // 核销码 FS-XXXX-XXXX（§22.2）
    var status: RedemptionStatus
    var createdAt: Date
    var confirmedAt: Date?

    init(rewardID: UUID, memberID: UUID, familyID: UUID, cost: Int, code: String,
         createdAt: Date = .now) {
        self.id = UUID()
        self.rewardID = rewardID
        self.memberID = memberID
        self.familyID = familyID
        self.cost = cost
        self.code = code
        self.status = .pending
        self.createdAt = createdAt
        self.confirmedAt = nil
    }
}

@Model
final class WishListItem {
    @Attribute(.unique) var id: UUID
    var memberID: UUID
    var rewardID: UUID
    var createdAt: Date
    var notifiedAt: Date?

    init(memberID: UUID, rewardID: UUID, createdAt: Date = .now) {
        self.id = UUID()
        self.memberID = memberID
        self.rewardID = rewardID
        self.createdAt = createdAt
        self.notifiedAt = nil
    }
}

// MARK: - ScoreLot（积分批次，v2 §5.2）

@Model
final class ScoreLot {
    @Attribute(.unique) var id: UUID
    var memberID: UUID
    var monthKey: String      // 获得月份 yyyy-MM
    var amount: Int           // 批次剩余可用分
    var isPermanent: Bool     // 已打五折转入永久池

    init(memberID: UUID, monthKey: String, amount: Int, isPermanent: Bool = false) {
        self.id = UUID()
        self.memberID = memberID
        self.monthKey = monthKey
        self.amount = amount
        self.isPermanent = isPermanent
    }
}

// MARK: - TaskAssignment（家长指派待办，v2 §5.2）

@Model
final class TaskAssignment {
    @Attribute(.unique) var id: UUID
    var familyID: UUID
    var ruleID: UUID
    var assigneeID: UUID
    var assignerID: UUID
    var dueDay: String        // yyyy-MM-dd（家庭时区）
    var status: AssignmentStatus
    var createdAt: Date

    init(familyID: UUID, ruleID: UUID, assigneeID: UUID, assignerID: UUID,
         dueDay: String, createdAt: Date = .now) {
        self.id = UUID()
        self.familyID = familyID
        self.ruleID = ruleID
        self.assigneeID = assigneeID
        self.assignerID = assignerID
        self.dueDay = dueDay
        self.status = .open
        self.createdAt = createdAt
    }
}

// MARK: - AuditLog / Badge / RankSnapshot

@Model
final class AuditLog {
    @Attribute(.unique) var id: UUID
    var familyID: UUID
    var actorID: UUID
    var action: AuditAction
    var targetID: UUID
    var reason: String?
    var createdAt: Date

    init(familyID: UUID, actorID: UUID, action: AuditAction, targetID: UUID,
         reason: String? = nil, createdAt: Date = .now) {
        self.id = UUID()
        self.familyID = familyID
        self.actorID = actorID
        self.action = action
        self.targetID = targetID
        self.reason = reason
        self.createdAt = createdAt
    }
}

@Model
final class Badge {
    @Attribute(.unique) var id: UUID
    var memberID: UUID
    var badgeKey: String
    var unlockedAt: Date

    init(memberID: UUID, badgeKey: String, unlockedAt: Date = .now) {
        self.id = UUID()
        self.memberID = memberID
        self.badgeKey = badgeKey
        self.unlockedAt = unlockedAt
    }
}

@Model
final class RankSnapshot {
    @Attribute(.unique) var id: UUID
    var familyID: UUID
    var period: RankPeriod
    var periodStart: Date
    var dataJSON: String      // [memberID: score]

    init(familyID: UUID, period: RankPeriod, periodStart: Date, dataJSON: String) {
        self.id = UUID()
        self.familyID = familyID
        self.period = period
        self.periodStart = periodStart
        self.dataJSON = dataJSON
    }
}

// MARK: - 等级引擎（§6.2.1）

enum LevelEngine {
    static let thresholds: [(score: Int, level: Int, title: String)] = [
        (0, 1, "新芽"), (100, 2, "小帮手"), (300, 3, "勤劳蜂"), (700, 4, "小达人"),
        (1500, 5, "榜样星"), (3000, 6, "大管家"), (5000, 7, "闪亮星"), (8000, 8, "传奇星"),
        (12000, 9, "家庭之光"), (20000, 10, "传家宝"),
    ]

    static func level(forCumulative score: Int) -> Int {
        var current = 1
        for t in thresholds where score >= t.score { current = t.level }
        return current
    }

    static func title(forLevel level: Int) -> String {
        thresholds.first { $0.level == level }?.title ?? "新芽"
    }

    /// 升到下一级还差多少分（满级返回 nil）
    static func pointsToNext(score: Int) -> Int? {
        guard let next = thresholds.first(where: { $0.score > score }) else { return nil }
        return next.score - score
    }

    /// 等级进度 0–1（当前级起点到下一级起点）
    static func progress(score: Int) -> Double {
        let level = level(forCumulative: score)
        if level >= 10 { return 1 }
        let currentStart = thresholds.first { $0.level == level }!.score
        let nextStart = thresholds.first { $0.level == level + 1 }!.score
        return Double(score - currentStart) / Double(nextStart - currentStart)
    }
}
