import SwiftUI
import SwiftData

/// 我的页（§8.5）
struct ProfileView: View {
    @EnvironmentObject var app: AppEnvironment
    @Environment(\.modelContext) private var context
    @Query private var allMembers: [Member]
    @Query private var allRules: [Rule]
    @Query private var allRedemptions: [Redemption]

    @State private var showSwitcher = false
    @State private var showFamilyManage = false
    @State private var showRules = false
    @State private var showAudit = false
    @State private var showRedeemAdmin = false

    private var family: Family? { app.currentFamily(in: context) }
    private var me: Member? { app.currentMember(in: context) }
    private var isAdmin: Bool { me?.role == .admin }

    var body: some View {
        NavigationStack {
            List {
                if let me {
                    profileCard(me)
                    if isAdmin { adminSection }
                    memberSection
                    aboutSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.appBackground)
            .navigationTitle("我的")
            .sheet(isPresented: $showSwitcher) { MemberSwitcherSheet() }
            .sheet(isPresented: $showFamilyManage) { FamilyManageSheet() }
            .sheet(isPresented: $showRules) { RuleAdminSheet() }
            .sheet(isPresented: $showAudit) { AuditLogSheet() }
            .sheet(isPresented: $showRedeemAdmin) { AdminRedeemSheet() }
        }
    }

    // MARK: 个人卡

    private func profileCard(_ me: Member) -> some View {
        Section {
            VStack(spacing: 14) {
                MemberAvatarView(member: me, size: 72)
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Text(me.name).font(.title3.weight(.bold))
                        LevelBadge(level: me.level)
                    }
                    Text("\(roleLabel(me.role)) · \(family?.name ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("「\(LevelEngine.title(forLevel: me.level))」")
                        .font(.footnote)
                        .foregroundStyle(Theme.primary)
                }

                HStack(spacing: 12) {
                    statBox(value: "\(me.cumulativeScore)", label: "累计积分")
                    statBox(value: "\(me.availableScore)", label: "可用积分")
                    statBox(value: "\(me.streakDays) 天", label: "连续打卡",
                            icon: "flame.fill", iconColor: Theme.primary)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Lv.\(me.level) → Lv.\(min(me.level + 1, 10))")
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        if let next = LevelEngine.pointsToNext(score: me.cumulativeScore) {
                            Text("还差 \(next) 分").font(.caption2).foregroundStyle(Theme.primary)
                        }
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.primary.opacity(0.15))
                            Capsule()
                                .fill(Theme.brandGradient)
                                .frame(width: geo.size.width * LevelEngine.progress(score: me.cumulativeScore))
                        }
                    }
                    .frame(height: 8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    private func statBox(value: String, label: String, icon: String? = nil, iconColor: Color = .secondary) -> some View {
        VStack(spacing: 3) {
            if let icon {
                Image(systemName: icon).font(.caption).foregroundStyle(iconColor)
            }
            Text(value).font(.system(.headline, design: .rounded, weight: .bold).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: 管理区（家长）

    private var adminSection: some View {
        Section("家长工具") {
            row("person.2.fill", "家庭管理") { showFamilyManage = true }
            row("list.bullet.rectangle.portrait", "积分规则配置") { showRules = true }
            row("shield.lefthalf.filled", "审计日志") { showAudit = true }
            row("qrcode", "兑换核销") { showRedeemAdmin = true }
        }
    }

    private var memberSection: some View {
        Section("成员") {
            row("arrow.left.arrow.right", "切换成员") {
                showSwitcher = true
            }
        }
    }

    private var aboutSection: some View {
        Section("关于") {
            HStack {
                row("info.circle", "家分宝 v1.0") {}
                Spacer()
                Text("每一分，都是爱")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func row(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Label(title, systemImage: icon)
                .foregroundStyle(.primary)
        }
    }

    private func roleLabel(_ role: MemberRole) -> String {
        switch role {
        case .admin: "家长"
        case .child: "孩子"
        case .elder: "长辈"
        }
    }
}

// MARK: - 切换成员（本地单机多角色，§8.5）

struct MemberSwitcherSheet: View {
    @EnvironmentObject var app: AppEnvironment
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allMembers: [Member]

    var body: some View {
        NavigationStack {
            List {
                if let f = app.currentFamily(in: context) {
                    ForEach(allMembers.filter { $0.familyID == f.id && $0.status == .active }) { m in
                        Button {
                            Haptics.light()
                            app.currentMemberID = m.id
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                MemberAvatarView(member: m, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.name).foregroundStyle(.primary)
                                    Text(roleText(m))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if app.currentMemberID == m.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.primary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("切换成员")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func roleText(_ m: Member) -> String {
        let base = m.role == .admin ? "家长" : m.role == .child ? "孩子" : "长辈"
        return "\(base) · 可用 \(m.availableScore) 分"
    }
}

// MARK: - 家庭管理

struct FamilyManageSheet: View {
    @EnvironmentObject var app: AppEnvironment
    @Environment(\.modelContext) private var context
    @Query private var allMembers: [Member]

    @State private var newName = ""
    @State private var newRole: MemberRole = .child
    @State private var newEmoji = "👦"

    private var family: Family? { app.currentFamily(in: context) }
    private var members: [Member] {
        guard let f = family else { return [] }
        return allMembers.filter { $0.familyID == f.id }
    }

    private let emojis = ["👨", "👩", "👦", "👧", "👵", "👴", "🧑", "👶"]

    var body: some View {
        NavigationStack {
            List {
                Section("成员（\(members.filter { $0.status == .active }.count)）") {
                    ForEach(members) { m in
                        HStack(spacing: 12) {
                            MemberAvatarView(member: m, size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.name)
                                Text(m.role == .admin ? "家长" : m.role == .child ? "孩子 · 系数 \(m.coefficient, specifier: "%.1f")" : "长辈")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if m.status == .exited {
                                Text("已退出").font(.caption).foregroundStyle(.secondary)
                            } else if m.id != family?.ownerID {
                                Button("退出") {
                                    FamilyService.exitMember(m, context: context)
                                }
                                .font(.caption)
                                .foregroundStyle(Theme.deductRed)
                            } else {
                                Text("创建人").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("添加成员") {
                    TextField("昵称", text: $newName)
                    Picker("角色", selection: $newRole) {
                        Text("孩子").tag(MemberRole.child)
                        Text("家长").tag(MemberRole.admin)
                        Text("长辈").tag(MemberRole.elder)
                    }
                    .pickerStyle(.segmented)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(emojis, id: \.self) { e in
                                Button {
                                    newEmoji = e
                                } label: {
                                    Text(e).font(.title3)
                                        .padding(8)
                                        .background(newEmoji == e ? Theme.primary.opacity(0.15) : .clear,
                                                    in: Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Button("添加") {
                        guard let f = family, !newName.isEmpty else { return }
                        _ = FamilyService.addMember(to: f, name: newName, role: newRole, emoji: newEmoji,
                                                     context: context)
                        Haptics.success()
                        newName = ""
                    }
                    .disabled(newName.isEmpty)
                }
            }
            .navigationTitle("家庭管理")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 规则配置（家长）

struct RuleAdminSheet: View {
    @EnvironmentObject var app: AppEnvironment
    @Environment(\.modelContext) private var context
    @Query private var allRules: [Rule]

    private var family: Family? { app.currentFamily(in: context) }
    private var rules: [Rule] {
        guard let f = family else { return [] }
        return allRules.filter { $0.familyID == f.id }.sorted {
            ($0.isActive ? 0 : 1, $0.sortOrder) < ($1.isActive ? 0 : 1, $1.sortOrder)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(RuleCategory.allCases, id: \.self) { cat in
                    let group = rules.filter { $0.category == cat }
                    if !group.isEmpty {
                        Section("\(cat.iconName) \(cat.label)") {
                            ForEach(group) { rule in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Image(systemName: rule.icon)
                                                .foregroundStyle(rule.isDeduction ? Theme.deductRed : Theme.primary)
                                                .frame(width: 24)
                                            Text(rule.name).font(.subheadline)
                                            if rule.requiresApproval {
                                                Image(systemName: "checkmark.shield")
                                                    .font(.caption2)
                                                    .foregroundStyle(Theme.gold)
                                            }
                                        }
                                        HStack(spacing: 8) {
                                            Text(rule.points >= 0 ? "+\(rule.points)" : "\(rule.points)")
                                                .font(.caption.weight(.bold).monospacedDigit())
                                                .foregroundStyle(rule.points >= 0 ? Theme.addGreen : Theme.deductRed)
                                            Text(rule.dailyLimit > 0 ? "每日 \(rule.dailyLimit) 次" : "不限次")
                                                .font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { rule.isActive },
                                        set: { rule.isActive = $0; try? context.save() }))
                                        .labelsHidden()
                                        .tint(Theme.primary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("积分规则")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 审计日志 + 异常报告

struct AuditLogSheet: View {
    @EnvironmentObject var app: AppEnvironment
    @Environment(\.modelContext) private var context
    @Query private var allMembers: [Member]
    @Query private var allLogs: [AuditLog]
    @Query private var allRules: [Rule]

    private var family: Family? { app.currentFamily(in: context) }
    private var logs: [AuditLog] {
        guard let f = family else { return [] }
        return allLogs.filter { $0.familyID == f.id }
            .sorted { $0.createdAt > $1.createdAt }
    }
    private var anomalies: [AuditService.Anomaly] {
        guard let f = family else { return [] }
        let members = allMembers.filter { $0.familyID == f.id }
        return AuditService.detectAnomalies(family: f, members: members, context: context)
    }

    var body: some View {
        NavigationStack {
            List {
                if !anomalies.isEmpty {
                    Section("⚠️ 异常提示（只提示，不处罚）") {
                        ForEach(anomalies) { a in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(a.code) · \(a.title)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Theme.deductRed.opacity(0.85))
                                Text(a.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                Section("操作记录") {
                    ForEach(logs.prefix(60)) { log in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("\(memberNames[log.actorID] ?? "成员") · \(actionLabel(log.action))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.primary)
                                Spacer()
                                Text(log.createdAt, format: .dateTime.month().day().hour().minute())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if let reason = log.reason {
                                Text(reason).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("审计日志")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func actionLabel(_ a: AuditAction) -> String {
        actorName(a) + " · " + {
            switch a {
            case .add: "加分"
            case .deduct: "减分"
            case .approve: "确认"
            case .reject: "驳回"
            case .reverse: "撤销"
            case .config: "改配置"
            case .redeem: "兑换"
            }
        }()
    }

    private var memberNames: [UUID: String] {
        Dictionary(uniqueKeysWithValues: allMembers.map { ($0.id, $0.name) })
    }

    private func actorName(_ a: AuditAction) -> String { "" }
}

// MARK: - 家长核销兑换

struct AdminRedeemSheet: View {
    @EnvironmentObject var app: AppEnvironment
    @Environment(\.modelContext) private var context
    @Query private var allRedemptions: [Redemption]
    @Query private var allRewards: [Reward]
    @Query private var allMembers: [Member]

    @State private var inputCode = ""
    @State private var result: String?

    private var family: Family? { app.currentFamily(in: context) }
    private var pending: [Redemption] {
        guard let f = family else { return [] }
        return allRedemptions
            .filter { $0.familyID == f.id && $0.status == .pending }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("输入核销码") {
                    TextField("FS-XXXX-XXXX", text: $inputCode)
                        .font(.system(.title3, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                    if let r = result {
                        Text(r).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("待核销（\(pending.count)）") {
                    if pending.isEmpty { Text("暂无").foregroundStyle(.secondary) }
                    ForEach(pending) { p in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(memberName(p.memberID)).font(.subheadline.weight(.medium))
                                Text(rewardName(p.rewardID)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("核销") {
                                verify(code: p.code)
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.addGreen)
                        }
                    }
                }
            }
            .navigationTitle("兑换核销")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func verify(code: String) {
        guard RewardService.isValidCode(code.trimmingCharacters(in: .whitespaces)) else {
            Haptics.warning()
            result = "核销码校验失败，请让孩子重新出示"
            return
        }
        if let r = allRedemptions.first(where: { $0.code == code && $0.status == .pending }),
           let admin = app.currentMember(in: context) {
            try? RewardService.confirm(r, by: admin, context: context)
            Haptics.success()
            result = "✅ 核销成功：「\(rewardName(r.rewardID))」"
            inputCode = ""
        } else {
            result = "未找到对应的待核销记录"
        }
    }

    private func memberName(_ id: UUID) -> String {
        allMembers.first { $0.id == id }?.name ?? "成员"
    }
    private func rewardName(_ id: UUID) -> String {
        allRewards.first { $0.id == id }?.title ?? "奖励"
    }
}
