import SwiftUI

/// 通知设置（§18.4：总开关 + 分类开关 + 免打扰时段）
struct NotificationSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var app: AppEnvironment
    @Environment(\.modelContext) private var context
    @State private var settings = NotificationSettings.load()
    @State private var saved = false
    @State private var geoResult: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $settings.master) { Text("通知总开关") }
                } footer: {
                    Text("关闭总开关后所有提醒静音；各分类可独立开关")
                }
                // （footer 组合写法统一为 content-first，见下方各 Section）
                Section {
                    row("到家提醒", "进入家附近 100 米且有未完成待办时提醒（1 小时冷却）", $settings.geoTodo)
                    if let f = app.currentFamily(in: context) {
                        HStack {
                            Button {
                                LocationService.shared.setHomeToCurrent(family: f) { ok in
                                    geoResult = ok ? "✅ 已把当前位置设为家" : "❌ 定位失败，请检查定位权限"
                                    if ok { try? context.save() }
                                }
                            } label: {
                                Label("把当前位置设为「家」", systemImage: "mappin.and.ellipse")
                            }
                        }
                        if GeoReminder.hasHome(f) {
                            Label("已设置家的位置（到家提醒生效中）", systemImage: "checkmark.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let r = geoResult {
                            Text(r).font(.caption).foregroundStyle(Theme.primary)
                        }
                    }
                } header: {
                    Text("地理提醒")
                } footer: {
                    Text("需要「使用期间」定位权限；坐标只存在本机，不上传")
                }
                Section("提醒类型") {
                    row("待办汇总", "每天 19:00，还有未完成待办时提醒", $settings.todo)
                    row("生日提醒", "生日当天与前一天早上 9:00", $settings.birthday)
                    row("评审提醒", "有打卡等你评审时，2 小后提醒一次", $settings.approval)
                    row("积分到期", "批次到期前 30/7/1 天提醒，先花掉更划算", $settings.expiry)
                    row("周结算", "每周五 20:00，本周 MVP 与家庭总分", $settings.weekly)
                    row("打卡保护", "连续打卡 ≥3 天时，当晚 21:00 还没打卡就提醒", $settings.streakProtect)
                }
                Section {
                    Picker(selection: $settings.quietStartMinutes) {
                        timeOptions
                    } label: { Text("开始") }
                    Picker(selection: $settings.quietEndMinutes) {
                        timeOptions
                    } label: { Text("结束") }
                } header: {
                    Text("免打扰")
                } footer: {
                    Text("免打扰时段内的提醒自动顺延到时段结束（默认 22:00–07:00，支持跨午夜）")
                }
            }
            .navigationTitle("通知设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        settings.save()
                        Haptics.success()
                        saved = true
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var timeOptions: some View {
        ForEach(stride(from: 0, to: 24 * 60, by: 30).map { $0 }, id: \.self) { minutes in
            Text(String(format: "%02d:%02d", minutes / 60, minutes % 60)).tag(minutes)
        }
    }

    private func row(_ title: String, _ sub: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(sub).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
