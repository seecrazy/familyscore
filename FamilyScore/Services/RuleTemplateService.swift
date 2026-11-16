import Foundation

/// 规则模板包（DESIGN.md §6.3 / §6.5）
enum RuleTemplateService {

    enum TemplateKind: String, CaseIterable, Identifiable {
        case three      = "三口之家（推荐）"
        case withElder  = "有老人家庭"
        case twoKids    = "二胎家庭"
        case custom     = "自定义（从空白开始）"
        var id: String { rawValue }
        var subtitle: String {
            switch self {
            case .three: "20 条精选规则，适合爸妈+一个孩子"
            case .withElder: "增加陪伴与健康类规则，四代同堂"
            case .twoKids: "增加协作与分享类规则，兄妹共成长"
            case .custom: "从零开始，逐条添加"
            }
        }
    }

    /// 规则草稿（未落库）
    struct Draft {
        var category: RuleCategory
        var name: String
        var icon: String
        var points: Int
        var dailyLimit: Int
        var requiresApproval: Bool
    }

    static func rules(for kind: TemplateKind) -> [Draft] {
        switch kind {
        case .custom: return []
        case .three: return coreRules
        case .withElder: return coreRules + elderRules
        case .twoKids: return coreRules + twoKidsRules
        }
    }

    /// 三口之家 20 条（§6.5 推荐包）
    static let coreRules: [Draft] = [
        // 家务 8
        .init(category: .chore, name: "洗碗", icon: "fork.knife", points: 5, dailyLimit: 3, requiresApproval: true),
        .init(category: .chore, name: "扫地/拖地", icon: "paintbrush", points: 8, dailyLimit: 2, requiresApproval: true),
        .init(category: .chore, name: "倒垃圾", icon: "trash", points: 3, dailyLimit: 2, requiresApproval: false),
        .init(category: .chore, name: "做饭（一餐）", icon: "chef.hat", points: 15, dailyLimit: 2, requiresApproval: true),
        .init(category: .chore, name: "洗衣+晾晒", icon: "tshirt", points: 6, dailyLimit: 2, requiresApproval: true),
        .init(category: .chore, name: "整理房间", icon: "square.and.arrow.down.on.square", points: 5, dailyLimit: 2, requiresApproval: false),
        .init(category: .chore, name: "深度清洁", icon: "sparkles", points: 20, dailyLimit: 1, requiresApproval: true),
        .init(category: .chore, name: "遛宠物", icon: "pawprint", points: 5, dailyLimit: 3, requiresApproval: false),
        // 学习 4
        .init(category: .study, name: "完成作业", icon: "text.book.closed", points: 10, dailyLimit: 2, requiresApproval: true),
        .init(category: .study, name: "阅读 30 分钟", icon: "book.fill", points: 8, dailyLimit: 3, requiresApproval: false),
        .init(category: .study, name: "练琴/特长", icon: "pianokeys", points: 10, dailyLimit: 2, requiresApproval: true),
        .init(category: .study, name: "考试进步", icon: "arrow.up.forward.circle", points: 30, dailyLimit: 0, requiresApproval: true),
        // 健康 4
        .init(category: .health, name: "运动 30 分钟", icon: "figure.run", points: 10, dailyLimit: 2, requiresApproval: false),
        .init(category: .health, name: "早睡（22:30 前）", icon: "moon.zzz", points: 5, dailyLimit: 1, requiresApproval: false),
        .init(category: .health, name: "喝够 8 杯水", icon: "drop", points: 3, dailyLimit: 1, requiresApproval: false),
        .init(category: .health, name: "刷牙打卡", icon: "tooth", points: 2, dailyLimit: 2, requiresApproval: false),
        // 情绪 3 + 减分 6（§6.3 减分项，家长发起）
        .init(category: .emotion, name: "主动关心家人", icon: "heart.fill", points: 5, dailyLimit: 3, requiresApproval: false),
        .init(category: .emotion, name: "帮助家人解决难题", icon: "hands.and.sparkles", points: 10, dailyLimit: 2, requiresApproval: true),
        .init(category: .emotion, name: "家庭活动全勤", icon: "party.popper", points: 15, dailyLimit: 1, requiresApproval: true),
        .init(category: .chore, name: "未完成约定任务", icon: "exclamationmark.circle", points: -5, dailyLimit: 0, requiresApproval: false),
    ]

    /// 有老人家庭附加包（§6.5）
    static let elderRules: [Draft] = [
        .init(category: .emotion, name: "陪伴老人 30 分钟", icon: "figure.2.and.child.holding.hands", points: 8, dailyLimit: 2, requiresApproval: false),
        .init(category: .health, name: "体检/看牙医", icon: "stethoscope", points: 8, dailyLimit: 0, requiresApproval: true),
        .init(category: .chore, name: "帮老人取快递/买菜", icon: "bag", points: 5, dailyLimit: 2, requiresApproval: false),
        .init(category: .emotion, name: "教长辈用手机", icon: "iphone", points: 6, dailyLimit: 1, requiresApproval: false),
    ]

    /// 二胎家庭附加包（§6.5）
    static let twoKidsRules: [Draft] = [
        .init(category: .emotion, name: "辅导弟弟妹妹功课", icon: "person.2.fill", points: 10, dailyLimit: 1, requiresApproval: true),
        .init(category: .emotion, name: "主动分享玩具/零食", icon: "gift.fill", points: 5, dailyLimit: 2, requiresApproval: false),
        .init(category: .chore, name: "兄妹合作完成家务", icon: "person.2.wave.2", points: 12, dailyLimit: 1, requiresApproval: true),
        .init(category: .emotion, name: "谦让弟弟妹妹", icon: "hands.and.sparkles.fill", points: 5, dailyLimit: 1, requiresApproval: false),
    ]

    /// 全量减分项（家长可手动添加，§6.3）
    static let deductionRules: [Draft] = [
        .init(category: .chore, name: "未完成约定任务", icon: "exclamationmark.circle", points: -5, dailyLimit: 0, requiresApproval: false),
        .init(category: .special, name: "拖延提醒 3 次以上", icon: "clock.arrow.circlepath", points: -3, dailyLimit: 0, requiresApproval: false),
        .init(category: .chore, name: "乱扔物品", icon: "trash.slash", points: -3, dailyLimit: 0, requiresApproval: false),
        .init(category: .emotion, name: "说脏话/发脾气", icon: "bubble.left.and.exclamationmark.bubble.right", points: -5, dailyLimit: 0, requiresApproval: false),
        .init(category: .health, name: "超时玩手机/游戏", icon: "iphone.slash", points: -5, dailyLimit: 0, requiresApproval: false),
        .init(category: .emotion, name: "撒谎", icon: "eye.slash", points: -10, dailyLimit: 0, requiresApproval: false),
    ]

    /// 默认奖励商城（§8.4）
    static func defaultRewardDrafts() -> [(title: String, icon: String, cost: Int, stock: Int, discount: Int?, discountEndsAt: Date?)] {
        [
            ("选今晚的电影", "film", 150, -1, 120, .now.addingTimeInterval(3 * 86400)),
            ("冰淇淋一个", "icecream", 80, 3, nil, nil),
            ("零花钱 10 元", "banknote", 200, -1, nil, nil),
            ("免做一次家务", "figure.wave", 50, -1, nil, nil),
            ("周末活动我来选", "ticket", 300, 1, nil, nil),
            ("晚睡 30 分钟券", "moon.stars", 120, -1, nil, nil),
        ]
    }
}
