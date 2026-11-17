import Foundation
import SwiftData

/// 数据导出/导入（§8.5 / §15 分家导出）：全量 JSON 或按成员子集，跨设备可导入合并
enum ExportService {

    struct ExportBundle: Codable {
        var formatVersion: Int = 1
        var exportedAt: Date
        var app: String = "FamilyScore"
        var family: FamilyDTO
        var members: [MemberDTO]
        var rules: [RuleDTO]
        var records: [RecordDTO]
        var rewards: [RewardDTO]
        var redemptions: [RedemptionDTO]
        var lots: [LotDTO]
        var assignments: [AssignmentDTO]
        var badges: [BadgeDTO]
    }

    // MARK: DTO（导出结构稳定，不随 SwiftData schema 变）

    struct FamilyDTO: Codable {
        var id: UUID; var name: String; var createdAt: Date
        var ownerID: UUID; var timezoneID: String
        var settings: FamilySettings
    }
    struct MemberDTO: Codable {
        var id: UUID; var familyID: UUID; var name: String; var emoji: String
        var role: String; var coefficient: Double
        var cumulativeScore: Int; var availableScore: Int
        var joinedAt: Date; var status: String
        var streakDays: Int; var lastCheckInDay: String?
        var birthday: Date?
    }
    struct RuleDTO: Codable {
        var id: UUID; var familyID: UUID; var category: String; var name: String
        var icon: String; var points: Int; var dailyLimit: Int
        var requiresApproval: Bool; var isActive: Bool; var sortOrder: Int
    }
    struct RecordDTO: Codable {
        var id: UUID; var familyID: UUID; var memberID: UUID; var ruleID: UUID?
        var points: Int; var basePoints: Int; var coefficient: Double; var multiplier: Double
        var category: String; var note: String?
        var status: String; var createdAt: Date; var approvedBy: UUID?
        var isReversal: Bool
    }
    struct RewardDTO: Codable {
        var id: UUID; var familyID: UUID; var title: String; var icon: String
        var cost: Int; var stock: Int; var isActive: Bool
    }
    struct RedemptionDTO: Codable {
        var id: UUID; var rewardID: UUID; var memberID: UUID; var familyID: UUID
        var cost: Int; var code: String; var status: String; var createdAt: Date
    }
    struct LotDTO: Codable {
        var id: UUID; var memberID: UUID; var monthKey: String; var amount: Int; var isPermanent: Bool
    }
    struct AssignmentDTO: Codable {
        var id: UUID; var familyID: UUID; var ruleID: UUID; var assigneeID: UUID
        var assignerID: UUID; var dueDay: String; var status: String; var createdAt: Date
    }
    struct BadgeDTO: Codable {
        var id: UUID; var memberID: UUID; var badgeKey: String; var unlockedAt: Date
    }

    // MARK: 导出

    /// 全量导出；`memberFilter` 非空时做"分家导出"（§15：只带相关成员与记录）
    static func export(family: Family, context: ModelContext,
                       memberFilter: [UUID]? = nil) throws -> ExportBundle {
        let fid = family.id
        let members = ((try? context.fetch(FetchDescriptor<Member>(
            predicate: #Predicate { $0.familyID == fid }))) ?? [])
            .filter { memberFilter?.contains($0.id) ?? true }
        let memberIDs = Set(members.map(\.id))
        let ownerIncluded = memberFilter == nil || memberIDs.contains(family.ownerID)

        let rules = ((try? context.fetch(FetchDescriptor<Rule>(
            predicate: #Predicate { $0.familyID == fid }))) ?? [])
        let records = ((try? context.fetch(FetchDescriptor<ScoreRecord>(
            predicate: #Predicate { $0.familyID == fid }))) ?? [])
            .filter { memberFilter == nil || memberIDs.contains($0.memberID) }
        let rewards = ((try? context.fetch(FetchDescriptor<Reward>(
            predicate: #Predicate { $0.familyID == fid }))) ?? [])
        let redemptions = ((try? context.fetch(FetchDescriptor<Redemption>(
            predicate: #Predicate { $0.familyID == fid }))) ?? [])
            .filter { memberFilter == nil || memberIDs.contains($0.memberID) }
        let lots = ((try? context.fetch(FetchDescriptor<ScoreLot>(/* 全部再按成员筛 */)))) ?? []
        let lotDTOs = lots.filter { memberIDs.contains($0.memberID) }
        let assignments = ((try? context.fetch(FetchDescriptor<TaskAssignment>(
            predicate: #Predicate { $0.familyID == fid }))) ?? [])
            .filter { memberFilter == nil || memberIDs.contains($0.assigneeID) }
        let badges = ((try? context.fetch(FetchDescriptor<Badge>(/* 全部再按成员筛 */)))) ?? []
        let badgeDTOs = badges.filter { memberIDs.contains($0.memberID) }

        var dto = ExportBundle(
            exportedAt: .now,
            family: FamilyDTO(id: family.id, name: family.name, createdAt: family.createdAt,
                              ownerID: ownerIncluded ? family.ownerID : (members.first?.id ?? family.ownerID),
                              timezoneID: family.timezoneID, settings: family.settingsData),
            members: members.map {
                MemberDTO(id: $0.id, familyID: $0.familyID, name: $0.name, emoji: $0.emoji,
                          role: $0.role.rawValue, coefficient: $0.coefficient,
                          cumulativeScore: $0.cumulativeScore, availableScore: $0.availableScore,
                          joinedAt: $0.joinedAt, status: $0.status.rawValue,
                          streakDays: $0.streakDays, lastCheckInDay: $0.lastCheckInDay,
                          birthday: $0.birthday)
            },
            rules: rules.map {
                RuleDTO(id: $0.id, familyID: $0.familyID, category: $0.category.rawValue,
                        name: $0.name, icon: $0.icon, points: $0.points, dailyLimit: $0.dailyLimit,
                        requiresApproval: $0.requiresApproval, isActive: $0.isActive, sortOrder: $0.sortOrder)
            },
            records: records.map {
                RecordDTO(id: $0.id, familyID: $0.familyID, memberID: $0.memberID, ruleID: $0.ruleID,
                          points: $0.points, basePoints: $0.basePoints, coefficient: $0.coefficient,
                          multiplier: $0.multiplier, category: $0.category.rawValue, note: $0.note,
                          status: $0.status.rawValue, createdAt: $0.createdAt, approvedBy: $0.approvedBy,
                          isReversal: $0.isReversal)
            },
            rewards: rewards.map {
                RewardDTO(id: $0.id, familyID: $0.familyID, title: $0.title, icon: $0.icon,
                          cost: $0.cost, stock: $0.stock, isActive: $0.isActive)
            },
            redemptions: redemptions.map {
                RedemptionDTO(id: $0.id, rewardID: $0.rewardID, memberID: $0.memberID,
                              familyID: $0.familyID, cost: $0.cost, code: $0.code,
                              status: $0.status.rawValue, createdAt: $0.createdAt)
            },
            lots: lotDTOs.map {
                LotDTO(id: $0.id, memberID: $0.memberID, monthKey: $0.monthKey,
                       amount: $0.amount, isPermanent: $0.isPermanent)
            },
            assignments: assignments.map {
                AssignmentDTO(id: $0.id, familyID: $0.familyID, ruleID: $0.ruleID,
                              assigneeID: $0.assigneeID, assignerID: $0.assignerID,
                              dueDay: $0.dueDay, status: $0.status.rawValue, createdAt: $0.createdAt)
            },
            badges: badgeDTOs.map {
                BadgeDTO(id: $0.id, memberID: $0.memberID, badgeKey: $0.badgeKey, unlockedAt: $0.unlockedAt)
            })
        // 凭证图片不导出（体积与隐私，§8.5 数据导出为账面数据）
        _ = dto.formatVersion
        return dto
    }

    static func encode(_ bundle: ExportBundle) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(bundle)
    }

    static func decode(_ data: Data) throws -> ExportBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ExportBundle.self, from: data)
    }

    // MARK: 导入（幂等：按 UUID 去重，已存在跳过；跨家庭导入生成新家庭）

    struct ImportReport: Equatable {
        var familyName: String
        var membersImported: Int
        var recordsImported: Int
        var rewardsImported: Int
        var skippedExisting: Int

        var summary: String {
            "已导入「\(familyName)」：\(membersImported) 位成员、\(recordsImported) 条积分记录、\(rewardsImported) 个奖励（跳过已存在 \(skippedExisting) 条）"
        }
    }

    @discardableResult
    static func `import`(_ bundle: ExportBundle, context: ModelContext) throws -> ImportReport {
        var report = ImportReport(familyName: bundle.family.name, membersImported: 0,
                                  recordsImported: 0, rewardsImported: 0, skippedExisting: 0)

        // 已存在的家庭（同 id）→ 幂等合并（只补缺失记录）；否则整包导入为新家庭
        let fid = bundle.family.id
        let existingFamily = (try? context.fetch(FetchDescriptor<Family>(
            predicate: #Predicate { $0.id == fid })))?.first

        func existingIDs<T: PersistentModel>(_ keyPath: KeyPath<T, UUID>) -> Set<UUID> {
            let all = (try? context.fetch(FetchDescriptor<T>())) ?? []
            return Set(all.map { $0[keyPath: keyPath] })
        }

        let family: Family
        if let f = existingFamily {
            family = f
        } else {
            let f = Family(name: bundle.family.name, ownerID: bundle.family.ownerID,
                           timezoneID: bundle.family.timezoneID,
                           settings: bundle.family.settings, createdAt: bundle.family.createdAt)
            f.id = bundle.family.id
            context.insert(f)
            family = f
        }

        let memberIDs = existingIDs(\Member.id)
        for dto in bundle.members where !memberIDs.contains(dto.id) {
            let m = Member(familyID: family.id, name: dto.name, emoji: dto.emoji,
                           role: MemberRole(rawValue: dto.role) ?? .child,
                           coefficient: dto.coefficient, joinedAt: dto.joinedAt)
            m.id = dto.id
            m.cumulativeScore = dto.cumulativeScore
            m.availableScore = dto.availableScore
            m.status = MemberStatus(rawValue: dto.status) ?? .active
            m.streakDays = dto.streakDays
            m.lastCheckInDay = dto.lastCheckInDay
            m.birthday = dto.birthday
            context.insert(m)
            report.membersImported += 1
        }
        report.skippedExisting += bundle.members.count - report.membersImported

        let ruleIDs = existingIDs(\Rule.id)
        for dto in bundle.rules where !ruleIDs.contains(dto.id) {
            let r = Rule(familyID: family.id, category: RuleCategory(rawValue: dto.category) ?? .chore,
                         name: dto.name, icon: dto.icon, points: dto.points, dailyLimit: dto.dailyLimit,
                         requiresApproval: dto.requiresApproval, isActive: dto.isActive,
                         sortOrder: dto.sortOrder)
            r.id = dto.id
            context.insert(r)
        }

        let recordIDs = existingIDs(\ScoreRecord.id)
        for dto in bundle.records where !recordIDs.contains(dto.id) {
            let r = ScoreRecord(familyID: family.id, memberID: dto.memberID, ruleID: dto.ruleID,
                                points: dto.points, basePoints: dto.basePoints,
                                coefficient: dto.coefficient, multiplier: dto.multiplier,
                                category: RuleCategory(rawValue: dto.category) ?? .chore,
                                note: dto.note, status: RecordStatus(rawValue: dto.status) ?? .approved,
                                createdAt: dto.createdAt, approvedBy: dto.approvedBy,
                                isReversal: dto.isReversal)
            r.id = dto.id
            context.insert(r)
            report.recordsImported += 1
        }
        report.skippedExisting += bundle.records.count - report.recordsImported

        let rewardIDs = existingIDs(\Reward.id)
        for dto in bundle.rewards where !rewardIDs.contains(dto.id) {
            let r = Reward(familyID: family.id, title: dto.title, icon: dto.icon,
                           cost: dto.cost, stock: dto.stock, isActive: dto.isActive)
            r.id = dto.id
            context.insert(r)
            report.rewardsImported += 1
        }

        let redemptionIDs = existingIDs(\Redemption.id)
        for dto in bundle.redemptions where !redemptionIDs.contains(dto.id) {
            let r = Redemption(rewardID: dto.rewardID, memberID: dto.memberID, familyID: family.id,
                               cost: dto.cost, code: dto.code, createdAt: dto.createdAt)
            r.id = dto.id
            r.status = RedemptionStatus(rawValue: dto.status) ?? .pending
            context.insert(r)
        }

        let lotIDs = existingIDs(\ScoreLot.id)
        for dto in bundle.lots where !lotIDs.contains(dto.id) {
            let l = ScoreLot(memberID: dto.memberID, monthKey: dto.monthKey,
                             amount: dto.amount, isPermanent: dto.isPermanent)
            l.id = dto.id
            context.insert(l)
        }

        let assignmentIDs = existingIDs(\TaskAssignment.id)
        for dto in bundle.assignments where !assignmentIDs.contains(dto.id) {
            let a = TaskAssignment(familyID: family.id, ruleID: dto.ruleID, assigneeID: dto.assigneeID,
                                   assignerID: dto.assignerID, dueDay: dto.dueDay, createdAt: dto.createdAt)
            a.id = dto.id
            a.status = AssignmentStatus(rawValue: dto.status) ?? .open
            context.insert(a)
        }

        let badgeIDs = existingIDs(\Badge.id)
        for dto in bundle.badges where !badgeIDs.contains(dto.id) {
            let b = Badge(memberID: dto.memberID, badgeKey: dto.badgeKey, unlockedAt: dto.unlockedAt)
            b.id = dto.id
            context.insert(b)
        }

        try context.save()
        return report
    }
}
