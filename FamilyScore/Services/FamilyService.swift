import Foundation
import SwiftData

/// 家庭生命周期服务：创建、成员管理、模板落库（DESIGN.md §3/§15）
enum FamilyService {

    @discardableResult
    static func createFamily(
        name: String, myName: String, myRole: MemberRole, myEmoji: String,
        template: RuleTemplateService.TemplateKind,
        timezoneID: String = TimeZone.current.identifier,
        context: ModelContext
    ) -> (family: Family, owner: Member) {
        let familyID = UUID()
        let owner = Member(familyID: familyID, name: myName, emoji: myEmoji, role: myRole)
        let family = Family(name: name, ownerID: owner.id, timezoneID: timezoneID)
        family.id = familyID
        context.insert(family)
        context.insert(owner)

        applyTemplate(template, to: family, context: context)
        createDefaultRewards(for: family, context: context)
        try? context.save()
        return (family, owner)
    }

    static func applyTemplate(_ template: RuleTemplateService.TemplateKind, to family: Family,
                              context: ModelContext) {
        for (i, draft) in RuleTemplateService.rules(for: template).enumerated() {
            context.insert(Rule(familyID: family.id, category: draft.category, name: draft.name,
                                icon: draft.icon, points: draft.points, dailyLimit: draft.dailyLimit,
                                requiresApproval: draft.requiresApproval, sortOrder: i))
        }
    }

    static func createDefaultRewards(for family: Family, context: ModelContext) {
        for d in RuleTemplateService.defaultRewardDrafts() {
            context.insert(Reward(familyID: family.id, title: d.title, icon: d.icon, cost: d.cost,
                                  discountCost: d.discount, discountEndsAt: d.discountEndsAt,
                                  stock: d.stock))
        }
    }

    @discardableResult
    static func addMember(to family: Family, name: String, role: MemberRole, emoji: String,
                          context: ModelContext) -> Member {
        let m = Member(familyID: family.id, name: name, emoji: emoji, role: role)
        context.insert(m)
        try? context.save()
        return m
    }

    /// 成员退出（§15）：历史积分保留、不参与新排名
    static func exitMember(_ member: Member, context: ModelContext) {
        member.status = .exited
        try? context.save()
    }

    static func members(of family: Family, context: ModelContext) -> [Member] {
        let fid = family.id
        let desc = FetchDescriptor<Member>(predicate: #Predicate { $0.familyID == fid },
                                           sortBy: [SortDescriptor(\.joinedAt, order: .forward)])
        return (try? context.fetch(desc)) ?? []
    }

    static func activeRules(of family: Family, context: ModelContext) -> [Rule] {
        let fid = family.id
        let desc = FetchDescriptor<Rule>(predicate: #Predicate { $0.familyID == fid && $0.isActive == true },
                                         sortBy: [SortDescriptor(\.sortOrder, order: .forward)])
        return (try? context.fetch(desc)) ?? []
    }

    static func rewards(of family: Family, context: ModelContext) -> [Reward] {
        let fid = family.id
        let desc = FetchDescriptor<Reward>(predicate: #Predicate { $0.familyID == fid && $0.isActive == true },
                                           sortBy: [SortDescriptor(\.cost, order: .forward)])
        return (try? context.fetch(desc)) ?? []
    }
}
