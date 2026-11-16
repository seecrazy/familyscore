import SwiftUI
import SwiftData

/// Onboarding（§12.3 五步：品牌欢迎 → 价值轮播 → 创建家庭 → 选模板 → 完成邀请）
struct OnboardingView: View {
    @Environment(\.modelContext) private var context

    @State private var step = 0
    // 创建家庭表单
    @State private var familyName = ""
    @State private var myName = ""
    @State private var myRole: MemberRole = .admin
    @State private var myEmoji = "👩"
    @State private var template: RuleTemplateService.TemplateKind = .three
    @State private var building = false
    @AppStorage("hasCompletedOnboarding") private var done = false
    @AppStorage("currentMemberID") private var currentMemberID: String = ""

    private let roleEmojis: [MemberRole: [String]] = [
        .admin: ["👨", "👩"],
        .child: ["👦", "👧"],
        .elder: ["👵", "👴"],
    ]

    var body: some View {
        VStack {
            TabView(selection: $step) {
                welcomeStep.tag(0)
                valueStep.tag(1)
                createStep.tag(2)
                templateStep.tag(3)
                finishStep.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: step == 1 ? .automatic : .never))
            .animation(.easeInOut, value: step)
        }
        .background(Theme.appBackground)
    }

    // MARK: 1 品牌欢迎

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Image(systemName: "house.fill")
                    .font(.system(size: 84))
                    .foregroundStyle(Theme.brandGradient)
                Image(systemName: "star.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.gold)
                    .offset(x: 38, y: -38)
                    .shadow(color: Theme.gold, radius: 8)
                Image(systemName: "heart.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.deductRed)
                    .offset(x: 0, y: 16)
            }
            .breathing()
            Text("家分宝")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.primary)
            Text("每一分，都是爱")
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    withAnimation { step = 1 }
                } label: {
                    Text("创建我的家庭")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
                }
                Button {
                    startDemo()
                } label: {
                    Label("先体验一下（演示家庭）", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.radiusButton))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    // MARK: 2 价值轮播（3 屏）

    private var valueStep: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("跳过") { withAnimation { step = 2 } }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 20)
            }
            TabView {
                valueCard(icon: "hands.and.sparkles.fill", color: Theme.primary,
                          title: "小行动，大温暖",
                          subtitle: "洗碗、阅读、运动，\n每一件小事都值得被看见")
                valueCard(icon: "trophy.fill", color: Theme.gold,
                          title: "全家一起上榜",
                          subtitle: "日榜、周榜、年榜，\n见证每个人的成长")
                valueCard(icon: "gift.fill", color: Theme.rankBlue,
                          title: "积分换惊喜",
                          subtitle: "攒积分换电影、零食、零花钱，\n爱有回响")
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                withAnimation { step = 2 }
            } label: {
                Text("开始创建家庭")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    private func valueCard(icon: String, color: Color, title: String, subtitle: String) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(color)
                .padding(30)
                .background(color.opacity(0.1), in: Circle())
            Text(title).font(.title.weight(.bold))
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: 3 创建家庭

    private var createStep: some View {
        ScrollView {
            VStack(spacing: 22) {
                stepHeader("建立你的家庭", "第 3 步 · 共 5 步")
                VStack(alignment: .leading, spacing: 8) {
                    Text("家庭名称").font(.caption).foregroundStyle(.secondary)
                    TextField("如：王家", text: $familyName)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("我是").font(.caption).foregroundStyle(.secondary)
                    Picker("角色", selection: $myRole) {
                        Text("家长").tag(MemberRole.admin)
                        Text("孩子").tag(MemberRole.child)
                        Text("长辈").tag(MemberRole.elder)
                    }
                    .pickerStyle(.segmented)
                    HStack(spacing: 12) {
                        ForEach(roleEmojis[myRole] ?? ["🙂"], id: \.self) { e in
                            Button { myEmoji = e } label: {
                                Text(e).font(.title)
                                    .padding(10)
                                    .background(myEmoji == e ? Theme.primary.opacity(0.15) : .clear,
                                                in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("我的昵称").font(.caption).foregroundStyle(.secondary)
                    TextField("如：妈妈", text: $myName)
                        .textFieldStyle(.roundedBorder)
                }
                nextButton("下一步", enabled: !familyName.isEmpty && !myName.isEmpty) {
                    withAnimation { step = 3 }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
        }
    }

    // MARK: 4 选择模板

    private var templateStep: some View {
        ScrollView {
            VStack(spacing: 18) {
                stepHeader("挑一套规则开始", "第 4 步 · 随时能改")
                ForEach(RuleTemplateService.TemplateKind.allCases) { kind in
                    Button {
                        Haptics.light()
                        template = kind
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(kind.rawValue)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(kind.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: template == kind ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(Theme.primary)
                        }
                        .padding(14)
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(template == kind ? Theme.primary : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
                nextButton("开始使用", enabled: true) {
                    createFamily()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
        }
    }

    // MARK: 5 完成

    private var finishStep: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "party.popper.fill")
                .font(.system(size: 60))
                .foregroundStyle(Theme.gold)
            Text("家庭创建成功！")
                .font(.title.weight(.bold))
            Text("把家分宝分享给家人\n一起把家变得更好")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            VStack(spacing: 12) {
                Button {
                    shareInvite()
                } label: {
                    Label("邀请家人（复制邀请语）", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: Theme.radiusButton))
                }
                Button {
                    enterApp()
                } label: {
                    Text("先逛逛，稍后邀请 →")
                        .font(.subheadline)
                        .foregroundStyle(Theme.primary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    // MARK: 动作

    private func createFamily() {
        building = true
        let (family, owner) = FamilyService.createFamily(
            name: familyName, myName: myName, myRole: myRole, myEmoji: myEmoji,
            template: template, context: context)
        currentMemberID = owner.id.uuidString
        building = false
        Haptics.success()
        withAnimation { step = 4 }
    }

    private func startDemo() {
        let (family, members) = DemoData.build(context: context)
        // 以妈妈身份体验（家长视角功能最全）
        currentMemberID = members.first { $0.name == "妈妈" }?.id.uuidString ?? members[0].id.uuidString
        Haptics.success()
        done = true
    }

    private func enterApp() {
        done = true
    }

    private func shareInvite() {
        UIPasteboard.general.string =
            "我在「家分宝」创建了\(familyName.isEmpty ? "我们家的" : "「\(familyName)」")积分小天地，一起把家变得更好 🏠✨"
        enterApp()
    }

    // MARK: 小件

    private func stepHeader(_ title: String, _ caption: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.title2.weight(.bold))
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func nextButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(enabled ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color(hex: 0xD1D1D6)),
                            in: RoundedRectangle(cornerRadius: Theme.radiusButton))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Logo 呼吸浮动（±4pt / 3s，§12.3）
struct BreathingModifier: ViewModifier {
    @State private var up = false
    func body(content: Content) -> some View {
        content
            .offset(y: up ? -4 : 4)
            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: up)
            .onAppear { up = true }
    }
}

extension View {
    func breathing() -> some View { modifier(BreathingModifier()) }
}
