import Foundation

/// 通知设置（§18.4：总开关 + 分类开关 + 免打扰时段，默认 22:00–07:00）
struct NotificationSettings: Codable, Equatable {
    var master = true
    var todo = true
    var birthday = true
    var approval = true
    var expiry = true
    var weekly = true
    var streakProtect = true
    var goalReached = true
    /// 免打扰起止（一天内分钟数；起始 1320=22:00，结束 420=07:00，允许跨午夜）
    var quietStartMinutes = 22 * 60
    var quietEndMinutes = 7 * 60

    static let storageKey = "fs.notification.settings"

    static func load(defaults: UserDefaults = .standard) -> NotificationSettings {
        guard let data = defaults.data(forKey: storageKey),
              let s = try? JSONDecoder().decode(NotificationSettings.self, from: data) else {
            return NotificationSettings()
        }
        return s
    }

    func save(defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

/// 通知规划输入（App 层从数据库组装，Planner 保持纯函数）
struct NotificationContext {
    var timezoneID: String = TimeZone.current.identifier
    // 待办
    var openTodoCount: Int = 0
    var todoExampleTitle: String?
    // 生日：[(name, isToday, daysLeft)]
    var birthdays: [(name: String, isToday: Bool, daysLeft: Int)] = []
    // 审批
    var pendingApprovalCount: Int = 0
    // 积分到期：[(memberName, expiringAmount, daysLeft)]
    var expiringLots: [(memberName: String, amount: Int, daysLeft: Int)] = []
    // 周结算
    var weeklyChampionName: String?
    var weeklyFamilyScore: Int = 0
    // 打卡保护
    var protectMemberName: String?
    var protectStreakDays: Int = 0
}

/// 纯函数规划器：输入设置+上下文+当前时间 → 输出应排程的全部本地通知（可测）
enum NotificationPlanner {

    struct Planned: Equatable {
        let id: String          // "fs-<类别>[-<key>]"
        let title: String
        let body: String
        let fireDate: Date
    }

    static func plans(settings: NotificationSettings, ctx: NotificationContext,
                      now: Date = .now) -> [Planned] {
        guard settings.master else { return [] }
        var result: [Planned] = []
        let cal = FamilyCalendar.calendar(timezoneID: ctx.timezoneID)

        func dateToday(_ hour: Int, _ minute: Int, after now: Date) -> Date? {
            var comps = cal.dateComponents([.year, .month, .day], from: now)
            comps.hour = hour; comps.minute = minute
            return cal.date(from: comps)
        }

        // 1. 每日待办 19:00（§18.4）
        if settings.todo, ctx.openTodoCount > 0 {
            if let fire = dateToday(19, 0, after: now), fire > now {
                result.append(Planned(
                    id: "fs-todo",
                    title: "今日待办还剩 \(ctx.openTodoCount) 件",
                    body: ctx.todoExampleTitle.map { "比如「\($0)」——睡前一起清个零吧 💛" } ?? "每一分，都是爱",
                    fireDate: quietAdjusted(fire, settings: settings, timezoneID: ctx.timezoneID)))
            }
        }

        // 2. 生日：当天与前一天 09:00（§18.4）
        if settings.birthday {
            for (i, bd) in ctx.birthdays.enumerated() {
                guard bd.daysLeft <= 1 else { continue }
                let fireDay = Calendar.current.date(byAdding: .day, value: bd.daysLeft, to: now) ?? now
                if var fire = dateToday(9, 0, after: fireDay) {
                    if bd.daysLeft == 0 && fire <= now { continue }
                    fire = quietAdjusted(fire, settings: settings, timezoneID: ctx.timezoneID)
                    result.append(Planned(
                        id: "fs-birthday-\(i)",
                        title: bd.isToday ? "🎂 今天是\(bd.name)的生日" : "明天是\(bd.name)的生日",
                        body: bd.isToday ? "记得给\(bd.name)一个大大的拥抱 ✨" : "提前准备起来，给\(bd.name)一个惊喜 🎁",
                        fireDate: fire))
                }
            }
        }

        // 3. 审批提醒：有 pending → 2 小时后聚合推一次（家长侧，§18.4）
        if settings.approval, ctx.pendingApprovalCount > 0 {
            result.append(Planned(
                id: "fs-approval",
                title: "有 \(ctx.pendingApprovalCount) 条打卡等你评审",
                body: "打开家分宝，通过后积分才到账哦",
                fireDate: quietAdjusted(now.addingTimeInterval(2 * 3600),
                                        settings: settings, timezoneID: ctx.timezoneID)))
        }

        // 4. 积分到期：30/7/1 天三档 10:00（§6.2/§18.4）
        if settings.expiry {
            for lot in ctx.expiringLots {
                guard lot.daysLeft <= 30, lot.amount > 0 else { continue }
                let fireDay = Calendar.current.date(byAdding: .day, value: lot.daysLeft, to: now) ?? now
                if let fire = dateToday(10, 0, after: fireDay), fire > now {
                    let urgency = lot.daysLeft <= 1 ? "明天就到期" : lot.daysLeft <= 7 ? "一周内到期" : "一个月内到期"
                    result.append(Planned(
                        id: "fs-expiry-\(lot.memberName)-\(lot.daysLeft)",
                        title: "\(lot.memberName) 有 \(lot.amount) 分\(urgency)",
                        body: "满一年会打五折入永久池，先去商城花掉更划算 🎁",
                        fireDate: quietAdjusted(fire, settings: settings, timezoneID: ctx.timezoneID)))
                }
            }
        }

        // 5. 周结算：本周五 20:00（§18.4 日榜不推防焦虑）；本周五已过则下周五
        if settings.weekly, let champion = ctx.weeklyChampionName {
            var friday = nextWeekday(6, of: now, cal: cal)  // 6=周五（1=周日），含今天
            var fire = dateToday(20, 0, after: friday)
            if fire == nil || fire! <= now {
                friday = cal.date(byAdding: .day, value: 7, to: friday) ?? friday
                fire = dateToday(20, 0, after: friday)
            }
            if let fire, fire > now {
                result.append(Planned(
                    id: "fs-weekly",
                    title: "本周 MVP 是\(champion)！",
                    body: "全家这周共得 \(ctx.weeklyFamilyScore) 分，看看排行榜的变化吧 🏆",
                    fireDate: quietAdjusted(fire, settings: settings, timezoneID: ctx.timezoneID)))
            }
        }

        // 6. 打卡保护：今晚 21:00（streak ≥ 3 且今日未打卡，§18.4）
        if settings.streakProtect, let name = ctx.protectMemberName, ctx.protectStreakDays >= 3 {
            if let fire = dateToday(21, 0, after: now), fire > now {
                result.append(Planned(
                    id: "fs-streak",
                    title: "\(name)的连续打卡还差今天",
                    body: "已连续 \(ctx.protectStreakDays) 天，今天随便打个卡就能续上 🔥",
                    fireDate: quietAdjusted(fire, settings: settings, timezoneID: ctx.timezoneID)))
            }
        }

        // 7. 目标达成：即时（App 内检测到时发送，规划器给出 30 秒后触发）
        if settings.goalReached, ctx.weeklyFamilyScore > 0 {
            // goalReached 用即时发放在运行时（NotificationService.celebrateGoal），不排程
        }

        return result
    }

    /// 免打扰顺延：落在免打扰窗口 → 顺延到窗口结束（支持跨午夜，如 22:00–07:00）
    static func quietAdjusted(_ date: Date, settings: NotificationSettings, timezoneID: String) -> Date {
        guard settings.master else { return date }
        let cal = FamilyCalendar.calendar(timezoneID: timezoneID)
        let comps = cal.dateComponents([.hour, .minute], from: date)
        let minutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let start = settings.quietStartMinutes
        let end = settings.quietEndMinutes

        let inQuiet: Bool
        if start <= end {                       // 不跨午夜，如 13:00–15:00
            inQuiet = minutes >= start && minutes < end
        } else {                                // 跨午夜，如 22:00–07:00
            inQuiet = minutes >= start || minutes < end
        }
        guard inQuiet else { return date }

        // 顺延到免打扰结束时刻（当天 end < start 时 end 在次日）
        var target = cal.dateComponents([.year, .month, .day], from: date)
        target.hour = end / 60; target.minute = end % 60
        if var adjusted = cal.date(from: target) {
            if adjusted <= date {
                adjusted = cal.date(byAdding: .day, value: 1, to: adjusted) ?? adjusted
            }
            return adjusted
        }
        return date
    }

    /// 下一个指定星期几（1=周日 … 7=周六）的当天零点；**含今天**——时刻是否已过由调用方判断
    static func nextWeekday(_ weekday: Int, of date: Date, cal: Calendar) -> Date {
        let current = cal.component(.weekday, from: date)
        let delta = (weekday - current + 7) % 7
        return cal.date(byAdding: .day, value: delta, to: cal.startOfDay(for: date)) ?? date
    }
}
