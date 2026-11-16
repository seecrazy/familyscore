import Foundation
import SwiftData

/// 积分规则引擎（DESIGN.md §6）：计分公式、上限、防刷、双轨入账、撤销、连续打卡
enum ScoreEngineError: LocalizedError, Equatable {
    case ruleInactive
    case dailyLimitReached(remainingToday: Int)
    case repeatWindow(minutes: Int)
    case deductionCapReached(appliedThisTime: Int)
    case duplicateProof
    case onlyAdminCanDeduct
    case approverDailyLimitReached
    case onlyAdminCanApprove
    case recordNotPending

    var errorDescription: String? {
        switch self {
        case .ruleInactive: "该规则已停用"
        case .dailyLimitReached(let r): "今日该行为已达上限（还可 \(r) 次）"
        case .repeatWindow(let m): " \(m) 分钟内已提交过，请勿重复"
        case .deductionCapReached(let applied): "已达每日减分上限，本次实际扣 \(applied) 分"
        case .duplicateProof: "这张凭证今天已经用过了"
        case .onlyAdminCanDeduct: "减分需由家长发起"
        case .approverDailyLimitReached: "今日确认次数已达上限（20 条）"
        case .onlyAdminCanApprove: "只有家长可以确认"
        case .recordNotPending: "该记录不在待确认状态"
        }
    }
}

enum SubmitOutcome: Equatable {
    case approved(ScoreRecord)   // 已入账
    case pendingApproval(ScoreRecord) // 待家长确认（未入账）
}

enum ScoreEngine {

    // MARK: 计分公式（§6.1）：round(基础分 × 系数 × 倍率)，负分同规则（−5×1.2 = −6）

    static func computedPoints(base: Int, coefficient: Double, multiplier: Double) -> Int {
        Int((Double(base) * coefficient * multiplier).rounded())
    }

    // MARK: 提交行为

    /// 提交一次行为。`forceRepeated` 用于 UI 层"5 分钟内重复"二次确认放行（§6.4-2）。
    @discardableResult
    static func submit(
        member: Member, family: Family, rule: Rule,
        note: String? = nil, proofHash: String? = nil,
        at date: Date = .now, actorIsAdmin: Bool,
        approver: UUID? = nil, forceRepeated: Bool = false,
        context: ModelContext, autosave: Bool = true
    ) throws -> SubmitOutcome {
        guard rule.isActive else { throw ScoreEngineError.ruleInactive }
        guard rule.familyID == family.id, member.familyID == family.id else {
            throw ScoreEngineError.ruleInactive
        }

        // 减分必须家长发起（§6.3/§6.4-6）
        if rule.isDeduction, !actorIsAdmin { throw ScoreEngineError.onlyAdminCanDeduct }

        // 5 分钟重复窗口
        if !forceRepeated {
            let memberID = member.id, ruleID = rule.id
            let window = TimeInterval(family.settingsData.repeatWindowMinutes * 60)
            let cutoff = date.addingTimeInterval(-window)
            let desc = FetchDescriptor<ScoreRecord>(predicate: #Predicate {
                $0.memberID == memberID && $0.ruleID == ruleID && $0.createdAt >= cutoff
            })
            let recent = ((try? context.fetch(desc)) ?? []).filter { $0.status != .rejected }
            if !recent.isEmpty {
                throw ScoreEngineError.repeatWindow(minutes: family.settingsData.repeatWindowMinutes)
            }
        }

        // 凭证哈希当日重复 → 实时拒绝（A4，§13.1）
        if let ph = proofHash, !ph.isEmpty {
            let fid = family.id
            let dayStart = FamilyCalendar.startOfDay(date, timezoneID: family.timezoneID)
            let dayEnd = dayStart.addingTimeInterval(86400)
            let dup = FetchDescriptor<ScoreRecord>(predicate: #Predicate {
                $0.familyID == fid && $0.proofHash == ph && $0.createdAt >= dayStart && $0.createdAt < dayEnd
            })
            if let hit = try? context.fetch(dup), !hit.isEmpty {
                throw ScoreEngineError.duplicateProof
            }
        }

        // 每日规则次数上限（§6.4-1；pending 记录也占位防重复提交）
        if rule.dailyLimit > 0 {
            let used = countToday(member: member, rule: rule, family: family, at: date, context: context)
            if used >= rule.dailyLimit {
                throw ScoreEngineError.dailyLimitReached(remainingToday: 0)
            }
        }

        let multiplier = family.settingsData.doublePointsMultiplier
        var points = computedPoints(base: rule.points, coefficient: member.coefficient, multiplier: multiplier)
        var finalNote = note

        // 每日减分上限 −20（§6.1）：截断到剩余额度，"超出不再扣"
        if points < 0 {
            let cap = family.settingsData.dailyDeductionCap
            let already = deductedToday(member: member, family: family, at: date, context: context)
            let room = max(0, cap - already)
            let wanted = -points
            if wanted > room {
                points = -room
                finalNote = (finalNote.map { $0 + "；" } ?? "") + "已达每日减分上限，本次实际扣 \(room) 分"
            }
        }

        // 需家长确认 → pending 不入账（§6.3 requiresApproval）；
        // 家长本人操作或代提交（approver 已给出）视为当场确认
        let needApproval = rule.requiresApproval && !(actorIsAdmin && approver != nil)
        let record = ScoreRecord(
            familyID: family.id, memberID: member.id, ruleID: rule.id,
            points: points, basePoints: rule.points, coefficient: member.coefficient,
            multiplier: multiplier, category: rule.category, note: finalNote, proofHash: proofHash,
            status: needApproval ? .pending : .approved,
            createdAt: date, approvedBy: needApproval ? nil : (approver ?? member.id))
        context.insert(record)

        if needApproval {
            return .pendingApproval(record)
        }

        try apply(record: record, to: member, family: family, context: context, autosave: autosave)
        AuditService.log(familyID: family.id, actorID: approver ?? member.id,
                         action: points >= 0 ? .add : .deduct, targetID: record.id,
                         reason: rule.name, context: context)
        return .approved(record)
    }

    // MARK: 审批

    /// 家长确认 pending 记录 → 入账
    @discardableResult
    static func approve(record: ScoreRecord, family: Family, by approver: Member,
                        at date: Date = .now, context: ModelContext) throws -> ScoreRecord {
        guard approver.role == .admin else { throw ScoreEngineError.onlyAdminCanApprove }
        guard record.status == .pending else { throw ScoreEngineError.recordNotPending }

        // 同一确认人每日上限（§6.4-4）
        let count = approvalCountToday(approver: approver, family: family, at: date, context: context)
        if count >= family.settingsData.approverDailyLimit {
            throw ScoreEngineError.approverDailyLimitReached
        }

        guard let member = fetchMember(record.memberID, context: context) else {
            throw ScoreEngineError.recordNotPending
        }
        record.status = .approved
        record.approvedBy = approver.id
        try apply(record: record, to: member, family: family, context: context)
        AuditService.log(familyID: family.id, actorID: approver.id, action: .approve,
                         targetID: record.id, context: context)
        return record
    }

    static func reject(record: ScoreRecord, family: Family, by approver: Member,
                       reason: String? = nil, context: ModelContext) throws {
        guard approver.role == .admin else { throw ScoreEngineError.onlyAdminCanApprove }
        guard record.status == .pending else { throw ScoreEngineError.recordNotPending }
        record.status = .rejected
        AuditService.log(familyID: family.id, actorID: approver.id, action: .reject,
                         targetID: record.id, reason: reason, context: context)
    }

    // MARK: 撤销（append-only 反向记录，§6.4-5）

    @discardableResult
    static func reverse(record: ScoreRecord, family: Family, by admin: Member,
                        reason: String, at date: Date = .now, context: ModelContext) throws -> ScoreRecord {
        guard admin.role == .admin else { throw ScoreEngineError.onlyAdminCanApprove }
        guard record.status == .approved || record.status == .appealed else {
            throw ScoreEngineError.recordNotPending
        }
        guard let member = fetchMember(record.memberID, context: context) else {
            throw ScoreEngineError.recordNotPending
        }

        let reversal = ScoreRecord(
            familyID: family.id, memberID: record.memberID, ruleID: record.ruleID,
            points: -record.points, basePoints: -record.basePoints,
            coefficient: record.coefficient, multiplier: record.multiplier,
            category: record.category,
            note: "撤销：「\(record.note ?? "记录")」· \(reason)",
            status: .approved, createdAt: date, approvedBy: admin.id,
            backfilledAt: nil, isReversal: true)
        context.insert(reversal)

        record.status = .reversed
        record.reversedRecordID = reversal.id
        try apply(record: reversal, to: member, family: family, context: context)
        AuditService.log(familyID: family.id, actorID: admin.id, action: .reverse,
                         targetID: record.id, reason: reason, context: context)
        return reversal
    }

    // MARK: 入账（双轨 + 批次 + streak）

    /// 将一条 approved 记录的分数效果落到成员快照与积分批次上。
    /// 正向：累计 +，可用 +，批次 +；负向：累计不变，可用 −，扣最早批次（FIFO）。
    static func apply(record: ScoreRecord, to member: Member, family: Family,
                      context: ModelContext, autosave: Bool = true) throws {
        if record.points >= 0 {
            if !record.isReversal {
                // 真实行为分：累计 + streak；撤销减分的反向记录只恢复可用分，不算"获得"
                member.cumulativeScore += record.points
                try updateStreak(member: member, family: family, record: record, context: context)
            }
            member.availableScore += record.points
            addLot(memberID: member.id, points: record.points, at: record.createdAt,
                   timezoneID: family.timezoneID, context: context)
        } else {
            member.availableScore += record.points // 可为负（记账诚实，家长可见"欠分"）
            if record.isReversal {
                member.cumulativeScore += record.points // 撤销加分 → 累计回滚
            }
            deductLots(memberID: member.id, points: -record.points, context: context)
        }
        if autosave { try context.save() }
    }

    // MARK: 连续打卡（§6.1）

    static func updateStreak(member: Member, family: Family, record: ScoreRecord, context: ModelContext) throws {
        let tz = family.timezoneID
        let todayKey = FamilyCalendar.dayKey(record.createdAt, timezoneID: tz)
        guard member.lastCheckInDay != todayKey else { return } // 当日已计

        let yesterdayKey = FamilyCalendar.dayKey(
            record.createdAt.addingTimeInterval(-86400), timezoneID: tz)
        member.streakDays = (member.lastCheckInDay == yesterdayKey) ? member.streakDays + 1 : 1
        member.lastCheckInDay = todayKey

        // 里程碑奖励（每档只发一次，Badge 记录去重）
        let milestones: [(days: Int, bonus: Int, key: String)] = [
            (7, 20, "streak7"), (30, 100, "streak30"), (100, 300, "streak100"),
        ]
        for m in milestones where member.streakDays == m.days {
            let mid = member.id
            let badgeKey = m.key
            let desc = FetchDescriptor<Badge>(predicate: #Predicate { $0.memberID == mid && $0.badgeKey == badgeKey })
            let existing = (try? context.fetch(desc)) ?? []
            if existing.isEmpty {
                context.insert(Badge(memberID: member.id, badgeKey: m.key,
                                     unlockedAt: record.createdAt))
                let bonus = ScoreRecord(
                    familyID: family.id, memberID: member.id, ruleID: nil,
                    points: m.bonus, basePoints: m.bonus, coefficient: 1.0, multiplier: 1.0,
                    category: .special, note: "连续打卡 \(m.days) 天奖励",
                    status: .approved, createdAt: record.createdAt)
                context.insert(bonus)
                member.cumulativeScore += m.bonus
                member.availableScore += m.bonus
                addLot(memberID: member.id, points: m.bonus, at: record.createdAt,
                       timezoneID: tz, context: context)
            }
        }
    }

    // MARK: 统计查询

    static func countToday(member: Member, rule: Rule, family: Family, at date: Date,
                           context: ModelContext) -> Int {
        let start = FamilyCalendar.startOfDay(date, timezoneID: family.timezoneID)
        let end = start.addingTimeInterval(86400)
        let memberID = member.id, ruleID = rule.id
        let desc = FetchDescriptor<ScoreRecord>(predicate: #Predicate {
            $0.memberID == memberID && $0.ruleID == ruleID && $0.createdAt >= start && $0.createdAt < end
        })
        return ((try? context.fetch(desc)) ?? []).filter { $0.status != .rejected }.count
    }

    static func deductedToday(member: Member, family: Family, at date: Date,
                              context: ModelContext) -> Int {
        let start = FamilyCalendar.startOfDay(date, timezoneID: family.timezoneID)
        let end = start.addingTimeInterval(86400)
        let memberID = member.id
        let desc = FetchDescriptor<ScoreRecord>(predicate: #Predicate {
            $0.memberID == memberID && $0.createdAt >= start && $0.createdAt < end && $0.points < 0
        })
        let effective: Set<RecordStatus> = [.approved, .reversed, .appealed]
        let records = ((try? context.fetch(desc)) ?? []).filter { effective.contains($0.status) }
        return -records.reduce(0) { $0 + $1.points }
    }

    static func approvalCountToday(approver: Member, family: Family, at date: Date,
                                   context: ModelContext) -> Int {
        let start = FamilyCalendar.startOfDay(date, timezoneID: family.timezoneID)
        let end = start.addingTimeInterval(86400)
        let approverID = approver.id
        let desc = FetchDescriptor<ScoreRecord>(predicate: #Predicate {
            $0.approvedBy == approverID && $0.createdAt >= start && $0.createdAt < end
        })
        return (try? context.fetch(desc))?.count ?? 0
    }

    // MARK: 批次记账（§6.2 / ScoreLot）

    static func addLot(memberID: UUID, points: Int, at date: Date, timezoneID: String,
                       context: ModelContext) {
        guard points > 0 else { return }
        let key = FamilyCalendar.monthKey(date, timezoneID: timezoneID)
        let desc = FetchDescriptor<ScoreLot>(predicate: #Predicate {
            $0.memberID == memberID && $0.monthKey == key && $0.isPermanent == false
        })
        if let lot = try? context.fetch(desc).first {
            lot.amount += points
        } else {
            context.insert(ScoreLot(memberID: memberID, monthKey: key, amount: points))
        }
    }

    /// FIFO 扣减（先扣最早批次；不够扣时欠账记在最新批次，保证 Σ批次 = availableScore）
    static func deductLots(memberID: UUID, points: Int, context: ModelContext) {
        var remaining = points
        let predicate = #Predicate<ScoreLot> { $0.memberID == memberID }
        let desc = FetchDescriptor<ScoreLot>(predicate: predicate)
        // 非永久先扣、同组内最早先扣（FIFO）
        let lots = ((try? context.fetch(desc)) ?? []).sorted {
            if $0.isPermanent != $1.isPermanent { return !$0.isPermanent }
            return $0.monthKey < $1.monthKey
        }
        for lot in lots where remaining > 0 {
            let take = min(lot.amount, remaining)
            lot.amount -= take
            remaining -= take
        }
        if remaining > 0 {
            // 欠账：记在最新批次；从无批次则记入 "0000-00"（排序最前，后续扣减/新债务优先合并）
            if let newest = lots.last {
                newest.amount -= remaining
            } else {
                context.insert(ScoreLot(memberID: memberID, monthKey: "0000-00", amount: -remaining))
            }
        }
    }

    // MARK: 辅助

    static func fetchMember(_ id: UUID, context: ModelContext) -> Member? {
        var d = FetchDescriptor<Member>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }
}
