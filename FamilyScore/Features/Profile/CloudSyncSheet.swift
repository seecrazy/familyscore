import SwiftUI
import SwiftData

/// 云同步状态页（§18.3）：iCloud 可用性、未同步变更、手动同步（本地模式导出兜底）
struct CloudSyncSheet: View {
    @EnvironmentObject var app: AppEnvironment
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allLogs: [AuditLog]

    @State private var status: CloudSyncStatus = .localOnly
    @State private var checking = true
    @State private var message: String?

    private var family: Family? { app.currentFamily(in: context) }
    private var unsyncedCount: Int { SyncEngine.unsynced(context: context).count }

    var body: some View {
        NavigationStack {
            List {
                Section("iCloud 状态") {
                    HStack {
                        Image(systemName: statusIcon)
                            .foregroundStyle(statusColor)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(statusText).font(.subheadline.weight(.semibold))
                            Text(statusSub).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if checking { ProgressView().padding(.leading) }
                }

                Section("本地变更队列") {
                    HStack {
                        Text("待同步变更")
                        Spacer()
                        Text("\(unsyncedCount) 条")
                            .font(.body.weight(.semibold).monospacedDigit())
                            .foregroundStyle(unsyncedCount > 0 ? Theme.gold : .secondary)
                    }
                    Button {
                        trySync()
                    } label: {
                        Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(status != .available)
                }

                Section {
                    Text(message ?? "同步说明")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("数据模型：家庭为单位的加密 JSON 包，成员设备经 iCloud 家庭共享接收；积分记录按 UUID 幂等合并，配置类本地优先并提示冲突。无 iCloud 时纯本地使用，也可用「数据导出」手动迁移。")
                }
            }
            .navigationTitle("云同步")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.fontWeight(.semibold)
                }
            }
            .onAppear {
                CloudSyncService.checkStatus { s in
                    status = s
                    checking = false
                }
            }
        }
    }

    private var statusIcon: String {
        switch status {
        case .available, .lastSynced: "checkmark.icloud.fill"
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        case .localOnly: "icloud.slash"
        case .failed: "exclamationmark.icloud"
        }
    }
    private var statusColor: Color {
        switch status {
        case .available, .lastSynced: Theme.addGreen
        case .syncing: Theme.rankBlue
        case .localOnly: .secondary
        case .failed: Theme.deductRed
        }
    }
    private var statusText: String {
        switch status {
        case .available: "iCloud 可用"
        case .localOnly: "本地模式（未检测到 iCloud 账号）"
        case .syncing: "同步中…"
        case .lastSynced(let d): "上次同步 \(d.formatted(.relative(presentation: .named)))"
        case .failed(let e): "同步失败：\(e)"
        }
    }
    private var statusSub: String {
        switch status {
        case .available: "家庭共享邀请发送后，成员设备可自动合并"
        default: "全部功能仍可本地使用；可随时用「数据导出/导入」迁移"
        }
    }

    private func trySync() {
        guard let f = family else { return }
        status = .syncing
        let ok = CloudSyncService.push(family: f, context: context)
        if ok {
            SyncEngine.markAllSynced(context: context)
            status = .lastSynced(.now)
            message = "✅ 已推送 \(unsyncedCount) 条变更"
        } else {
            status = .localOnly
            message = "当前构建未启用 iCloud 能力（需要开发者账号签名）。变更已保留在本地队列，可导出 JSON 手动迁移。"
        }
    }
}
