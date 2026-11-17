import Foundation
import SwiftData
import WidgetKit

/// App 侧 Widget 桥：摘要写入 + 一键打卡队列消费（引擎结算，§14.2）
enum WidgetSyncService {

    /// 组装并写入 Widget 摘要（App Group），随后刷新小组件时间线
    static func refresh(family: Family?, me: Member?, context: ModelContext) {
        guard let family, let me else { return }
        var s = WidgetBridge.Summary()
        s.familyName = family.name
        s.myName = me.name
        s.myEmoji = me.emoji
        s.weeklyGoal = family.settingsData.weeklyGoal
        s.level = me.level
        s.levelTitle = LevelEngine.title(forLevel: me.level)
        s.pointsToNext = LevelEngine.pointsToNext(score: me.cumulativeScore)
        s.streakDays = me.streakDays
        WidgetBridge.cachedMemberID = me.id

        let members = FamilyService.members(of: family, context: context)
        let records = RankService.effectiveRecords(familyID: family.id, since: nil, context: context)
        let tz = family.timezoneID

        // 今日
        let todayStart = FamilyCalendar.startOfDay(.now, timezoneID: tz)
        let today = records.filter { $0.createdAt >= todayStart }
        s.familyTodayScore = today.reduce(0) { $0 + $1.points }
        s.myTodayScore = today.filter { $0.memberID == me.id }.reduce(0) { $0 + $1.points }

        // 周
        let weekStart = FamilyCalendar.periodStart(.week, at: .now, timezoneID: tz)
        s.weeklyScore = records.filter { $0.createdAt >= weekStart }.reduce(0) { $0 + $1.points }

        // 待办
        let todayKey = FamilyCalendar.dayKey(.now, timezoneID: tz)
        let fid = family.id
        let assignments = ((try? context.fetch(FetchDescriptor<TaskAssignment>(
            predicate: #Predicate { $0.familyID == fid && $0.dueDay == todayKey }))) ?? [])
        s.openTodoCount = assignments.filter { $0.status == .open }.count

        // 待评审（家长视角）
        let pending = ((try? context.fetch(FetchDescriptor<ScoreRecord>(
            predicate: #Predicate { $0.familyID == fid }))) ?? [])
        s.pendingApprovals = pending.filter { $0.status == .pending }.count

        // 快捷打卡候选：正向规则前 3（按当前成员系数算预览分）
        let rules = FamilyService.activeRules(of: family, context: context).filter { !$0.isDeduction }
        s.quickRules = rules.prefix(3).map {
            WidgetBridge.QuickRule(ruleID: $0.id, name: $0.name, icon: $0.icon,
                                   points: ScoreEngine.computedPoints(base: $0.points,
                                                                      coefficient: me.coefficient,
                                                                      multiplier: family.settingsData.doublePointsMultiplier))
        }

        WidgetBridge.writeSummary(s)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 消费锁屏一键打卡队列：以当前成员身份走引擎（评审规则照常产生 pending）
    static func consumeQueue(me: Member, family: Family, context: ModelContext) {
        let queue = WidgetBridge.readQueue()
        guard !queue.isEmpty else { return }
        var refreshed = false
        WidgetBridge.drainQueue { req in
            let rid = req.ruleID
            guard let rule = (try? context.fetch(FetchDescriptor<Rule>(
                predicate: #Predicate { $0.id == rid })))?.first, rule.isActive else { return }
            _ = try? ScoreEngine.submit(
                member: me, family: family, rule: rule,
                note: "锁屏一键打卡", at: req.createdAt,
                actorIsAdmin: me.role == .admin,
                approver: me.role == .admin ? me.id : nil,
                context: context)
            refreshed = true
        }
        if refreshed {
            refresh(family: family, me: me, context: context)
        }
    }
}