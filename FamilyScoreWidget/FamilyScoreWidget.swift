import WidgetKit
import SwiftUI

/// 家分宝小组件（§14.2 锁屏一键打卡 / §8.1 家庭总分）
/// 桌面中件：家庭今日总分 + 周目标进度 + 我的分；锁屏圆形：一键打卡第一个候选规则
@main
struct FamilyWidgetBundle: WidgetBundle {
    var body: some Widget {
        FamilyWidget()
        QuickCheckInWidget()
    }
}

// MARK: - Timeline

struct SummaryEntry: TimelineEntry {
    let date: Date
    let summary: WidgetBridge.Summary
}

struct SummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry {
        SummaryEntry(date: .now, summary: demoSummary)
    }
    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
        completion(SummaryEntry(date: .now, summary: WidgetBridge.readSummary()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        let entry = SummaryEntry(date: .now, summary: WidgetBridge.readSummary())
        // 30 分钟刷新一次；真实更新由 App 侧变更时 WidgetCenter.reload 主动触发
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private var demoSummary: WidgetBridge.Summary {
        var s = WidgetBridge.Summary()
        s.familyName = "我的家"
        s.myName = "我"
        s.familyTodayScore = 128
        s.weeklyScore = 386
        s.weeklyGoal = 500
        s.myTodayScore = 45
        s.quickRules = [.init(ruleID: UUID(), name: "洗碗", icon: "fork.knife", points: 5)]
        return s
    }
}

// MARK: - 桌面中件（家庭卡）

struct FamilyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FamilyScoreHome", provider: SummaryProvider()) { entry in
            FamilyWidgetView(entry: entry)
        }
        .configurationDisplayName("家庭积分卡")
        .description("今日总分、周目标进度与我的得分")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct FamilyWidgetView: View {
    let entry: SummaryEntry
    private var s: WidgetBridge.Summary { entry.summary }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                LinearGradient(colors: [Color(red: 1.00, green: 0.54, blue: 0.24),
                                        Color(red: 1.00, green: 0.70, blue: 0.28)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .widgetURL(URL(string: "familyscore://home"))
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("🏠 \(s.familyName)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                if s.streakDays >= 3 {
                    Label("\(s.streakDays)", systemImage: "flame.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            (Text("今日 ").font(.caption).foregroundStyle(.white.opacity(0.85))
             + Text("\(s.familyTodayScore)").font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
             + Text(" 分").font(.caption2).foregroundStyle(.white.opacity(0.85)))
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.25))
                        Capsule().fill(.white)
                            .frame(width: geo.size.width * goalProgress)
                    }
                }
                .frame(height: 6)
                Text("本周 \(s.weeklyScore)/\(s.weeklyGoal)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.9))
            }
            HStack {
                Text("\(s.myEmoji) \(s.myName) +\(s.myTodayScore)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                if s.openTodoCount > 0 {
                    Text("待办 \(s.openTodoCount)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .padding(2)
    }

    private var goalProgress: CGFloat {
        min(1, CGFloat(s.weeklyScore) / CGFloat(max(s.weeklyGoal, 1)))
    }
}

// MARK: - 锁屏/桌面一键打卡（iOS 17 interactive widget）

struct QuickCheckInIntent: AppIntent {
    static var title: LocalizedStringResource = "快速打卡"
    static var description = IntentDescription("记录一次行为，打开 App 后按规则结算")

    @Parameter(title: "规则 ID")
    var ruleID: String
    @Parameter(title: "规则名")
    var ruleName: String
    @Parameter(title: "图标")
    var icon: String
    @Parameter(title: "分值")
    var points: Int
    @Parameter(title: "成员 ID")
    var memberID: String
    @Parameter(title: "成员名")
    var memberName: String

    init() {}

    init(rule: WidgetBridge.QuickRule, summary: WidgetBridge.Summary) {
        self.ruleID = rule.ruleID.uuidString
        self.ruleName = rule.name
        self.icon = rule.icon
        self.points = rule.points
        self.memberID = summary.memberUUID ?? ""
        self.memberName = summary.myName
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let rule = WidgetBridge.QuickRule(ruleID: UUID(uuidString: ruleID) ?? UUID(),
                                          name: ruleName, icon: icon, points: points)
        WidgetBridge.optimisticApply(rule: rule, memberName: memberName,
                                     memberID: UUID(uuidString: memberID) ?? UUID())
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "已记下「\(ruleName)」+\(points)，打开家分宝结算 💛")
    }
}

extension WidgetBridge.Summary {
    var memberUUID: UUID? {
        // 摘要不带 memberID（隐私最小化）——由 quickRules 携带的请求在 App 端以当前成员结算。
        // 此处占位：App 写摘要时把当前成员放进 memberName 对应缓存 key
        WidgetBridge.cachedMemberID
    }
}

struct QuickCheckInWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FamilyScoreQuickCheckIn", provider: SummaryProvider()) { entry in
            QuickCheckInWidgetView(entry: entry)
        }
        .configurationDisplayName("一键打卡")
        .description("锁屏/桌面直接记录行为，打开 App 完成评审结算")
        .supportedFamilies([.accessoryCircular, .systemSmall])
    }
}

struct QuickCheckInWidgetView: View {
    let entry: SummaryEntry
    @Environment(\.widgetFamily) private var family
    private var s: WidgetBridge.Summary { entry.summary }

    var body: some View {
        if family == .accessoryCircular {
            accessory
        } else {
            small
        }
    }

    /// 锁屏圆形：一键打卡第一个候选
    @ViewBuilder
    private var accessory: some View {
        if let first = s.quickRules.first {
            Button(intent: QuickCheckInIntent(rule: first, summary: s)) {
                VStack(spacing: 0) {
                    Image(systemName: first.icon)
                        .font(.headline)
                    Text("+\(first.points)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                }
            }
            .containerBackground(for: .widget) { Color.clear }
        } else {
            VStack(spacing: 0) {
                Image(systemName: "plus.circle")
                Text("打卡").font(.caption2)
            }
            .widgetURL(URL(string: "familyscore://home"))
            .containerBackground(for: .widget) { Color.clear }
        }
    }

    /// 桌面小件：三个候选 + 我的今日分
    private var small: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("\(s.myEmoji) +\(s.myTodayScore)")
                    .font(.headline.monospacedDigit())
                Spacer()
                Text("Lv.\(s.level) \(s.levelTitle)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(s.quickRules.prefix(3), id: \.ruleID) { rule in
                Button(intent: QuickCheckInIntent(rule: rule, summary: s)) {
                    HStack(spacing: 6) {
                        Image(systemName: rule.icon)
                            .font(.caption)
                            .frame(width: 18)
                        Text(rule.name).font(.caption.weight(.medium)).lineLimit(1)
                        Spacer()
                        Text("+\(rule.points)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.48))
                    }
                }
                .buttonStyle(.plain)
            }
            if s.quickRules.isEmpty {
                Text("打开 App 配置规则后可快捷打卡")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }
}
