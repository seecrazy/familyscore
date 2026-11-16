import SwiftUI

/// 成员头像：emoji + 等级描边；排名模式可加金环与皇冠（§10 MemberAvatar）
struct MemberAvatarView: View {
    let member: Member
    var rank: Int? = nil
    var size: CGFloat = 44

    private var ringColor: Color {
        switch rank {
        case 1: return Theme.gold
        case 2: return Color(white: 0.72)
        case 3: return Color(red: 0.78, green: 0.55, blue: 0.36)
        default: return Theme.primary.opacity(0.25 + Double(min(member.level, 10)) * 0.05)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ZStack {
                Circle()
                    .fill(Theme.cardBackground)
                    .frame(width: size, height: size)
                    .overlay(
                        Circle().stroke(ringColor, lineWidth: rank != nil ? 3 : 2))
                Text(member.emoji)
                    .font(.system(size: size * 0.5))
            }
            if rank == 1 {
                Image(systemName: "crown.fill")
                    .font(.system(size: size * 0.32))
                    .foregroundStyle(Theme.gold)
                    .offset(y: -size * 0.34)
            }
        }
        .accessibilityLabel("\(member.name)，等级 \(member.level)")
    }
}

/// 等级徽章（小圆点 + Lv）
struct LevelBadge: View {
    let level: Int
    var body: some View {
        Text("Lv.\(level)")
            .font(.caption2.weight(.bold).monospacedDigit())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Theme.primary.opacity(0.15), in: Capsule())
            .foregroundStyle(Theme.primary)
    }
}
