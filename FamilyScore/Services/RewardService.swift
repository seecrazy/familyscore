import Foundation
import SwiftData

enum RewardError: LocalizedError, Equatable {
    case inactive
    case outOfStock
    case insufficient(need: Int, have: Int)

    var errorDescription: String? {
        switch self {
        case .inactive: "该奖励已下架"
        case .outOfStock: "库存不足"
        case .insufficient(let need, let have): "还差 \(need - have) 分（拥有 \(have) 分）"
        }
    }
}

enum RewardService {

    // MARK: 商场管理辅助（v3.4：查重复用 + 快捷上下架）

    /// 按名称查已有奖励（含已下架）——新建时避免重复录入，复用配置重新上架
    static func findExisting(familyID: UUID, title: String, context: ModelContext) -> Reward? {
        let name = title.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let desc = FetchDescriptor<Reward>(predicate: #Predicate {
            $0.familyID == familyID && $0.title == name
        })
        return (try? context.fetch(desc))?.first
    }

    /// 图标占用映射（icon -> 占用奖励名）：新奖励选图标时禁选已占用（排除正在编辑的自身）
    static func occupiedIconMap(rewards: [Reward], excluding editingID: UUID?) -> [String: String] {
        rewards.filter { $0.id != editingID }
            .reduce(into: [:]) { map, r in
                if map[r.icon] == nil { map[r.icon] = r.title }  // 同图标多奖励取第一个
            }
    }

    /// 快捷上架/下架（列表滑动操作）
    static func setActive(_ reward: Reward, _ active: Bool, context: ModelContext) {
        reward.isActive = active
        AuditService.log(familyID: reward.familyID, actorID: reward.familyID, action: .config,
                         targetID: reward.id,
                         reason: active ? "上架「\(reward.title)」" : "下架「\(reward.title)」",
                         context: context)
        try? context.save()
    }

    // MARK: 兑换

    @discardableResult
    static func redeem(member: Member, family: Family, reward: Reward,
                       at date: Date = .now, context: ModelContext, autosave: Bool = true) throws -> Redemption {
        guard reward.isActive else { throw RewardError.inactive }
        guard reward.stock != 0 else { throw RewardError.outOfStock }
        let cost = reward.effectiveCost(at: date)
        guard member.availableScore >= cost else {
            throw RewardError.insufficient(need: cost, have: member.availableScore)
        }

        member.availableScore -= cost
        ScoreEngine.deductLots(memberID: member.id, points: cost, context: context)

        let code = generateCode()
        let redemption = Redemption(rewardID: reward.id, memberID: member.id,
                                    familyID: family.id, cost: cost, code: code, createdAt: date)
        context.insert(redemption)

        if reward.stock > 0 { reward.stock -= 1 }
        AuditService.log(familyID: family.id, actorID: member.id, action: .redeem,
                         targetID: redemption.id, reason: reward.title, context: context)
        if autosave { try context.save() }
        return redemption
    }

    /// 家长核销
    static func confirm(_ redemption: Redemption, by admin: Member, context: ModelContext) throws {
        guard admin.role == .admin else { return }
        guard redemption.status == .pending else { return }
        redemption.status = .confirmed
        redemption.confirmedAt = .now
        AuditService.log(familyID: redemption.familyID, actorID: admin.id, action: .approve,
                         targetID: redemption.id, context: context)
        try context.save()
    }

    /// 作废兑换并退分（退为当月新批次，§6.2）
    static func cancel(_ redemption: Redemption, family: Family, context: ModelContext) throws {
        guard redemption.status == .pending else { return }
        redemption.status = .cancelled
        if let member = ScoreEngine.fetchMember(redemption.memberID, context: context) {
            member.availableScore += redemption.cost
            ScoreEngine.addLot(memberID: member.id, points: redemption.cost, at: .now,
                               timezoneID: family.timezoneID, context: context)
        }
        AuditService.log(familyID: family.id, actorID: family.ownerID, action: .reverse,
                         targetID: redemption.id, reason: "兑换作废退分", context: context)
        try context.save()
    }

    // MARK: 核销码（§22.2：Crockford base32 + Luhn-mod-N 校验位，格式 FS-XXXX-XXXX）

    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ") // 31 位，去易混淆 I L O U

    static func generateCode(payloadLength: Int = 7, seed: UInt64 = UInt64.random(in: 0...UInt64.max)) -> String {
        var rng = SplitMix64(seed: seed)
        var payload = ""
        for _ in 0..<payloadLength {
            payload.append(alphabet[Int(rng.next() % UInt64(alphabet.count))])
        }
        let full = payload + String(alphabet[luhnCheckDigit(payload)])
        let chars = Array(full)
        return "FS-\(String(chars[0..<4]))-\(String(chars[4..<8]))"
    }

    static func isValidCode(_ code: String) -> Bool {
        let clean = code.replacingOccurrences(of: "-", with: "")
        guard clean.hasPrefix("FS"), clean.count == 10 else { return false }
        let body = String(clean.dropFirst(2))           // 7 位 payload + 1 位校验
        let payload = String(body.dropLast())
        guard let check = body.last, let checkIdx = alphabet.firstIndex(of: check) else { return false }
        return checkIdx == luhnCheckDigit(payload)
    }

    private static func luhnCheckDigit(_ payload: String) -> Int {
        let n = alphabet.count
        let sum = luhnSum(payload) // factor 从右端起 2（追加校验位后右端即校验位）
        return (n - sum % n) % n
    }

    private static func luhnSum(_ s: String) -> Int {
        let n = alphabet.count
        var factor = 2, sum = 0
        for ch in s.reversed() {
            guard let idx = alphabet.firstIndex(of: ch) else { return -1 }
            var addend = idx * factor
            if addend > n - 1 { addend -= (n - 1) }
            sum += addend
            factor = 3 - factor
        }
        return sum
    }

    /// 确定性随机（测试与演示数据可复现）
    struct SplitMix64 {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    // MARK: 批次过期（§6.2 v2：满 12 个月打五折入永久池）

    struct ExpiryReport: Equatable {
        var memberID: UUID
        var halvedAmount: Int   // 打折损失的分数
        var keptAmount: Int     // 转入永久池的分数
    }

    /// monthKey 距给定日期已满 expiryMonths 个月的批次 → amount 打五折（floor），isPermanent = true
    @discardableResult
    static func expireLots(member: Member, at date: Date = .now, expiryMonths: Int = 12,
                           timezoneID: String = TimeZone.current.identifier,
                           context: ModelContext) throws -> [ExpiryReport] {
        guard let currentTotalMonths = totalMonths(FamilyCalendar.monthKey(date, timezoneID: timezoneID)) else {
            return []
        }
        let mid = member.id
        let desc = FetchDescriptor<ScoreLot>(predicate: #Predicate {
            $0.memberID == mid && $0.isPermanent == false
        })
        var reports: [ExpiryReport] = []
        for lot in (try context.fetch(desc)) {
            guard let lotMonths = totalMonths(lot.monthKey),
                  currentTotalMonths - lotMonths >= expiryMonths else { continue }
            let kept = lot.amount / 2
            let halved = lot.amount - kept
            lot.amount = kept
            lot.isPermanent = true
            if halved > 0 || kept > 0 {
                reports.append(ExpiryReport(memberID: member.id, halvedAmount: halved, keptAmount: kept))
            }
        }
        // 同步冗余快照
        member.availableScore = totalAvailable(memberID: member.id, context: context)
        try context.save()
        return reports
    }

    /// 即将到期批次（提前约 30 天提醒，§6.2）：批次年龄已到 [expiryMonths-1, expiryMonths) 个月
    static func expiringLots(member: Member, withinDays: Int = 30, expiryMonths: Int = 12,
                             at date: Date = .now, timezoneID: String = TimeZone.current.identifier,
                             context: ModelContext) -> [ScoreLot] {
        guard let currentTotalMonths = totalMonths(FamilyCalendar.monthKey(date, timezoneID: timezoneID)) else {
            return []
        }
        let mid = member.id
        let desc = FetchDescriptor<ScoreLot>(predicate: #Predicate {
            $0.memberID == mid && $0.isPermanent == false
        })
        return ((try? context.fetch(desc)) ?? []).filter {
            guard let lotMonths = totalMonths($0.monthKey) else { return false }
            let age = currentTotalMonths - lotMonths
            return (expiryMonths - 1..<expiryMonths).contains(age) && $0.amount > 0
        }
    }

    /// "yyyy-MM" → y*12+m；非法返回 nil
    private static func totalMonths(_ key: String) -> Int? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, parts[1] >= 1, parts[1] <= 12 else { return nil }
        return parts[0] * 12 + parts[1]
    }

    static func totalAvailable(memberID: UUID, context: ModelContext) -> Int {
        let desc = FetchDescriptor<ScoreLot>(predicate: #Predicate { $0.memberID == memberID })
        return ((try? context.fetch(desc)) ?? []).reduce(0) { $0 + $1.amount }
    }
}
