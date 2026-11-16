import SwiftUI
import SwiftData

/// 指派任务（v2.1 需求 1）：家长选成员 + 选正向规则 + 截止日（今日/明日）
struct AssignmentSheet: View {
    @EnvironmentObject var app: AppEnvironment
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allMembers: [Member]
    @Query private var allRules: [Rule]

    @State private var assigneeID: UUID?
    @State private var ruleID: UUID?
    @State private var dueDayOffset = 0   // 0=今天 1=明天

    private var family: Family? { app.currentFamily(in: context) }
    private var me: Member? { app.currentMember(in: context) }
    private var activeMembers: [Member] {
        guard let f = family else { return [] }
        return allMembers.filter { $0.familyID == f.id && $0.status == .active && $0.role != .admin }
    }
    private var positiveRules: [Rule] {
        guard let f = family else { return [] }
        return allRules.filter { $0.familyID == f.id && $0.isActive && !$0.isDeduction }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
    private var isValid: Bool { assigneeID != nil && ruleID != nil }

    var body: some View {
        NavigationStack {
            List {
                Section("指派给谁") {
                    if activeMembers.isEmpty {
                        Text("家里还没有孩子/长辈成员，先去「我的 → 家庭管理」添加")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(activeMembers) { m in
                        Button {
                            assigneeID = m.id
                        } label: {
                            HStack(spacing: 10) {
                                MemberAvatarView(member: m, size: 34)
                                Text(m.name).foregroundStyle(.primary)
                                Spacer()
                                if assigneeID == m.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.primary)
                                }
                            }
                        }
                    }
                }
                Section("做什么") {
                    ForEach(positiveRules.prefix(30)) { rule in
                        Button {
                            ruleID = rule.id
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: rule.icon)
                                    .foregroundStyle(Theme.primary)
                                    .frame(width: 26)
                                Text(rule.name).foregroundStyle(.primary)
                                Spacer()
                                Text("+\(rule.points)")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(Theme.addGreen)
                                if ruleID == rule.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.primary)
                                }
                            }
                        }
                    }
                }
                Section("截止") {
                    Picker("截止", selection: $dueDayOffset) {
                        Text("今天").tag(0)
                        Text("明天").tag(1)
                    }
                    .pickerStyle(.segmented)
                    Text("未完成不自动减分，避免待办焦虑；可在审批时选择发起「未完成约定任务」")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("指派任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("指派") { assign() }
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                }
            }
        }
    }

    private func assign() {
        guard let f = family, let me, let assigneeID, let ruleID,
              let rule = positiveRules.first(where: { $0.id == ruleID }) else { return }
        let dueDate = FamilyCalendar.calendar(timezoneID: f.timezoneID)
            .date(byAdding: .day, value: dueDayOffset, to: .now) ?? .now
        let dueKey = FamilyCalendar.dayKey(dueDate, timezoneID: f.timezoneID)
        context.insert(TaskAssignment(familyID: f.id, ruleID: rule.id,
                                      assigneeID: assigneeID, assignerID: me.id, dueDay: dueKey))
        AuditService.log(familyID: f.id, actorID: me.id, action: .config, targetID: rule.id,
                         reason: "指派「\(rule.name)」 截止 \(dueKey)", context: context)
        try? context.save()
        Haptics.success()
        app.celebrate()
        dismiss()
    }
}
