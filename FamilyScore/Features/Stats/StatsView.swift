import SwiftUI
import Charts
import SwiftData

/// 统计页（§8.3）：概览卡、近 7 天趋势（Swift Charts）、四维雷达（自绘）、分类占比
struct StatsView: View {
    @EnvironmentObject var app: AppEnvironment
    @Environment(\.modelContext) private var context
    @Query private var allMembers: [Member]
    @Query private var allRecords: [ScoreRecord]
    @State private var radarScope: RadarScope = .month

    enum RadarScope: String, CaseIterable { case week = "周", month = "月", year = "年" }

    private var family: Family? { app.currentFamily(in: context) }
    private var me: Member? { app.currentMember(in: context) }

    private var stats: StatsSummary? {
        guard let f = family, let m = me else { return nil }
        let members = allMembers.filter { $0.familyID == f.id }
        let records = allRecords.filter { $0.familyID == f.id }
        return StatsSummary.compute(family: f, me: m, members: members, records: records)
    }

    /// 雷达数据按所选周期重新计算
    private var radarData: [RuleCategory: Int] {
        guard let f = family, let m = me else { return [:] }
        let tz = f.timezoneID
        let period: RankPeriod = radarScope == .week ? .week : radarScope == .month ? .month : .year
        let start = FamilyCalendar.periodStart(period, at: .now, timezoneID: tz)
        let mine = allRecords.filter {
            $0.familyID == f.id && $0.memberID == m.id && $0.createdAt >= start &&
            ($0.status == .approved || $0.status == .reversed || $0.status == .appealed)
        }
        var radar: [RuleCategory: Int] = [:]
        for r in mine { radar[r.category, default: 0] += max(0, r.points) }
        return radar
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let s = stats {
                    VStack(spacing: 16) {
                        overviewCards(s)
                        trendCard(s)
                        radarCard
                        categoryCard
                        totalCard(s)
                    }
                    .padding(.horizontal)
                    .padding(.vertical)
                }
            }
            .background(Theme.appBackground)
            .navigationTitle("我的统计")
        }
    }

    private func overviewCards(_ s: StatsSummary) -> some View {
        HStack(spacing: 12) {
            statCard(title: "本周积分", value: "\(s.weekScore)", color: Theme.primary)
            statCard(title: "本月排名", value: "#\(s.monthRank)", color: Theme.rankBlue,
                     sub: "共 \(s.totalActive) 人")
        }
    }

    private func statCard(title: String, value: String, color: Color, sub: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
            if let sub { Text(sub).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .scoreCard()
    }

    private func trendCard(_ s: StatsSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("近 7 天趋势").font(.headline)
            Chart {
                ForEach(Array(s.trend.enumerated()), id: \.offset) { i, item in
                    AreaMark(
                        x: .value("日", item.0),
                        y: .value("分", item.1),
                        stacking: .unstacked
                    )
                    .foregroundStyle(Theme.primary.opacity(0.12).gradient)

                    LineMark(
                        x: .value("日", item.0),
                        y: .value("分", item.1)
                    )
                    .foregroundStyle(Theme.primary)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("日", item.0),
                        y: .value("分", item.1)
                    )
                    .foregroundStyle(Theme.primary)
                    .annotation(position: .top) {
                        if item.1 > 0 {
                            Text("\(item.1)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartYScale(domain: .automatic(includesZero: true))
            .frame(height: 180)
            .accessibilityLabel("近 7 天积分趋势折线图，从\(s.trend.first?.0 ?? "")到\(s.trend.last?.0 ?? "")")
        }
        .padding(16)
        .scoreCard()
    }

    private var radarCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("能力雷达").font(.headline)
                Spacer()
                Picker("范围", selection: $radarScope) {
                    ForEach(RadarScope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            RadarChart(data: radarData)
                .frame(height: 210)
                .accessibilityLabel(radarAccessibility)
        }
        .padding(16)
        .scoreCard()
    }

    private var radarAccessibility: String {
        RuleCategory.allCases.filter { $0 != .special }.map {
            "\($0.label) \(radarData[$0] ?? 0) 分"
        }.joined(separator: "，")
    }

    private var categoryCard: some View {
        let total = RuleCategory.allCases.filter { $0 != .special }
            .reduce(0) { $0 + max(0, radarData[$1] ?? 0) }
        return VStack(alignment: .leading, spacing: 12) {
            Text("分类占比（\(radarScope.rawValue)）").font(.headline)
            if total == 0 {
                Text("这\(radarScope.rawValue)还没有记录，去打个卡吧")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(RuleCategory.allCases.filter { $0 != .special }, id: \.self) { cat in
                    let v = max(0, radarData[cat] ?? 0)
                    HStack(spacing: 10) {
                        Text("\(cat.iconName) \(cat.label)")
                            .font(.caption)
                            .frame(width: 64, alignment: .leading)
                        GeometryReader { geo in
                            Capsule().fill(Theme.primary.opacity(0.25))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(cat.color)
                                        .frame(width: geo.size.width * CGFloat(v) / CGFloat(max(total, 1)))
                                }
                        }
                        .frame(height: 10)
                        Text("\(v * 100 / max(total, 1))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
        .padding(16)
        .scoreCard()
    }

    private func totalCard(_ s: StatsSummary) -> some View {
        Group {
            if let m = me {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("累计 \(m.cumulativeScore) 分 · Lv.\(m.level) \(LevelEngine.title(forLevel: m.level))")
                            .font(.subheadline.weight(.semibold))
                        if let next = LevelEngine.pointsToNext(score: m.cumulativeScore) {
                            Text("再攒 \(next) 分升级").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("已是满级传家宝 ✨").font(.caption).foregroundStyle(Theme.gold)
                        }
                    }
                    Spacer()
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.title2)
                        .foregroundStyle(Theme.primary)
                }
                .padding(16)
                .scoreCard()
            }
        }
    }
}

/// 四维雷达图（自绘 Shape，§10 RadarChart）
struct RadarChart: View {
    let data: [RuleCategory: Int]
    private let axes: [RuleCategory] = [.chore, .study, .health, .emotion]

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2 - 28
            let maxValue = max(10, data.values.max() ?? 0)

            ZStack {
                // 网格（3 层）
                ForEach([0.33, 0.66, 1.0], id: \.self) { scale in
                    RadarPolygon(values: axes.map { _ in CGFloat(scale) }, smooth: false)
                        .stroke(Color(hex: 0xE5E5EA), lineWidth: 1)
                        .frame(width: radius * 2, height: radius * 2)
                        .position(center)
                }
                // 轴与标签
                ForEach(Array(axes.enumerated()), id: \.offset) { i, axis in
                    let angle = -CGFloat.pi / 2 + CGFloat(i) * 2 * .pi / CGFloat(axes.count)
                    RadarAxisLine(angle: angle)
                        .stroke(Color(hex: 0xE5E5EA), lineWidth: 1)
                        .frame(width: radius * 2, height: radius * 2)
                        .position(center)
                    Text(axis.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .position(x: center.x + (radius + 20) * cos(angle),
                                  y: center.y + (radius + 20) * sin(angle))
                }
                // 数据面
                RadarPolygon(values: axes.map { CGFloat(min(1, Double(data[$0] ?? 0) / Double(maxValue))) },
                             smooth: false)
                    .fill(Theme.primary.opacity(0.28))
                    .overlay(
                        RadarPolygon(values: axes.map { CGFloat(min(1, Double(data[$0] ?? 0) / Double(maxValue))) },
                                     smooth: false)
                            .stroke(Theme.primary, lineWidth: 2))
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)
                    .animation(.spring(response: 0.5), value: data)
            }
        }
    }
}

/// 雷达多边形：values 为 0~1 归一化数组
struct RadarPolygon: Shape {
    let values: [CGFloat]
    var smooth: Bool = false

    func path(in rect: CGRect) -> Path {
        guard values.count >= 3 else { return Path() }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for (i, v) in values.enumerated() {
            let angle = -CGFloat.pi / 2 + CGFloat(i) * 2 * .pi / CGFloat(values.count)
            let p = CGPoint(x: center.x + radius * v * cos(angle),
                            y: center.y + radius * v * sin(angle))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

struct RadarAxisLine: Shape {
    let angle: CGFloat
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x + radius * cos(angle),
                                 y: center.y + radius * sin(angle)))
        return path
    }
}

extension RuleCategory {
    var color: Color {
        switch self {
        case .chore: Theme.primary
        case .study: Theme.rankBlue
        case .health: Theme.addGreen
        case .emotion: Theme.deductRed.opacity(0.85)
        case .special: Theme.gold
        }
    }
}
