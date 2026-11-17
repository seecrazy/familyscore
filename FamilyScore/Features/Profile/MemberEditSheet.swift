import SwiftUI
import SwiftData

/// 成员资料编辑（v3.3 需求 2）：名称/头像/角色；无记录成员可删除
struct MemberEditSheet: View {
    let member: Member
    let family: Family

    @EnvironmentObject var app: AppEnvironment
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var emoji: String
    @State private var role: MemberRole
    @State private var confirmDelete = false
    @State private var deleteBlocked: Int?
    @State private var isOwner: Bool

    private let emojis = ["👨", "👩", "👦", "👧", "👵", "👴", "🧑", "👶"]
    private let isNewEnoughToHaveNoRecords: Bool

    init(member: Member, family: Family, recordCount: Int) {
        self.member = member
        self.family = family
        _name = State(initialValue: member.name)
        _emoji = State(initialValue: member.emoji)
        _role = State(initialValue: member.role)
        _isOwner = State(initialValue: member.id == family.ownerID)
        isNewEnoughToHaveNoRecords = recordCount == 0 && member.cumulativeScore == 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("资料") {
                    TextField("昵称", text: $name)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(emojis, id: \.self) { e in
                                Button { emoji = e } label: {
                                    Text(e).font(.title2)
                                        .padding(9)
                                        .background(emoji == e ? Theme.primary.opacity(0.15) : .clear,
                                                    in: Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if isOwner {
                    Section { HStack {
                        Text("角色")
                        Spacer()
                        Text("创建人 · 家长").foregroundStyle(.secondary)
                    } } footer: { Text("创建者身份不可更改（家庭管理权的根）") }
                } else {
                    Section("角色") {
                        Picker(selection: $role) {
                            Text("孩子").tag(MemberRole.child)
                            Text("家长").tag(MemberRole.admin)
                            Text("长辈").tag(MemberRole.elder)
                        } label: { Text("角色") }
                        .pickerStyle(.segmented)
                        Text(role == .child ? "孩子系数默认 1.2（可在保存后由家庭规则调整）；角色变更不追溯历史积分"
                                             : "家长可评审打卡、管理规则与商城；长辈界面走大字版")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label(isNewEnoughToHaveNoRecords ? "删除该成员" : "删除（有历史记录不可删）",
                              systemImage: "trash")
                    }
                    .disabled(!isNewEnoughToHaveNoRecords)
                } footer: {
                    Text("仅从未产生过任何记录的成员可删除；有积分/兑换记录的成员只能「退出家庭」，历史账本永久保留（§15）")
                }
            }
            .navigationTitle("编辑成员")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        _ = MemberAdminService.updateProfile(member, family: family,
                                                             name: name, emoji: emoji, role: role,
                                                             context: context)
                        Haptics.success()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("确定删除「\(member.name)」？", isPresented: $confirmDelete,
                               titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    switch MemberAdminService.deleteIfClean(member, context: context) {
                    case .deleted:
                        if app.currentMemberID == member.id { app.currentMemberID = nil }
                        Haptics.success()
                        dismiss()
                    case .blockedHasRecords(let n):
                        deleteBlocked = n
                    }
                }
                Button("取消", role: .cancel) {}
            }
            .alert("无法删除", isPresented: Binding(get: { deleteBlocked != nil },
                                                   set: { if !$0 { deleteBlocked = nil } })) {
                Button("改为退出家庭", role: .destructive) {
                    FamilyService.exitMember(member, context: context)
                    dismiss()
                }
                Button("知道了", role: .cancel) {}
            } message: {
                Text("该成员已有 \(deleteBlocked ?? 0) 条历史记录，删除会破坏全家账本。可以改为「退出家庭」：历史保留、不再参与排名。")
            }
        }
    }
}
