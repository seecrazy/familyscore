import Foundation

/// 家庭时区日历工具：日/周/月/年边界与 key 生成（DESIGN.md §5.3）
enum FamilyCalendar {
    static func calendar(timezoneID: String) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timezoneID) ?? .current
        cal.firstWeekday = 2 // 周一开始
        return cal
    }

    static func dayKey(_ date: Date, timezoneID: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: timezoneID) ?? .current
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: date)
    }

    static func monthKey(_ date: Date, timezoneID: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        fmt.timeZone = TimeZone(identifier: timezoneID) ?? .current
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: date)
    }

    static func startOfDay(_ date: Date, timezoneID: String) -> Date {
        calendar(timezoneID: timezoneID).startOfDay(for: date)
    }

    static func startOfWeek(_ date: Date, timezoneID: String) -> Date {
        let cal = calendar(timezoneID: timezoneID)
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    static func startOfMonth(_ date: Date, timezoneID: String) -> Date {
        let cal = calendar(timezoneID: timezoneID)
        let comps = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: comps) ?? date
    }

    static func startOfYear(_ date: Date, timezoneID: String) -> Date {
        let cal = calendar(timezoneID: timezoneID)
        var comps = cal.dateComponents([.year], from: date)
        comps.month = 1; comps.day = 1
        return cal.date(from: comps) ?? date
    }

    /// 周期起点（§5.3 排行榜查询策略）
    static func periodStart(_ period: RankPeriod, at date: Date, timezoneID: String) -> Date {
        switch period {
        case .day: startOfDay(date, timezoneID: timezoneID)
        case .week: startOfWeek(date, timezoneID: timezoneID)
        case .month: startOfMonth(date, timezoneID: timezoneID)
        case .year: startOfYear(date, timezoneID: timezoneID)
        case .all: .distantPast
        }
    }

    /// 上一周期起点（进步榜/环比用）
    static func previousPeriodStart(_ period: RankPeriod, at date: Date, timezoneID: String) -> Date {
        let cal = calendar(timezoneID: timezoneID)
        let start = periodStart(period, at: date, timezoneID: timezoneID)
        switch period {
        case .day: return cal.date(byAdding: .day, value: -1, to: start) ?? start
        case .week: return cal.date(byAdding: .weekOfYear, value: -1, to: start) ?? start
        case .month: return cal.date(byAdding: .month, value: -1, to: start) ?? start
        case .year: return cal.date(byAdding: .year, value: -1, to: start) ?? start
        case .all: return .distantPast
        }
    }

    /// monthKey 对应的起始日期（批次过期判断用）
    static func date(ofMonthKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        var comps = DateComponents()
        comps.year = parts[0]; comps.month = parts[1]; comps.day = 1
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: comps)
    }
}
