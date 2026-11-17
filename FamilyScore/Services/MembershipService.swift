import Foundation
import StoreKit

/// 会员权益（§17.1 免费 vs 会员）与订阅状态
enum MembershipFeature: String, CaseIterable {
    case unlimitedMembers      // 免费限 3 人
    case fullHistory           // 免费仅 1 年
    case fullTemplates         // 免费仅基础 20 条模板
    case fullYearReport        // 完整年度报告 + 分享卡
    case dataExport            // 数据导出
    case league                // 家庭联赛（M4 云端）

    var title: String {
        switch self {
        case .unlimitedMembers: "无限成员"
        case .fullHistory: "永久历史数据"
        case .fullTemplates: "全部规则模板"
        case .fullYearReport: "完整年度报告"
        case .dataExport: "数据导出"
        case .league: "亲友家庭联赛"
        }
    }

    var freeAvailable: Bool {
        switch self {
        case .unlimitedMembers, .fullHistory, .fullTemplates, .fullYearReport, .league: false
        case .dataExport: false
        }
    }
}

/// 会员状态（本地.entitlement 缓存 + StoreKit 交易校验）
struct MembershipState: Codable, Equatable {
    var productID: String?          // 月/年订阅 ID
    var expiresAt: Date?
    var isMember: Bool { productID != nil && (expiresAt ?? .distantFuture) > .now }

    static let storageKey = "fs.membership.state"

    static func load(defaults: UserDefaults = .standard) -> MembershipState {
        guard let data = defaults.data(forKey: Self.storageKey),
              let s = try? JSONDecoder().decode(MembershipState.self, from: data) else {
            return MembershipState()
        }
        return s
    }

    func save(defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

/// 功能门槛（§17.1）：会员判定纯函数（可测），订阅交易走 StoreKit 2
enum MembershipGate {

    static let monthlyID = "com.sanshi.familyscore.member.monthly"
    static let yearlyID = "com.sanshi.familyscore.member.yearly"

    static func allows(_ feature: MembershipFeature, state: MembershipState) -> Bool {
        state.isMember || feature.freeAvailable
    }

    /// 免费版成员数上限（§17.1）
    static func canAddMember(currentActive: Int, state: MembershipState) -> Bool {
        state.isMember || currentActive < 3
    }

    /// 免费版历史数据窗口（1 年，§17.1）
    static func historyCutoff(state: MembershipState, now: Date = .now) -> Date? {
        state.isMember ? nil : now.addingTimeInterval(-365 * 86400)
    }

    /// 免费版模板（仅三口之家基础包，§17.1）
    static func isTemplateAllowed(_ kind: RuleTemplateService.TemplateKind, state: MembershipState) -> Bool {
        state.isMember || kind == .three || kind == .custom
    }
}

/// StoreKit 2 订阅服务（模拟器用 Configuration.storekit 本地测试）
@MainActor
final class MembershipService: ObservableObject {

    static let shared = MembershipService()

    @Published var products: [Product] = []
    @Published var state: MembershipState = MembershipState.load()
    @Published var purchasing = false
    @Published var message: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task.detached { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
    }

    deinit { updatesTask?.cancel() }

    func loadProducts() async {
        do {
            products = try await Product.products(for: [MembershipGate.monthlyID, MembershipGate.yearlyID])
                .sorted { $0.price < $1.price }
        } catch {
            message = "商店暂不可用（本地测试请用 Configuration.storekit）"
        }
    }

    func purchase(_ product: Product) async {
        purchasing = true
        defer { purchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let txn) = verification {
                    apply(txn)
                    await txn.finish()
                    message = "🎉 欢迎加入会员，谢谢支持"
                } else {
                    message = "交易校验失败"
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            message = "购买未完成：\(error.localizedDescription)"
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = state.isMember ? "已恢复会员 ✅" : "没有找到可恢复的购买"
        } catch {
            message = "恢复失败：\(error.localizedDescription)"
        }
    }

    /// 从 StoreKit 当前权益刷新本地缓存
    func refreshEntitlements() async {
        var newest: (id: String, expiry: Date)?
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let txn) = entitlement,
               txn.productID == MembershipGate.monthlyID || txn.productID == MembershipGate.yearlyID {
                let expiry = txn.expirationDate ?? .distantFuture
                if newest == nil || expiry > newest!.expiry {
                    newest = (txn.productID, expiry)
                }
            }
        }
        if let n = newest {
            state = MembershipState(productID: n.id, expiresAt: n.expiry)
        } else {
            state = MembershipState()
        }
        state.save()
    }

    private func handle(_ update: VerificationResult<Transaction>) async {
        if case .verified(let txn) = update {
            await refreshEntitlements()
            await txn.finish()
        }
    }

    private func apply(_ txn: Transaction) {
        state = MembershipState(productID: txn.productID,
                                expiresAt: txn.expirationDate ?? .distantFuture)
        state.save()
    }
}
