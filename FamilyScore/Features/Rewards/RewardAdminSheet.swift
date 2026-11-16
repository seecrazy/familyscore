import SwiftUI
import SwiftData

/// 奖励商城管理（v2.1 需求 3）：新增/编辑/上下架奖励（标题/图标/分值/库存/限时折扣）
struct RewardAdminSheet: View {
    @EnvironmentObject var app: AppEnvironment
    @Environment(\.modelContext) private var context
    @Query private var allRewards: [Reward]

    @State private var editing: Reward?
    @State private var showNew = false

    private var family: Family? { app.currentFamily(in: context) }
    private var rewards: [Reward] {
        guard let f = family else { return [] }
        return allRewards.filter { $0.familyID == f.id }
            .sorted { ($0.isActive ? 0 : 1, $0.cost) < ($1.isActive ? 0 : 1, $1.cost) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rewards) { r in
                        Button {
                            editing = r
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: r.icon)
                                    .font(.title3)
                                    .foregroundStyle(r.isActive ? Theme.primary : .secondary)
                                    .frame(width: 34, height: 34)
                                    .background((r.isActive ? Theme.primary : Color.secondary).opacity(0.1),
                                                in: RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.title).foregroundStyle(.primary)
                                    HStack(spacing: 6) {
                                        if r.effectiveCost != r.cost {
                                            Text("\(r.cost)").strikethrough().font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text("\(r.effectiveCost) 分")
                                            .font(.caption.weight(.bold).monospacedDigit())
                                            .foregroundStyle(Theme.primary)
                                        Text(r.stock < 0 ? "∞" : "×\(r.stock)")
                                            .font(.caption2).foregroundStyle(.secondary)
                                        if r.effectiveCost != r.cost {
                                            Text("折扣中").font(.caption2).foregroundStyle(Theme.deductRed)
                                        }
                                    }
                                }
                                Spacer()
                                if !r.isActive {
                                    Text("已下架").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("奖励（\(rewards.filter(\.isActive).count) 上架中）")
                } footer: {
                    Text("点任意奖励编辑；下架后成员不可见但兑换记录保留")
                }
            }
            .navigationTitle("奖励商城管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showNew = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showNew) {
                RewardEditSheet(reward: nil)
            }
            .sheet(item: $editing) { r in
                RewardEditSheet(reward: r)
            }
        }
    }
}

/// 奖励编辑/新建
struct RewardEditSheet: View {
    let reward: Reward?    // nil = 新建
    @EnvironmentObject var app: AppEnvironment
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var icon = "gift.fill"
    @State private var cost = 100
    @State private var stock = -1
    @State private var hasDiscount = false
    @State private var discountCost = 80
    @State private var discountDays = 3
    @State private var isActive = true

    static let icons = ["film", "icecream", "banknote", "ticket", "gamecontroller.fill",
                        "figure.wave", "moon.stars", "gift.fill", "cup.and.saucer.fill",
                        "cart.fill", "book.fill", "airplane"]

    private var family: Family? { app.currentFamily(in: context) }

    var body: some View {
        NavigationStack {
            Form {
                Section("奖励内容") {
                    TextField("名称，如：选今晚的电影", text: $title)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Self.icons, id: \.self) { ic in
                                Button {
                                    icon = ic
                                } label: {
                                    Image(systemName: ic)
                                        .font(.title3)
                                        .frame(width: 42, height: 42)
                                        .foregroundStyle(icon == ic ? .white : Theme.primary)
                                        .background(icon == ic ? Theme.primary : Theme.primary.opacity(0.08),
                                                    in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Section("定价与库存") {
                    Stepper(value: $cost, in: 10...2000, step: 10) {
                        HStack { Text("所需积分"); Spacer(); Text("\(cost) 分").monospacedDigit() }
                    }
                    Stepper(value: $stock, in: -1...99) {
                        HStack {
                            Text("库存")
                            Spacer()
                            Text(stock < 0 ? "无限" : "\(stock) 件").monospacedDigit()
                        }
                    }
                }
                Section("限时折扣（可选）") {
                    Toggle("开启折扣", isOn: $hasDiscount)
                    if hasDiscount {
                        Stepper(value: $discountCost, in: 10...cost, step: 10) {
                            HStack { Text("折扣价"); Spacer(); Text("\(discountCost) 分").monospacedDigit() }
                        }
                        Stepper(value: $discountDays, in: 1...14) {
                            HStack { Text("持续"); Spacer(); Text("\(discountDays) 天") }
                        }
                    }
                }
                if reward != nil {
                    Section {
                        Toggle("上架中", isOn: $isActive)
                    }
                }
            }
            .navigationTitle(reward == nil ? "新奖励" : "编辑奖励")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(title.isEmpty || (hasDiscount && discountCost >= cost))
                }
            }
            .onAppear {
                guard let r = reward else { return }
                title = r.title; icon = r.icon; cost = r.cost; stock = r.stock
                isActive = r.isActive
                if let d = r.discountCost {
                    hasDiscount = true
                    discountCost = d
                    if let end = r.discountEndsAt {
                        discountDays = max(1, Int(end.timeIntervalSinceNow / 86400))
                    }
                }
            }
        }
    }

    private func save() {
        guard let f = family else { return }
        if let r = reward {
            r.title = title; r.icon = icon; r.cost = cost; r.stock = stock; r.isActive = isActive
            r.discountCost = hasDiscount ? discountCost : nil
            r.discountEndsAt = hasDiscount ? .now.addingTimeInterval(Double(discountDays) * 86400) : nil
        } else {
            context.insert(Reward(
                familyID: f.id, title: title, icon: icon, cost: cost,
                discountCost: hasDiscount ? discountCost : nil,
                discountEndsAt: hasDiscount ? .now.addingTimeInterval(Double(discountDays) * 86400) : nil,
                stock: stock))
        }
        AuditService.log(familyID: f.id, actorID: app.currentMemberID ?? f.ownerID,
                         action: .config, targetID: reward?.id ?? f.id,
                         reason: "\(reward == nil ? "新增" : "修改")奖励「\(title)」", context: context)
        try? context.save()
        Haptics.success()
        dismiss()
    }
}
