import SwiftUI
import SwiftData

/// 商城页（§8.4）：奖励卡（折扣/库存/心愿单）、兑换、核销码、兑换记录
struct RewardsView: View {
    @EnvironmentObject var app: AppEnvironment
    @Environment(\.modelContext) private var context
    @Query private var allRewards: [Reward]
    @Query private var allRedemptions: [Redemption]
    @Query private var allMembers: [Member]

    @State private var confirmReward: Reward?
    @State private var showCode: Redemption?
    @State private var toast: String?

    private var family: Family? { app.currentFamily(in: context) }
    private var me: Member? { app.currentMember(in: context) }
    private var rewards: [Reward] {
        guard let f = family else { return [] }
        return allRewards.filter { $0.familyID == f.id && $0.isActive }
            .sorted { $0.effectiveCost < $1.effectiveCost }
    }
    private var redemptions: [Redemption] {
        guard let m = me else { return [] }
        return allRedemptions.filter { $0.memberID == m.id }
            .sorted { $0.createdAt > $1.createdAt }
    }
    private var isAdmin: Bool { me?.role == .admin }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    balanceCard
                    if let t = toast {
                        Text(t)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color(hex: 0x3A3A3C), in: Capsule())
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    rewardList
                    historySection
                }
                .padding(.horizontal)
                .padding(.vertical)
                .animation(.easeInOut(duration: 0.25), value: toast)
            }
            .background(Theme.appBackground)
            .navigationTitle("奖励商城")
            .sheet(item: $confirmReward) { reward in
                RewardConfirmSheet(reward: reward) { result in
                    toast = result
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { toast = nil }
                }
                .presentationDetents([.medium])
            }
            .sheet(item: $showCode) { r in
                RedemptionCodeSheet(redemption: r)
                    .presentationDetents([.medium])
            }
        }
    }

    private var balanceCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("我的可用积分").font(.caption).foregroundStyle(.white.opacity(0.85))
                Text("\(me?.availableScore ?? 0)")
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
            }
            Spacer()
            if let m = me {
                VStack(alignment: .trailing, spacing: 2) {
                    LevelBadge(level: m.level)
                        .background(.white.opacity(0.9), in: Capsule())
                    Text("累计 \(m.cumulativeScore)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .padding(18)
        .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .shadow(color: Theme.primary.opacity(0.3), radius: 12, y: 5)
    }

    private var rewardList: some View {
        VStack(spacing: 12) {
            ForEach(rewards) { reward in
                RewardCardView(reward: reward, balance: me?.availableScore ?? 0,
                               isAdmin: isAdmin) { action in
                    switch action {
                    case .redeem:
                        confirmReward = reward
                    case .wish:
                        Haptics.light()
                        if let m = me, !wishListed(reward) {
                            context.insert(WishListItem(memberID: m.id, rewardID: reward.id))
                            try? context.save()
                            toast = "已加入心愿单，攒够了提醒你 ✨"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { toast = nil }
                        }
                    case .confirm(let redemption):
                        showCode = redemption
                    }
                }
            }
        }
    }

    private func wishListed(_ reward: Reward) -> Bool {
        guard let m = me else { return false }
        let mid = m.id, rid = reward.id
        let desc = FetchDescriptor<WishListItem>(predicate: #Predicate {
            $0.memberID == mid && $0.rewardID == rid
        })
        return ((try? context.fetch(desc)) ?? []).isEmpty == false
    }

    private var historySection: some View {
        Group {
            if !redemptions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("兑换记录").font(.headline)
                    ForEach(redemptions.prefix(8)) { r in
                        Button {
                            if r.status == .pending { showCode = r }
                        } label: {
                            HStack {
                                Image(systemName: r.status == .confirmed ? "checkmark.seal.fill" : "ticket")
                                    .foregroundStyle(r.status == .confirmed ? Theme.addGreen : Theme.primary)
                                Text(rewardTitle(r.rewardID))
                                    .font(.subheadline)
                                if r.status == .confirmed {
                                    Text("已核销").font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else if r.status == .cancelled {
                                    Text("已作废").font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("待核销").font(.caption2)
                                        .foregroundStyle(Theme.gold)
                                }
                                Spacer()
                                Text("−\(r.cost)").font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(Theme.deductRed.opacity(0.85))
                                Text(r.createdAt, format: .dateTime.month().day())
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                }
                .padding(16)
                .scoreCard()
            }
        }
    }

    private func rewardTitle(_ id: UUID) -> String {
        allRewards.first { $0.id == id }?.title ?? "奖励"
    }
}

// MARK: - 奖励卡（§10 RewardCard）

enum RewardAction {
    case redeem
    case wish
    case confirm(Redemption)
}

struct RewardCardView: View {
    let reward: Reward
    let balance: Int
    var isAdmin: Bool = false
    var action: (RewardAction) -> Void

    private var cost: Int { reward.effectiveCost }
    private var hasDiscount: Bool {
        reward.discountCost != nil && reward.effectiveCost != reward.cost
    }
    private var affordable: Bool { balance >= cost }
    private var outOfStock: Bool { reward.stock == 0 }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: reward.icon)
                .font(.title2)
                .foregroundStyle(Theme.primary)
                .frame(width: 52, height: 52)
                .background(Theme.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(reward.title).font(.body.weight(.semibold))
                    if hasDiscount {
                        Text("限时折扣")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(Theme.deductRed.opacity(0.12), in: Capsule())
                            .foregroundStyle(Theme.deductRed)
                    }
                }
                HStack(spacing: 6) {
                    if hasDiscount {
                        Text("\(reward.cost)")
                            .font(.caption)
                            .strikethrough()
                            .foregroundStyle(.secondary)
                    }
                    Text("\(cost) 分")
                        .font(.callout.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.primary)
                    Text(reward.stock < 0 ? "库存 ∞" : "库存 \(reward.stock)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !affordable && !outOfStock {
                    Text("还差 \(cost - balance) 分")
                        .font(.caption2)
                        .foregroundStyle(Theme.gold)
                }
            }
            Spacer()

            if outOfStock {
                Text("已抢完")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else if affordable {
                Button {
                    Haptics.medium()
                    action(.redeem)
                } label: {
                    Text("兑换")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(Theme.primary, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    action(.wish)
                } label: {
                    Label("心愿单", systemImage: "heart")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.rankBlue)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(Theme.rankBlue.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .scoreCard()
        .opacity(outOfStock ? 0.55 : 1)
        .accessibilityElement()
        .accessibilityLabel("\(reward.title)，需要 \(cost) 分\(affordable ? "，可以兑换" : "，还差 \(max(0, cost - balance)) 分")")
    }
}

// MARK: - 兑换确认（家长 PIN 简化版：儿童兑换需家长在场点确认）

struct RewardConfirmSheet: View {
    let reward: Reward
    var onResult: (String) -> Void

    @EnvironmentObject var app: AppEnvironment
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Capsule().fill(Color(hex: 0xD1D1D6)).frame(width: 36, height: 5).padding(.top, 8)
            Image(systemName: reward.icon)
                .font(.largeTitle)
                .foregroundStyle(Theme.primary)
            Text("兑换「\(reward.title)」？")
                .font(.headline)
            Text("将消耗 \(reward.effectiveCost) 分")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let me = app.currentMember(in: context), me.role != .admin {
                Label("儿童兑换请家长在场确认", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.caption)
                    .foregroundStyle(Theme.gold)
            }
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Text("再想想")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(hex: 0xE9E9EB), in: RoundedRectangle(cornerRadius: Theme.radiusButton))
                }
                .buttonStyle(.plain)
                Button {
                    redeem()
                } label: {
                    Text("确认兑换")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.primary, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }

    private func redeem() {
        guard let f = app.currentFamily(in: context), let me = app.currentMember(in: context) else { return }
        do {
            _ = try RewardService.redeem(member: me, family: f, reward: reward, context: context)
            Haptics.success()
            app.celebrate()
            WidgetSyncService.refresh(family: f, me: me, context: context)
            onResult("兑换成功！把核销码给家长吧 🎉")
            dismiss()
        } catch let e as RewardError {
            Haptics.warning()
            onDoneError(e)
        } catch {
            onResult("❌ 兑换失败")
            dismiss()
        }
    }

    private func onDoneError(_ e: RewardError) {
        onResult("❌ \(e.errorDescription ?? "兑换失败")")
        dismiss()
    }
}

// MARK: - 核销码（§22.2）

struct RedemptionCodeSheet: View {
    let redemption: Redemption
    @EnvironmentObject var app: AppEnvironment
    @Environment(\.modelContext) private var context
    @Query private var allRewards: [Reward]
    @State private var copied = false

    var body: some View {
        VStack(spacing: 14) {
            Capsule().fill(Color(hex: 0xD1D1D6)).frame(width: 36, height: 5).padding(.top, 8)
            Text(allRewards.first { $0.id == redemption.rewardID }?.title ?? "奖励")
                .font(.headline)
            Text("−\(redemption.cost) 分")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Text(redemption.code)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .kerning(2)
                .padding(.horizontal, 24).padding(.vertical, 14)
                .background(Theme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                .contextMenu {
                    Button(copied ? "已复制" : "复制核销码") {
                        UIPasteboard.general.string = redemption.code
                        copied = true
                    }
                }

            if redemption.status == .pending {
                VStack(spacing: 8) {
                    Text("家长在「我的 → 兑换核销」里输入或核对后确认")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let admin = app.currentMember(in: context), admin.role == .admin {
                        Button {
                            try? RewardService.confirm(redemption, by: admin, context: context)
                            Haptics.success()
                        } label: {
                            Label("我是家长，确认核销", systemImage: "checkmark.seal.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20).padding(.vertical, 11)
                                .background(Theme.addGreen, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Label(redemption.status == .confirmed ? "已核销 ✅" : "已作废",
                      systemImage: redemption.status == .confirmed ? "checkmark.seal.fill" : "xmark.seal")
                    .foregroundStyle(redemption.status == .confirmed ? Theme.addGreen : .secondary)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal)
    }
}
