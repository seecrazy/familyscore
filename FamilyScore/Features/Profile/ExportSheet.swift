import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 数据导出/导入（§8.5/§15 分家导出）
struct ExportSheet: View {
    @EnvironmentObject var app: AppEnvironment
    @Environment(\.modelContext) private var context
    @Query private var allMembers: [Member]

    @State private var exportURL: URL?
    @State private var showImporter = false
    @State private var result: String?

    private var family: Family? { app.currentFamily(in: context) }
    private var members: [Member] {
        guard let f = family else { return [] }
        return allMembers.filter { $0.familyID == f.id && $0.status == .active }
    }

    private var exportAllowed: Bool {
        MembershipGate.allows(.dataExport, state: MembershipState.load())
    }

    var body: some View {
        NavigationStack {
            List {
                if !exportAllowed {
                    Section {
                        Label("数据导出是会员功能", systemImage: "crown.fill")
                            .foregroundStyle(Theme.gold)
                        Text("升级会员解锁导出/导入，用于换机迁移与分家导出")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("去看看会员") { showMembership = true }
                    }
                }
                Section {
                    Button {
                        export(memberFilter: nil, suffix: "全量")
                    } label: {
                        Label("导出整个家庭（JSON）", systemImage: "square.and.arrow.up")
                    }
                    .disabled(!exportAllowed)
                } header: {
                    Text("全量备份")
                } footer: {
                    Text("包含成员、规则、积分记录、奖励与兑换、徽章；凭证图片不导出（隐私与体积）。可用于换机迁移或导入合并。")
                }

                Section {
                    ForEach(members) { m in
                        Button {
                            export(memberFilter: [m.id] + members.filter { $0.role == .admin }.map(\.id),
                                   suffix: m.name)
                        } label: {
                            HStack {
                                Text("\(m.emoji) 只带 \(m.name)")
                                Spacer()
                                Image(systemName: "arrow.right.circle")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                } header: {
                    Text("分家导出（§15）")
                } footer: {
                    Text("只导出所选成员的记录与家长骨架，导入后是一份新的独立家庭")
                }

                Section {
                    Button {
                        showImporter = true
                    } label: {
                        Label("从 JSON 导入（合并）", systemImage: "square.and.arrow.down")
                    }
                    .disabled(!exportAllowed)
                } footer: {
                    Text("按记录唯一 ID 幂等合并：重复导入同一份文件不会产生重复数据")
                }

                if let r = result {
                    Section { Text(r).font(.caption) }
                }
            }
            .navigationTitle("数据导出 / 导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.fontWeight(.semibold)
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(url: item.url)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showMembership) { MembershipSheet() }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    importFrom(url: url)
                case .failure:
                    self.result = "❌ 选择文件失败"
                }
            }
        }
    }
    @Environment(\.dismiss) private var dismiss

    private struct ShareItem: Identifiable { let id = UUID(); let url: URL }

    @State private var shareItem: ShareItem?
    @State private var showMembership = false

    private func export(memberFilter: [UUID]?, suffix: String) {
        guard let f = family else { return }
        do {
            let bundle = try ExportService.export(family: f, context: context, memberFilter: memberFilter)
            let data = try ExportService.encode(bundle)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("家分宝-\(f.name)-\(suffix)-\(Int(Date.now.timeIntervalSince1970)).json")
            try data.write(to: url)
            Haptics.success()
            shareItem = ShareItem(url: url)
        } catch {
            result = "❌ 导出失败：\(error.localizedDescription)"
        }
    }

    private func importFrom(url: URL) {
        do {
            guard url.startAccessingSecurityScopedResource() else {
                result = "❌ 无法读取文件"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            let bundle = try ExportService.decode(data)
            let report = try ExportService.import(bundle, context: context)
            Haptics.success()
            result = "✅ " + report.summary
        } catch {
            result = "❌ 导入失败：文件格式不正确或已损坏"
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
