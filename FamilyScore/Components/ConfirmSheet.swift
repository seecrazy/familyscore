import SwiftUI
import SwiftData

/// 加分确认半屏卡（§9.1）：分值预览（含系数）、备注、拍照凭证占位、5 分钟重复二次确认
struct ConfirmSheet: View {
    let rule: Rule
    let member: Member
    let family: Family
    var onDone: (String) -> Void   // 传入结果文案（成功/待确认/错误）

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var proofData: Data?
    @State private var showRepeatConfirm = false
    @State private var repeatError: ScoreEngineError?
    @EnvironmentObject var app: AppEnvironment

    private var actorIsAdmin: Bool {
        guard let id = app.currentMemberID,
              let me = ScoreEngine.fetchMember(id, context: context) else { return false }
        return me.role == .admin
    }

    /// 该次提交是否需要评审（用于 UI 提示）：家长本人提交视为当场通过
    private var needReview: Bool {
        let requires = rule.requiresApproval || family.settingsData.requiresReviewAllCheckIns
        return requires && !actorIsAdmin
    }

    private var previewPoints: Int {
        ScoreEngine.computedPoints(base: rule.points, coefficient: member.coefficient,
                                   multiplier: family.settingsData.doublePointsMultiplier)
    }

    var body: some View {
        VStack(spacing: 18) {
            Capsule().fill(Color(hex: 0xD1D1D6)).frame(width: 36, height: 5).padding(.top, 8)

            Text(rule.isDeduction ? "确认减分" : "确认加分")
                .font(.headline)

            HStack(spacing: 14) {
                Image(systemName: rule.icon)
                    .font(.title)
                    .foregroundStyle(rule.isDeduction ? Theme.deductRed : Theme.primary)
                    .frame(width: 52, height: 52)
                    .background((rule.isDeduction ? Theme.deductRed : Theme.primary).opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.name).font(.body.weight(.semibold))
                    Text("基础 \(rule.points) × 系数 \(member.coefficient, specifier: "%.1f")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(previewPoints >= 0 ? "+\(previewPoints)" : "\(previewPoints)")
                    .font(.title.weight(.bold).monospacedDigit())
                    .foregroundStyle(previewPoints >= 0 ? Theme.addGreen : Theme.deductRed)
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 6) {
                Label(rule.requiresProof ? "这个行为建议拍照证明一下" : "拍照凭证（可选）",
                      systemImage: "camera")
                    .font(.caption)
                    .foregroundStyle(rule.requiresProof ? Theme.gold : .secondary)
                ProofPicker(imageData: $proofData)
            }
            .padding(.horizontal)

            if needReview {
                Label("提交后需家长评审通过才入账", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(Theme.rankBlue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            TextField("备注（可选），如：晚餐后洗碗", text: $note)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            if let err = repeatError, case .deductionCapReached(let applied) = err {
                Label(err.errorDescription ?? "", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.gold)
                    .padding(.horizontal)
            }

            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Text("取消")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color(hex: 0xE9E9EB), in: RoundedRectangle(cornerRadius: Theme.radiusButton))
                }
                .buttonStyle(.plain)

                Button {
                    submit(force: false)
                } label: {
                    Text(rule.isDeduction ? "确认减分" : "确认加分")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(rule.isDeduction ? Theme.deductRed : Theme.primary,
                                    in: RoundedRectangle(cornerRadius: Theme.radiusButton))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .confirmationDialog("5 分钟内已有同样记录，还要再记一次吗？",
                            isPresented: $showRepeatConfirm, titleVisibility: .visible) {
            Button("仍要记一次", role: .destructive) { submit(force: true) }
            Button("取消", role: .cancel) {}
        }
    }

    private func submit(force: Bool) {
        let me = member
        do {
            let outcome = try ScoreEngine.submit(
                member: me, family: family, rule: rule, note: note.isEmpty ? nil : note,
                proofImageData: proofData,
                actorIsAdmin: actorIsAdmin,
                approver: actorIsAdmin ? me.id : nil,
                forceRepeated: force, context: context)
            switch outcome {
            case .approved(let rec):
                Haptics.success()
                onDone(rec.points >= 0
                       ? "+\(rec.points) \(rule.name) · 已入账"
                       : "\(rec.points) \(rule.name) · 已记录")
            case .pendingApproval:
                Haptics.light()
                onDone("已提交，家长评审通过后就入账 🛡️")
            }
            WidgetSyncService.refresh(family: family, me: member, context: context)
            dismiss()
        } catch let err as ScoreEngineError {
            if case .repeatWindow = err, !force {
                repeatError = err
                showRepeatConfirm = true
            } else {
                Haptics.warning()
                onDone("❌ \(err.errorDescription ?? "提交失败")")
                if case .deductionCapReached = err { dismiss() }
            }
        } catch {
            onDone("❌ 提交失败")
        }
    }
}
