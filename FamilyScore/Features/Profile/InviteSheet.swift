import SwiftUI

/// 邀请家人（v3.3 需求 3：创建后随时可再邀请）
struct InviteSheet: View {
    let familyName: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var inviteText: String {
        "我在「家分宝」创建了「\(familyName)」的积分小天地 🏠✨\n" +
        "一起把家变得更好——打卡得分、排行榜见成长、积分换惊喜！"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Capsule().fill(Color(hex: 0xD1D1D6)).frame(width: 36, height: 5).padding(.top, 8)
                Image(systemName: "envelope.badge.person.crop.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.primary)
                Text("邀请家人加入「\(familyName)」")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 10) {
                    Label("共用一台 iPhone/iPad：在「家庭管理」的成员菜单里点「切换到 TA」即可", systemImage: "iphone")
                    Label("各自的设备：对方安装家分宝后，用「数据导出 / 导入」把我家的账本传过去", systemImage: "square.and.arrow.up.on.square")
                    Label("iCloud 自动同步：已就绪，随正式版一起开通", systemImage: "icloud")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Theme.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))

                Button {
                    UIPasteboard.general.string = inviteText
                    copied = true
                    Haptics.success()
                } label: {
                    Label(copied ? "已复制，去微信/iMessage 粘贴" : "复制邀请语",
                          systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 4)
            }
            .padding(.horizontal)
            .navigationTitle("邀请家人")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
