import SwiftUI

/// 首页家庭总积分卡（§8.1）：今日总分、我的分+排名、连续天数、周目标进度
struct ScoreCardView: View {
    let summary: HomeSummary
    let me: Member

    private var goalProgress: Double {
        min(1, Double(summary.weeklyScore) / Double(max(summary.weeklyGoal, 1)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("家庭今日总积分")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                if summary.streakDays >= 3 {
                    Label("\(summary.streakDays)", systemImage: "flame.fill")
                        .font(.footnote.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.white.opacity(0.2), in: Capsule())
                        .accessibilityLabel("连续打卡 \(summary.streakDays) 天")
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(summary.familyToday)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("分")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .accessibilityLabel("今日家庭共 \(summary.familyToday) 分")

            Divider().overlay(.white.opacity(0.3))

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("我的今日").font(.caption2).foregroundStyle(.white.opacity(0.8))
                    Text(summary.myToday >= 0 ? "+\(summary.myToday)" : "\(summary.myToday)")
                        .font(.headline.weight(.bold).monospacedDigit()).foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("排名").font(.caption2).foregroundStyle(.white.opacity(0.8))
                    Text("#\(summary.myRank)")
                        .font(.headline.weight(.bold).monospacedDigit()).foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("本周目标")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Text("\(summary.weeklyScore)/\(summary.weeklyGoal)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.25))
                        Capsule()
                            .fill(LinearGradient(colors: [.white, Theme.gold],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * goalProgress)
                            .animation(.spring(response: 0.5), value: goalProgress)
                    }
                }
                .frame(height: 8)
            }
            .accessibilityElement()
            .accessibilityLabel("本周团队目标 \(summary.weeklyScore) 分，目标 \(summary.weeklyGoal) 分")
        }
        .padding(20)
        .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .shadow(color: Theme.primary.opacity(0.35), radius: 14, y: 6)
    }
}

/// 快速加分按钮（§8.1 智能宫格）
struct QuickActionChip: View {
    let rule: Rule
    let coefficient: Double
    var action: () -> Void

    private var displayPoints: Int {
        ScoreEngine.computedPoints(base: rule.points, coefficient: coefficient, multiplier: 1)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: rule.icon)
                    .font(.title3)
                    .foregroundStyle(Theme.primary)
                    .frame(height: 26)
                Text(rule.name)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("+\(displayPoints)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.addGreen)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(rule.name)，加 \(displayPoints) 分")
    }
}

/// 待办行（§8.1：来源标签 + 打卡按钮）
struct TaskRowView: View {
    let item: HomeSummary.TaskAssignmentItem
    var onCheckIn: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(item.done ? Theme.addGreen : Color(hex: 0xC7C7CC))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.rule.name)
                        .font(.subheadline.weight(.medium))
                        .strikethrough(item.done, color: .secondary)
                    Text(item.source)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 1.5)
                        .background(item.source.hasPrefix("@") ? Theme.rankBlue.opacity(0.12) : Theme.primary.opacity(0.1),
                                    in: Capsule())
                        .foregroundStyle(item.source.hasPrefix("@") ? Theme.rankBlue : Theme.primary)
                }
                HStack(spacing: 4) {
                    Text(item.assignee.emoji).font(.caption)
                    Text(item.assignee.name).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("+\(ScoreEngine.computedPoints(base: item.rule.points, coefficient: item.assignee.coefficient, multiplier: 1))")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.addGreen)
                }
            }
            if !item.done {
                Button {
                    Haptics.light()
                    onCheckIn?()
                } label: {
                    Text("打卡")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Theme.primary, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }
}

/// 家庭动态行
struct FeedRowView: View {
    let item: HomeSummary.FeedItem
    var body: some View {
        HStack(spacing: 10) {
            Text(item.member.emoji).font(.subheadline)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(item.member.name) 完成「\(item.text)」")
                    .font(.caption)
                    .lineLimit(1)
                Text(item.time, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.points >= 0 ? "+\(item.points)" : "\(item.points)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(item.points >= 0 ? Theme.addGreen : Theme.deductRed)
        }
        .padding(.vertical, 4)
    }
}
