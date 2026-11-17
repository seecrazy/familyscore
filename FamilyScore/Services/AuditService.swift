import Foundation
import SwiftData

/// 审计服务：操作留痕 + 异常检测（DESIGN.md §13 / §13.1）
enum AuditService {

    static func log(familyID: UUID, actorID: UUID, action: AuditAction, targetID: UUID,
                    reason: String? = nil, context: ModelContext) {
        context.insert(AuditLog(familyID: familyID, actorID: actorID, action: action,
                                targetID: targetID, reason: reason))
        // 变更记账（云同步队列，§18.3）——审计打点处即变更处，一处覆盖全部
        SyncEngine.record(familyID: familyID, action: action, targetID: targetID, context: context)
    }

    static func logs(familyID: UUID, limit: Int = 200, context: ModelContext) -> [AuditLog] {
        var d = FetchDescriptor<AuditLog>(
            predicate: #Predicate { $0.familyID == familyID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        d.fetchLimit = limit
        return (try? context.fetch(d)) ?? []
    }

    // MARK: 异常检测（A1–A6，只报告不自动处罚）

    struct Anomaly: Identifiable, Equatable {
        let id = UUID()
        let code: String        // A1–A6
        let title: String
        let detail: String
        let memberID: UUID?
    }

    /// 对近 30 天数据跑全部规则
    static func detectAnomalies(family: Family, members: [Member], windowDays: Int = 30,
                                at date: Date = .now, context: ModelContext) -> [Anomaly] {
        let tz = family.timezoneID
        let since = FamilyCalendar.startOfDay(date.addingTimeInterval(Double(-windowDays) * 86400),
                                              timezoneID: tz)
        let fid = family.id
        let desc = FetchDescriptor<ScoreRecord>(predicate: #Predicate {
            $0.familyID == fid && $0.createdAt >= since
        })
        let records = ((try? context.fetch(desc)) ?? []).filter {
            $0.status == .approved || $0.status == .reversed || $0.status == .appealed
        }
        var anomalies: [Anomaly] = []
        let nameOf: (UUID) -> String = { id in members.first { $0.id == id }?.name ?? "成员" }

        // A1 单日净得分突增：> max(50, 家庭日均×3)
        let familyTotal = records.reduce(0) { $0 + max(0, $1.points) }
        let dailyAvg = Double(familyTotal) / Double(max(windowDays, 1))
        let threshold = max(50.0, dailyAvg * 3)
        var byMemberDay: [String: (memberID: UUID, day: String, score: Int)] = [:]
        for r in records {
            let key = "\(r.memberID)|\(FamilyCalendar.dayKey(r.createdAt, timezoneID: tz))"
            byMemberDay[key, default: (r.memberID, key, 0)].score += r.points
        }
        for (_, v) in byMemberDay where Double(v.score) > threshold {
            anomalies.append(Anomaly(code: "A1", title: "单日得分突增",
                                     detail: "\(nameOf(v.memberID)) 在 \(v.day) 单日净得 \(v.score) 分（阈值 \(Int(threshold))）",
                                     memberID: v.memberID))
        }

        // A2 规则高频：同规则近 30 天 ≥ 25 次
        var ruleCounts: [UUID: Int] = [:]
        for r in records where r.ruleID != nil { ruleCounts[r.ruleID!, default: 0] += 1 }
        for (rid, count) in ruleCounts where count >= 25 {
            let ruleName = ruleName(rid, context: context)
            anomalies.append(Anomaly(code: "A2", title: "规则高频触发",
                                     detail: "「\(ruleName)」近 \(windowDays) 天触发 \(count) 次，建议下调每日上限",
                                     memberID: nil))
        }

        // A3 确认人单日确认 > 20（approve 上限之外的漏网统计）
        var approverDay: [String: (UUID, String, Int)] = [:]
        for r in records where r.approvedBy != nil {
            let key = "\(r.approvedBy!)|\(FamilyCalendar.dayKey(r.createdAt, timezoneID: tz))"
            approverDay[key, default: (r.approvedBy!, key, 0)].2 += 1
        }
        for (_, v) in approverDay where v.2 > family.settingsData.approverDailyLimit {
            anomalies.append(Anomaly(code: "A3", title: "确认人单日超限",
                                     detail: "\(nameOf(v.0)) 单日确认 \(v.2) 条",
                                     memberID: v.0))
        }

        // A4 凭证哈希重复（历史报告；实时拦截在 submit）
        var seen: [String: Int] = [:]
        for r in records where r.proofHash != nil { seen[r.proofHash!, default: 0] += 1 }
        for (hash, count) in seen where count >= 2 {
            anomalies.append(Anomaly(code: "A4", title: "凭证图片重复",
                                     detail: "同一张凭证被使用 \(count) 次（\(hash.prefix(8))…）",
                                     memberID: nil))
        }

        // A5 补录集中：单成员单日补录 > 5（backfilledAt 与 createdAt 不同日的记录）
        var backfillDay: [String: (UUID, Int)] = [:]
        for r in records where r.backfilledAt != nil {
            let key = "\(r.memberID)|\(FamilyCalendar.dayKey(r.backfilledAt!, timezoneID: tz))"
            backfillDay[key, default: (r.memberID, 0)].1 += 1
        }
        for (key, v) in backfillDay where v.1 > 5 {
            anomalies.append(Anomaly(code: "A5", title: "补录集中",
                                     detail: "\(nameOf(v.0)) 单日补录 \(v.1) 条（\(key.split(separator: "|").last ?? "")）",
                                     memberID: v.0))
        }

        // A6 减分集中：单成员近 30 天被减 ≥ 15 次（关系健康提示）
        var deductCounts: [UUID: Int] = [:]
        for r in records where r.points < 0 { deductCounts[r.memberID, default: 0] += 1 }
        for (mid, count) in deductCounts where count >= 15 {
            anomalies.append(Anomaly(code: "A6", title: "减分集中",
                                     detail: "\(nameOf(mid)) 近 \(windowDays) 天被减 \(count) 次，建议关注沟通方式",
                                     memberID: mid))
        }

        return anomalies
    }

    private static func ruleName(_ id: UUID, context: ModelContext) -> String {
        var d = FetchDescriptor<Rule>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d).first)?.name ?? "未知规则"
    }
}
