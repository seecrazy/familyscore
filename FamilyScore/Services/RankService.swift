import Foundation
import SwiftData

struct RankEntry: Identifiable, Equatable {
    let id = UUID()
    let memberID: UUID
    var score: Int
    var rank: Int
    /// 与上一周期名次差：正数=下降位数，负数=上升位数，nil=上期未上榜
    var delta: Int?
}

struct CategoryChampion: Equatable, Identifiable {
    let id = UUID()
    let category: RuleCategory
    let memberID: UUID?
    let score: Int
}

enum RankService {

    /// 生效记录（approved/reversed/appealed；reversed 由反向记录天然抵消，§5.2）
    static func effectiveRecords(familyID: UUID, since: Date?, context: ModelContext) -> [ScoreRecord] {
        var predicate: Predicate<ScoreRecord>?
        if let since {
            predicate = #Predicate { $0.familyID == familyID && $0.createdAt >= since }
        } else {
            predicate = #Predicate { $0.familyID == familyID }
        }
        let desc = FetchDescriptor<ScoreRecord>(predicate: predicate,
                                                sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        return (try? context.fetch(desc))?.filter {
            $0.status == .approved || $0.status == .reversed || $0.status == .appealed
        } ?? []
    }

    /// 某周期排行（含环比 delta），排除已退出成员
    static func leaderboard(family: Family, members: [Member], period: RankPeriod,
                            at date: Date = .now, context: ModelContext) -> [RankEntry] {
        let tz = family.timezoneID
        let activeMembers = members.filter { $0.status == .active }
        let start = FamilyCalendar.periodStart(period, at: date, timezoneID: tz)
        let records = effectiveRecords(familyID: family.id, since: start == .distantPast ? nil : start,
                                       context: context)
            .filter { $0.createdAt >= start }

        let activeIDs = Set(activeMembers.map(\.id))
        var scores: [UUID: Int] = [:]
        for m in activeMembers { scores[m.id] = 0 }
        for r in records where activeIDs.contains(r.memberID) { scores[r.memberID, default: 0] += r.points }

        // 上一周期名次
        let prevStart = FamilyCalendar.previousPeriodStart(period, at: date, timezoneID: tz)
        let prevRecords = effectiveRecords(familyID: family.id, since: prevStart, context: context)
            .filter { $0.createdAt >= prevStart && $0.createdAt < start }
        var prevScores: [UUID: Int] = [:]
        for m in activeMembers { prevScores[m.id] = 0 }
        for r in prevRecords { prevScores[r.memberID, default: 0] += r.points }
        let prevRanks = rankMap(of: activeMembers.map(\.id), scores: prevScores)

        return ranked(activeMembers: activeMembers.map(\.id), scores: scores, prevRanks: prevRanks)
    }

    /// 进步榜（§14.1）：本期 − 上期，仅两期都有记录的成员参与
    static func progressBoard(family: Family, members: [Member], period: RankPeriod,
                              at date: Date = .now, context: ModelContext) -> [RankEntry] {
        let tz = family.timezoneID
        let start = FamilyCalendar.periodStart(period, at: date, timezoneID: tz)
        let prevStart = FamilyCalendar.previousPeriodStart(period, at: date, timezoneID: tz)
        let all = effectiveRecords(familyID: family.id, since: prevStart, context: context)

        let activeSet = Set(members.filter { $0.status == .active }.map(\.id))
        func score(_ from: Date, _ to: Date) -> [UUID: Int] {
            var s: [UUID: Int] = [:]
            for r in all where r.createdAt >= from && r.createdAt < to && activeSet.contains(r.memberID) {
                s[r.memberID, default: 0] += r.points
            }
            return s
        }
        let current = score(start, date.addingTimeInterval(1))
        let previous = score(prevStart, start)

        let activeIDs = members.filter { $0.status == .active }.map(\.id)
        var entries: [RankEntry] = []
        for id in activeIDs {
            guard let prev = previous[id] else { continue } // 上期无数据 → 新人保护，不入榜
            let cur = current[id] ?? 0
            let gain = cur - prev
            entries.append(RankEntry(memberID: id, score: gain, rank: 0, delta: nil))
        }
        entries.sort { $0.score > $1.score }
        for i in entries.indices { entries[i].rank = i + 1 }
        return entries
    }

    /// 分类冠军（§8.2）
    static func categoryChampions(family: Family, members: [Member], at date: Date = .now,
                                  context: ModelContext) -> [CategoryChampion] {
        let start = FamilyCalendar.periodStart(.week, at: date, timezoneID: family.timezoneID)
        let records = effectiveRecords(familyID: family.id, since: start, context: context)
            .filter { $0.createdAt >= start }
        let activeIDs = Set(members.filter { $0.status == .active }.map(\.id))

        return RuleCategory.allCases.filter { $0 != .special }.map { cat in
            var scores: [UUID: Int] = [:]
            for r in records where r.category == cat && activeIDs.contains(r.memberID) {
                scores[r.memberID, default: 0] += r.points
            }
            let best = scores.max { $0.value < $1.value }
            return CategoryChampion(category: cat, memberID: best?.key, score: best?.value ?? 0)
        }
    }

    /// 家庭某周期总分（团队目标/首页总卡）
    static func familyScore(family: Family, period: RankPeriod, at date: Date = .now,
                            context: ModelContext) -> Int {
        let start = FamilyCalendar.periodStart(period, at: date, timezoneID: family.timezoneID)
        return effectiveRecords(familyID: family.id, since: start == .distantPast ? nil : start,
                                context: context).filter { $0.createdAt >= start }
            .reduce(0) { $0 + $1.points }
    }

    // MARK: 排名（并列同名次：1,2,2,4）

    private static func rankMap(of memberIDs: [UUID], scores: [UUID: Int]) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        let sorted = memberIDs.sorted { a, b in
            let sa = scores[a] ?? 0, sb = scores[b] ?? 0
            return sa == sb ? a.uuidString < b.uuidString : sa > sb
        }
        var lastScore: Int? = nil, lastRank = 0
        for (i, id) in sorted.enumerated() {
            let s = scores[id] ?? 0
            let rank = (s == lastScore) ? lastRank : i + 1
            result[id] = rank
            lastScore = s; lastRank = rank
        }
        return result
    }

    private static func ranked(activeMembers: [UUID], scores: [UUID: Int],
                               prevRanks: [UUID: Int]) -> [RankEntry] {
        let sorted = scores.keys.sorted { a, b in
            let sa = scores[a] ?? 0, sb = scores[b] ?? 0
            return sa == sb ? a.uuidString < b.uuidString : sa > sb
        }
        var entries: [RankEntry] = []
        var lastScore: Int? = nil, lastRank = 0
        for (i, id) in sorted.enumerated() {
            let s = scores[id] ?? 0
            let rank = (s == lastScore) ? lastRank : i + 1
            let delta = prevRanks[id].map { rank - $0 } // 负=上升
            entries.append(RankEntry(memberID: id, score: s, rank: rank, delta: delta))
            lastScore = s; lastRank = rank
        }
        return entries
    }
}
