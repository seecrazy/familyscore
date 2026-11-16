import SwiftUI

/// 领奖台 Top3（§8.2：2-1-3 布局，冠军放大 + 金色光环 + 皇冠）
struct PodiumView: View {
    let top3: [(member: Member, entry: RankEntry)]

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            podiumSlot(index: 1, medal: "🥈", color: Color(white: 0.72), scale: 0.88, bar: 64)
            podiumSlot(index: 0, medal: "🥇", color: Theme.gold, scale: 1.12, bar: 92)
            podiumSlot(index: 2, medal: "🥉", color: Color(red: 0.82, green: 0.60, blue: 0.42), scale: 0.88, bar: 48)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func podiumSlot(index: Int, medal: String, color: Color, scale: CGFloat, bar: CGFloat) -> some View {
        if index < top3.count {
            let m = top3[index].member
            let e = top3[index].entry
            VStack(spacing: 6) {
                Text(medal).font(.caption)
                ZStack {
                    Circle().fill(color.opacity(0.18)).padding(-6) // 光环
                    MemberAvatarView(member: m, rank: e.rank, size: 56 * scale)
                }
                Text(m.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text("\(e.score)")
                    .font(.system(.callout, design: .rounded, weight: .bold).monospacedDigit())
                Capsule()
                    .fill(color.opacity(0.85))
                    .frame(width: 64, height: 6)
                    .frame(height: bar, alignment: .bottom) // 台阶感由底部留白撑出
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement()
            .accessibilityLabel("第\(e.rank)名 \(m.name)，\(e.score) 分")
        } else {
            Color.clear.frame(maxWidth: .infinity).frame(height: 150)
        }
    }
}

/// 排名列表行（§8.2：含环比；垫底鼓励文案由父视图处理）
struct RankRowView: View {
    let member: Member
    let entry: RankEntry
    var isMe: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Text("\(entry.rank)")
                .font(.system(.body, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(entry.rank <= 3 ? Theme.gold : .secondary)
                .frame(width: 28)
            MemberAvatarView(member: member, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.name).font(.body.weight(.medium))
                    if isMe {
                        Text("我").font(.caption2.weight(.bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.primary.opacity(0.12), in: Capsule())
                            .foregroundStyle(Theme.primary)
                    }
                    LevelBadge(level: member.level)
                }
                Text("\(member.cumulativeScore) 累计")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.score)")
                    .font(.system(.headline, design: .rounded, weight: .bold).monospacedDigit())
                deltaView
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(isMe ? Theme.primary.opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var deltaView: some View {
        if let d = entry.delta {
            HStack(spacing: 2) {
                Image(systemName: d < 0 ? "arrow.up" : d > 0 ? "arrow.down" : "minus")
                    .font(.caption2.weight(.bold))
                Text("\(abs(d))").font(.caption2.weight(.semibold).monospacedDigit())
            }
            .foregroundStyle(d < 0 ? Theme.addGreen : d > 0 ? Theme.deductRed : .secondary)
            .accessibilityLabel(d < 0 ? "上升 \(abs(d)) 位" : d > 0 ? "下降 \(d) 位" : "持平")
        } else {
            Text("—").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
