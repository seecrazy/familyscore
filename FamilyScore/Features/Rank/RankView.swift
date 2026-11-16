import SwiftUI
import SwiftData

/// 排行榜页（§8.2）：日/周/月/年/历史 + 领奖台 + 完整列表 + 分类冠军 + 进步榜
struct RankView: View {
    @EnvironmentObject var app: AppEnvironment
    @Environment(\.modelContext) private var context
    @Query private var allMembers: [Member]
    @Query private var allRecords: [ScoreRecord]

    @State private var period: RankPeriod = .day
    @State private var showProgressBoard = false

    private var family: Family? { app.currentFamily(in: context) }
    private var members: [Member] {
        guard let f = family else { return [] }
        return allMembers.filter { $0.familyID == f.id }
    }
    private var myID: UUID? { app.currentMemberID }

    private var entries: [RankEntry] {
        guard let f = family else { return [] }
        return RankService.leaderboard(family: f, members: members, period: period,
                                       context: context)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("周期", selection: $period) {
                        ForEach([RankPeriod.day, .week, .month, .year, .all], id: \.self) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if entries.isEmpty {
                        ContentUnavailableView("还没有记录", systemImage: "trophy",
                                               description: Text("打卡之后，这里就有排名啦"))
                            .padding(.top, 40)
                    } else {
                        podiumSection
                        listSection
                        championsSection
                        progressSection
                    }
                }
                .padding(.vertical)
            }
            .background(Theme.appBackground)
            .navigationTitle("排行榜")
            .sheet(isPresented: $showProgressBoard) {
                ProgressBoardSheet(members: members)
                    .presentationDetents([.medium])
            }
        }
    }

    // MARK: 领奖台

    private var podiumSection: some View {
        let byID = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
        let top3 = entries.prefix(3).compactMap { e -> (Member, RankEntry)? in
            guard let m = byID[e.memberID] else { return nil }
            return (m, e)
        }
        return Group {
            if !top3.isEmpty {
                VStack(spacing: 4) {
                    Text("🏆 \(period.label)贡献榜")
                        .font(.headline)
                    PodiumView(top3: top3)
                }
                .scoreCard()
                .padding(.horizontal)
            }
        }
    }

    // MARK: 完整列表（第 4 名起 + 垫底鼓励）

    private var listSection: some View {
        let byID = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
        let rest = entries.dropFirst(3)
        return Group {
            if !rest.isEmpty {
                VStack(spacing: 2) {
                    ForEach(Array(rest)) { e in
                        if let m = byID[e.memberID] {
                            RankRowView(member: m, entry: e, isMe: e.memberID == myID)
                        }
                    }
                    if let last = entries.last, entries.count >= 3,
                       let m = byID[last.memberID] {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                            Text("下周的进步之星，大概率是\(m.name)")
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                    }
                }
                .scoreCard()
                .padding(.horizontal)
            }
        }
    }

    // MARK: 分类冠军

    private var championsSection: some View {
        Group {
            if let f = family {
                let champions = RankService.categoryChampions(family: f, members: members, context: context)
                let byID = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
                VStack(alignment: .leading, spacing: 10) {
                    Text("本周分类冠军").font(.headline)
                    ForEach(champions) { c in
                        HStack {
                            Text(c.category.iconName + " " + c.category.label + "王")
                                .font(.subheadline)
                            Spacer()
                            if let mid = c.memberID, let m = byID[mid] {
                                Text("\(m.emoji) \(m.name)")
                                    .font(.subheadline.weight(.semibold))
                                Text("\(c.score) 分")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("虚位以待").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .scoreCard()
                .padding(.horizontal)
            }
        }
    }

    // MARK: 进步榜入口

    private var progressSection: some View {
        Button {
            Haptics.light()
            showProgressBoard = true
        } label: {
            Label("和上周的自己比一比（进步榜）", systemImage: "arrow.up.heart")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Theme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.radiusButton))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}

/// 进步榜半屏卡（§14.1：与自己比，无焦虑）
struct ProgressBoardSheet: View {
    let members: [Member]
    @EnvironmentObject var app: AppEnvironment
    @Environment(\.modelContext) private var context

    private var family: Family? { app.currentFamily(in: context) }

    var body: some View {
        NavigationStack {
            List {
                if let f = family {
                    let board = RankService.progressBoard(family: f, members: members, period: .week, context: context)
                    let byID = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
                    if board.isEmpty {
                        Text("这周是新开始，下周见分晓").foregroundStyle(.secondary)
                    }
                    ForEach(board) { e in
                        if let m = byID[e.memberID] {
                            HStack {
                                MemberAvatarView(member: m, size: 36)
                                Text(m.name)
                                Spacer()
                                if e.score >= 0 {
                                    Label("+\(e.score)", systemImage: "arrow.up")
                                        .foregroundStyle(Theme.addGreen)
                                        .font(.body.weight(.bold).monospacedDigit())
                                } else {
                                    Label("\(e.score)", systemImage: "arrow.down")
                                        .foregroundStyle(Theme.deductRed.opacity(0.8))
                                        .font(.body.weight(.semibold).monospacedDigit())
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("本周进步榜")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

extension RuleCategory {
    var iconName: String {
        switch self {
        case .chore: "🧹"
        case .study: "📚"
        case .health: "💪"
        case .emotion: "💛"
        case .special: "⭐"
        }
    }
}

extension RankPeriod {
    var label: String {
        switch self {
        case .day: "日"
        case .week: "周"
        case .month: "月"
        case .year: "年"
        case .all: "历史"
        }
    }
}
