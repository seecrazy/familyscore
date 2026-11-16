import Foundation
import SwiftData

/// 体验模式：演示家庭"王家"五口人 × 30 天历史（§19.1 冷启动体验模式）
/// 确定性随机（固定种子），保证每次生成的数据一致，便于演示与测试。
enum DemoData {

    @discardableResult
    static func build(context: ModelContext, days: Int = 30, now: Date = .now) -> (family: Family, members: [Member]) {
        let familyID = UUID()
        let family = Family(name: "王家", ownerID: UUID(), timezoneID: TimeZone.current.identifier, isDemo: true)

        let dad = Member(familyID: familyID, name: "爸爸", emoji: "👨", role: .admin)
        let mom = Member(familyID: familyID, name: "妈妈", emoji: "👩", role: .admin)
        let ming = Member(familyID: familyID, name: "小明", emoji: "👦", role: .child)
        let didi = Member(familyID: familyID, name: "弟弟", emoji: "👧", role: .child)
        let grandma = Member(familyID: familyID, name: "奶奶", emoji: "👵", role: .elder)
        family.ownerID = mom.id
        family.id = familyID
        context.insert(family)
        let members = [dad, mom, ming, didi, grandma]
        members.forEach { context.insert($0) }

        // 规则：有老人家庭包（覆盖五口场景）
        FamilyService.applyTemplate(.withElder, to: family, context: context)
        FamilyService.createDefaultRewards(for: family, context: context)

        let rules = FamilyService.activeRules(of: family, context: context)
        let positive = rules.filter { $0.points > 0 }
        guard !positive.isEmpty else { return (family, members) }

        // 每人偏好权重：让排行有故事感（妈妈家务王、小明学习王、爸爸健康王）
        func preferredRules(for member: Member) -> [Rule] {
            switch member.role {
            case .admin where member == dad:
                return positive.sorted { ($0.category == .health ? 0 : 1) < ($1.category == .health ? 0 : 1) }
            case .admin:
                return positive.sorted { ($0.category == .chore ? 0 : 1) < ($1.category == .chore ? 0 : 1) }
            case .child where member == ming:
                return positive.sorted { ($0.category == .study ? 0 : 1) < ($1.category == .study ? 0 : 1) }
            case .child:
                return positive.sorted { ($0.category == .chore ? 0 : 1) < ($1.category == .chore ? 0 : 1) }
            case .elder:
                return positive.filter { $0.category == .health || $0.category == .emotion }
            }
        }

        var rng = RewardService.SplitMix64(seed: 20261116)

        // 30 天历史记录
        for dayOffset in stride(from: days - 1, through: 0, by: -1) {
            let day = now.addingTimeInterval(Double(-dayOffset) * 86400)
            for member in members {
                let prefs = preferredRules(for: member)
                let baseCount: Int
                switch member.role {
                case .admin: baseCount = 2
                case .child: baseCount = member == ming ? 3 : 2
                case .elder: baseCount = 1
                }
                let extra = Int(rng.next() % 3) // 0-2 条浮动
                let count = baseCount + extra
                for _ in 0..<count {
                    // 70% 从偏好类挑，30% 全池随机
                    let pool = (rng.next() % 10) < 7 ? Array(prefs.prefix(8)) : positive
                    let rule = pool[Int(rng.next() % UInt64(pool.count))]
                    let hour = 7 + rng.next() % 14 // 7:00–21:00
                    let at = day.addingTimeInterval(Double(hour) * 3600 + Double(rng.next() % 3600))
                    if at > now { continue }
                    // 周末双倍活动（§14.3 随机事件演示）
                    let savedMultiplier = family.settingsData.doublePointsMultiplier
                    if dayOffset % 7 == 5 || dayOffset % 7 == 6 {
                        family.settingsData.doublePointsMultiplier = 2.0
                    }
                    let demoNote = "体验数据"
                    _ = try? ScoreEngine.submit(
                        member: member, family: family, rule: rule, note: demoNote,
                        at: at, actorIsAdmin: true, approver: member.role == .admin ? member.id : mom.id,
                        forceRepeated: true, // 演示数据跳过重复窗口
                        context: context, autosave: false)
                    family.settingsData.doublePointsMultiplier = savedMultiplier
                }
            }
        }

        // 今日待办（指派）
        let trashRule = rules.first { $0.name == "倒垃圾" }
        let readRule = rules.first { $0.name == "阅读 30 分钟" }
        let todayKey = FamilyCalendar.dayKey(now, timezoneID: family.timezoneID)
        if let t = trashRule {
            context.insert(TaskAssignment(familyID: family.id, ruleID: t.id,
                                          assigneeID: didi.id, assignerID: mom.id, dueDay: todayKey))
        }
        if let r = readRule {
            context.insert(TaskAssignment(familyID: family.id, ruleID: r.id,
                                          assigneeID: ming.id, assignerID: mom.id, dueDay: todayKey))
        }

        // 一笔已兑换 + 一笔待核销
        let rewards = FamilyService.rewards(of: family, context: context)
        if let chorePass = rewards.first(where: { $0.title.contains("免做") }) {
            _ = try? RewardService.redeem(member: ming, family: family, reward: chorePass,
                                          at: now.addingTimeInterval(-86400), context: context,
                                          autosave: false)
        }
        if let ice = rewards.first(where: { $0.title.contains("冰淇淋") }) {
            _ = try? RewardService.redeem(member: didi, family: family, reward: ice,
                                          at: now.addingTimeInterval(-3600), context: context,
                                          autosave: false)
        }

        // 心愿单
        if let money = rewards.first(where: { $0.title.contains("零花钱") }) {
            context.insert(WishListItem(memberID: ming.id, rewardID: money.id))
        }

        // 徽章：全家"首周满勤"式徽章点缀
        context.insert(Badge(memberID: mom.id, badgeKey: "weekFull"))
        context.insert(Badge(memberID: ming.id, badgeKey: "studyKing"))

        try? context.save()
        return (family, members)
    }
}
