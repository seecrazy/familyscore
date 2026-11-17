import SwiftUI
import StoreKit

/// 会员页（§17.1）：权益对比、订阅购买、恢复购买
struct MembershipSheet: View {
    @StateObject private var store = MembershipService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    benefitsTable
                    if store.state.isMember {
                        memberBanner
                    } else {
                        purchaseButtons
                    }
                    if let msg = store.message {
                        Text(msg).font(.caption).foregroundStyle(Theme.primary)
                    }
                    footnote
                }
                .padding()
            }
            .background(Theme.appBackground)
            .navigationTitle("家分宝会员")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.fontWeight(.semibold)
                }
            }
            .task {
                await store.loadProducts()
                await store.refreshEntitlements()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "crown.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.gold)
            Text("核心功能永久免费").font(.headline)
            Text("会员卖的是仪式感——无限成员、永久历史、完整年报。绝不拿家庭日常功能做付费墙。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var benefitsTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("权益").font(.caption.weight(.semibold)).frame(width: 110, alignment: .leading)
                Text("免费").font(.caption.weight(.semibold)).frame(maxWidth: .infinity)
                Text("会员").font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 8)
            ForEach(Array(benefitRows.enumerated()), id: \.offset) { i, row in
                HStack {
                    Text(row.0).font(.caption).frame(width: 110, alignment: .leading)
                    Text(row.1).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.addGreen)
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 7)
                .background(i.isMultiple(of: 2) ? Color.primary.opacity(0.03) : .clear)
            }
        }
        .padding(.horizontal, 14)
        .scoreCard()
    }

    private var benefitRows: [(String, String)] {
        [
            ("成员数", "3 人"),
            ("历史数据", "1 年"),
            ("规则模板", "基础 20 条"),
            ("年度报告", "简版"),
            ("数据导出", "—"),
            ("家庭联赛", "—"),
        ]
    }

    private var memberBanner: some View {
        VStack(spacing: 6) {
            Image(systemName: "seal.checkmark.fill")
                .font(.title)
                .foregroundStyle(Theme.addGreen)
            Text("会员生效中")
                .font(.headline)
            if let exp = store.state.expiresAt {
                Text("有效期至 \(exp.formatted(.dateTime.year().month().day()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .scoreCard()
    }

    private var purchaseButtons: some View {
        VStack(spacing: 10) {
            if store.products.isEmpty {
                if store.purchasing { ProgressView() }
                else {
                    Text("商店加载中或不可用")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(store.products, id: \.id) { product in
                Button {
                    Task { await store.purchase(product) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.displayName).font(.subheadline.weight(.semibold))
                            Text(product.description).font(.caption2).lineLimit(1)
                        }
                        Spacer()
                        Text(product.displayPrice)
                            .font(.title3.weight(.bold).monospacedDigit())
                    }
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(store.purchasing)
            }
            Button {
                Task { await store.restore() }
            } label: {
                Text("恢复购买")
                    .font(.footnote)
                    .foregroundStyle(Theme.primary)
            }
        }
    }

    private var footnote: some View {
        Text("订阅通过 App Store 账号扣款，可随时在系统设置取消。开发调试：工程内 Configuration.storekit 本地商店。")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}
