import Foundation
import SwiftData
import UIKit

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
        // v2.1：生日样例——妈妈今天生日、小明 3 天后，首页提醒卡立即可见
        mom.birthday = Calendar.current.date(byAdding: .year, value: -34,
                                             to: Calendar.current.startOfDay(for: now)) ?? now
        ming.birthday = now.addingTimeInterval(3 * 86400)
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
        // v3.2：一条昨天过期未完成的指派（首页过期卡片 + 家长减分入口演示）
        if let petRule = rules.first(where: { $0.name == "遛宠物" }) {
            let yesterdayKey = FamilyCalendar.dayKey(now.addingTimeInterval(-86400),
                                                     timezoneID: family.timezoneID)
            let a = TaskAssignment(familyID: family.id, ruleID: petRule.id,
                                   assigneeID: didi.id, assignerID: mom.id, dueDay: yesterdayKey)
            context.insert(a)
            a.status = .expired
        }
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

        // 小明以儿童身份刚提交的洗碗记录（带拍照凭证）→ 妈妈首页可见待评审、动态可回看
        if let dish = rules.first(where: { $0.name == "洗碗" }) {
            _ = try? ScoreEngine.submit(
                member: ming, family: family, rule: dish,
                note: "晚饭的碗我来洗",
                proofImageData: DemoData.sampleProofImage(),
                at: now.addingTimeInterval(-1800),
                actorIsAdmin: false, approver: nil, context: context)
        }

        // 徽章：全家"首周满勤"式徽章点缀
        context.insert(Badge(memberID: mom.id, badgeKey: "weekFull"))
        context.insert(Badge(memberID: ming.id, badgeKey: "studyKing"))

        try? context.save()
        return (family, members)
    }

    /// 演示凭证图：浅橙底 + 白碗简笔（UIGraphics 绘制，确定性）
    static func sampleProofImage() -> Data? {
        let size = CGSize(width: 480, height: 640)
        let r = UIGraphicsImageRenderer(size: size)
        let img = r.image { ctx in
            UIColor(red: 1.00, green: 0.93, blue: 0.86, alpha: 1).setFill()
            ctx.cgContext.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 140, y: 250, width: 200, height: 120))
            ctx.cgContext.fill(CGRect(x: 190, y: 220, width: 100, height: 40))
            UIColor(red: 1.00, green: 0.54, blue: 0.24, alpha: 1).setFill()
            ctx.cgContext.fill(CGRect(x: 60, y: 460, width: 360, height: 70))
        }
        return img.jpegData(compressionQuality: 0.85)
    }
}
