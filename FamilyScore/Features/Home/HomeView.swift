import SwiftUI
import SwiftData
import UserNotifications

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
    @State private var showAssign = false
    @State private var showExitDemo = false
    @State private var birthdayList: [BirthdayService.Upcoming] = []

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
                        if family.isDemo { demoBanner }
                        if !birthdayList.isEmpty { birthdayCard }
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
            .sheet(isPresented: $showAssign) { AssignmentSheet() }
            .confirmationDialog("退出体验模式将清空演示数据，回到开屏引导",
                                isPresented: $showExitDemo, titleVisibility: .visible) {
                Button("退出并清空演示数据", role: .destructive) {
                    FamilyService.exitDemoMode(context: context)
                    app.currentMemberID = nil
                    hasCompletedOnboarding = false
                }
                Button("取消", role: .cancel) {}
            }
            .onAppear(perform: refreshBirthdayAndNotifications)
            .onReceive(NotificationCenter.default.publisher(for: .fsArrivedHome)) { _ in
                fireArrivalReminder()
            }
            .fullScreenCover(isPresented: Binding(get: { proofFullscreen != nil },
                                                  set: { if !$0 { proofFullscreen = nil } })) {
                if let img = proofFullscreen {
                    FullscreenImageView(image: img)
                }
            }
        }
    }

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private func refreshBirthdayAndNotifications() {
        guard let f = family else { return }
        let members = allMembers.filter { $0.familyID == f.id }
        birthdayList = BirthdayService.upcoming(members: members, family: f)
        NotificationService.requestAuthorization()
        NotificationService.reschedule(family: f, members: members, context: context)
        LocationService.shared.startMonitoring(family: f)
        // 锁屏一键打卡队列结算 + Widget 摘要刷新（§14.2）
        if let me {
            WidgetSyncService.consumeQueue(me: me, family: f, context: context)
            WidgetSyncService.refresh(family: f, me: me, context: context)
        }
    }

    /// 到家提醒：有未完成待办才发（§18.4 地理触发）
    private func fireArrivalReminder() {
        guard let f = family, let s = summary else { return }
        let settings = NotificationSettings.load()
        guard let msg = GeoReminder.arrivalMessage(
            openTodoCount: s.todayAssignments.filter { !$0.done }.count,
            todoTitle: s.todayAssignments.first(where: { !$0.done })?.rule.name,
            geoEnabled: settings.master && settings.geoTodo,
            minutesSinceLastFire: 60,
            lastFireDate: LocationService.shared.lastArrivalFire) else { return }
        let content = UNMutableNotificationContent()
        content.title = msg.title
        content.body = msg.body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "fs-geo-\(UUID().uuidString)", content: content, trigger: trigger))
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
            Label("待我评审（\(s.pendingRecords.count)）", systemImage: "bell.badge")
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
                        proofThumb(rec)
                        Button {
                            Haptics.light()
                            try? ScoreEngine.approve(record: rec, family: family!, by: me!, context: context)
                            WidgetSyncService.refresh(family: family, me: me, context: context)
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
            HStack {
                Label("今日待办（\(s.todayAssignments.filter { !$0.done }.count)）", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                if me?.role == .admin {
                    Button {
                        Haptics.light()
                        showAssign = true
                    } label: {
                        Label("指派", systemImage: "plus.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
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
        .accessibilityLabel("切换成员")
        .sheet(isPresented: $showSwitcher) { MemberSwitcherSheet() }
    }
    @State private var showSwitcher = false

    // MARK: 体验模式 banner（v2.1 需求 4）
    private var demoBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "theatermasks.fill")
                .foregroundStyle(Theme.rankBlue)
            Text("体验模式 · 数据为演示数据")
                .font(.caption.weight(.medium))
            Spacer()
            Button("退出体验") { showExitDemo = true }
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.deductRed)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.rankBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: 生日提醒（v2.1 需求 6）
    private var birthdayCard: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(birthdayList) { up in
                    HStack(spacing: 8) {
                        Text(up.isToday ? "🎂" : "🎁")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(up.isToday ? "今天是\(up.member.name)的生日！"
                                             : "\(up.member.name)的生日 · \(up.daysLeft) 天后")
                                .font(.caption.weight(.semibold))
                            Text(up.isToday ? "给 TA 一个大大的拥抱吧" : "提前准备个小惊喜")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(up.isToday ? Theme.gold.opacity(0.18) : Theme.primary.opacity(0.07),
                                in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    @ViewBuilder
    private func proofThumb(_ rec: ScoreRecord) -> some View {
        if let data = rec.proofImageData, let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable().scaledToFill()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture { proofFullscreen = img }
                .accessibilityLabel("查看凭证")
        } else {
            Image(systemName: "camera.metering.unknown")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
    @State private var proofFullscreen: UIImage?
    @State private var showProofFull = false

    private func ruleName(_ id: UUID?) -> String {
        guard let id else { return "记录" }
        return allRules.first { $0.id == id }?.name ?? "行为"
    }
}
