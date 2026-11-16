import SwiftUI
import SwiftData

/// 首页（§8.1）
struct HomeView: View {
    @EnvironmentObject var app: AppEnvironment
    @Environment(\.modelContext) private var context
    @Query private var allMembers: [Member]
    @Query private var allRules: [Rule]
    @Query private var allRecords: [ScoreRecord]
    @Query private var allAssignments: [TaskAssignment]

    @State private var sheetRule: Rule?
    @State private var toast: String?

    private var family: Family? { app.currentFamily(in: context) }
    private var me: Member? { app.currentMember(in: context) }

    private var summary: HomeSummary? {
        guard let f = family, let m = me else { return nil }
        return HomeSummary.compute(
            family: f, me: m,
            members: allMembers.filter { $0.familyID == f.id },
            rules: allRules.filter { $0.familyID == f.id && $0.isActive },
            records: allRecords.filter { $0.familyID == f.id },
            assignments: allAssignments.filter { $0.familyID == f.id },
            context: context)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let s = summary, let me, let family {
                    VStack(spacing: 18) {
                        if let t = toast { toastView(t) }
                        header(family: family)
                        ScoreCardView(summary: s, me: me)
                        if me.role == .admin, !s.pendingRecords.isEmpty {
                            approvalsSection(s)
                        }
                        quickSection(s, family: family)
                        todoSection(s)
                        feedSection(s)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                } else {
                    ContentUnavailableView("还没有家庭", systemImage: "house",
                                           description: Text("重新进入引导创建家庭"))
                }
            }
            .background(Theme.appBackground)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { switchButton } }
            .sheet(item: $sheetRule) { rule in
                ConfirmSheet(rule: rule, member: me ?? Member(familyID: UUID(), name: "", emoji: "🙂", role: .child),
                             family: family ?? Family(name: "", ownerID: UUID())) { result in
                    toast = result
                    if result.hasPrefix("+") { app.celebrate() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { toast = nil }
                }
                .presentationDetents([.medium])
            }
        }
    }

    private func header(family: Family) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.title2.weight(.bold))
                Text(family.name + (family.isDemo ? " · 体验模式" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var greeting: String {
        guard let me else { return "你好" }
        let hour = FamilyCalendar.calendar(timezoneID: family?.timezoneID ?? "UTC")
            .component(.hour, from: .now)
        let word = hour < 5 ? "夜深了" : hour < 11 ? "早上好" : hour < 14 ? "中午好" : hour < 19 ? "下午好" : "晚上好"
        return "\(word)，\(me.name) 👋"
    }

    private func toastView(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Color(hex: 0x3A3A3C), in: Capsule())
            .frame(maxWidth: .infinity)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: 家长审批（pending 记录）

    private func approvalsSection(_ s: HomeSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("待我确认（\(s.pendingRecords.count)）", systemImage: "bell.badge")
                .font(.headline)
            let byID = Dictionary(uniqueKeysWithValues: allMembers.filter { $0.familyID == family!.id }.map { ($0.id, $0) })
            ForEach(s.pendingRecords.prefix(4)) { rec in
                if let m = byID[rec.memberID] {
                    HStack(spacing: 10) {
                        Text(m.emoji)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(m.name) · \(ruleName(rec.ruleID))")
                                .font(.subheadline.weight(.medium))
                            Text(rec.createdAt, format: .relative(presentation: .named))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(rec.points >= 0 ? "+\(rec.points)" : "\(rec.points)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(rec.points >= 0 ? Theme.addGreen : Theme.deductRed)
                        Button {
                            Haptics.light()
                            try? ScoreEngine.approve(record: rec, family: family!, by: me!, context: context)
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Theme.addGreen)
                        }
                        .buttonStyle(.plain)
                        Button {
                            Haptics.light()
                            try? ScoreEngine.reject(record: rec, family: family!, by: me!, context: context)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Theme.deductRed.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .scoreCard()
    }

    // MARK: 快速加分

    private func quickSection(_ s: HomeSummary, family: Family) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("快速加分", systemImage: "bolt.fill").font(.headline)
                Spacer()
                if family.settingsData.doublePointsMultiplier > 1 {
                    Text("🎉 双倍积分日 ×\(family.settingsData.doublePointsMultiplier, specifier: "%.0f")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.deductRed)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                      spacing: 10) {
                ForEach(s.quickRules) { rule in
                    QuickActionChip(rule: rule, coefficient: me?.coefficient ?? 1) {
                        Haptics.light()
                        sheetRule = rule
                    }
                }
            }
        }
    }

    // MARK: 今日待办

    private func todoSection(_ s: HomeSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("今日待办（\(s.todayAssignments.filter { !$0.done }.count)）", systemImage: "checklist")
                .font(.headline)
            if s.todayAssignments.isEmpty {
                Text("今天没有待办，自由发挥 ✨")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(s.todayAssignments) { item in
                TaskRowView(item: item) {
                    sheetRule = item.rule
                }
                .opacity(item.done ? 0.55 : 1)
            }
        }
        .padding(16)
        .scoreCard()
    }

    // MARK: 家庭动态

    private func feedSection(_ s: HomeSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("家庭动态", systemImage: "bubble.left.and.bubble.right.fill")
                .font(.headline)
            ForEach(s.feed) { item in
                FeedRowView(item: item)
            }
        }
        .padding(16)
        .scoreCard()
    }

    private var switchButton: some View {
        Button {
            Haptics.light()
            showSwitcher = true
        } label: {
            if let me {
                Text(me.emoji).font(.title3)
            } else {
                Image(systemName: "person.crop.circle")
            }
        }
        .sheet(isPresented: $showSwitcher) { MemberSwitcherSheet() }
    }
    @State private var showSwitcher = false

    private func ruleName(_ id: UUID?) -> String {
        guard let id else { return "记录" }
        return allRules.first { $0.id == id }?.name ?? "行为"
    }
}
