import SwiftUI

enum RootTab: String, CaseIterable, Identifiable {
    case home, food, recipes, pet, settings

    var id: String { rawValue }

    var index: Int {
        RootTab.allCases.firstIndex(of: self) ?? 0
    }

    var title: String {
        switch self {
        case .home: "首页"
        case .food: "食品"
        case .recipes: "菜谱"
        case .pet: "宠物"
        case .settings: "设置"
        }
    }

    var asset: String { "nav-\(rawValue)" }
}

struct RootView: View {
    @State private var selection: RootTab = .home

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                HomeTheme.background.ignoresSafeArea()

                Group {
                    switch selection {
                    case .home: HomeView()
                    case .food: FoodView()
                    case .recipes: RecipesView()
                    case .pet: PetView()
                    case .settings: SettingsView()
                    }
                }
                .id(selection)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(x: 5)),
                    removal: .opacity
                ))
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: 78)
                }

                NativeBottomBar(selection: $selection)
                    .frame(width: min(398, proxy.size.width - 28))
                    .frame(height: 72)
                    .padding(.bottom, max(10, proxy.safeAreaInsets.bottom - 20))
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

struct NativeBottomBar: View {
    @Binding var selection: RootTab
    @State private var pillIndex = RootTab.home.index
    @State private var pillStretch: CGFloat = 1
    @State private var animationRevision = 0

    var body: some View {
        GeometryReader { proxy in
            let itemWidth = (proxy.size.width - 12) / CGFloat(RootTab.allCases.count)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 29, style: .continuous)
                    .fill(Color(red: 226 / 255, green: 228 / 255, blue: 234 / 255).opacity(0.72))
                    .overlay {
                        RoundedRectangle(cornerRadius: 29, style: .continuous)
                            .stroke(.white.opacity(0.86), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.07), radius: 8, y: 2)
                    .frame(width: itemWidth, height: 62)
                    .scaleEffect(x: pillStretch, y: 1)
                    .offset(x: 6 + itemWidth * CGFloat(pillIndex), y: 5)

                HStack(spacing: 0) {
                    ForEach(RootTab.allCases) { tab in
                        Button {
                            select(tab)
                        } label: {
                            VStack(spacing: 4) {
                                Image(selection == tab ? "\(tab.asset)-selected" : tab.asset)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 23, height: 23)

                                Text(tab.title)
                                    .font(.system(size: 10, weight: selection == tab ? .semibold : .medium))
                                    .lineLimit(1)
                                    .foregroundStyle(selection == tab ? HomeTheme.blue : .black)
                            }
                            .frame(width: itemWidth, height: 62)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .offset(x: 6, y: 5)
            }
            .frame(height: 72)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .stroke(.white.opacity(0.92), lineWidth: 1)
            }
            .shadow(color: Color(red: 31 / 255, green: 41 / 255, blue: 55 / 255).opacity(0.13), radius: 15, y: 6)
        }
        .frame(height: 72)
        .onAppear {
            pillIndex = selection.index
        }
    }

    private func select(_ tab: RootTab) {
        guard selection != tab else { return }

        animationRevision += 1
        let revision = animationRevision
        NativeHaptics.selection()

        withAnimation(.easeOut(duration: 0.075)) {
            pillStretch = 1.16
        }

        withAnimation(.easeOut(duration: 0.21)) {
            selection = tab
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.075) {
            guard animationRevision == revision else { return }
            withAnimation(.timingCurve(0.18, 0.85, 0.25, 1, duration: 0.22)) {
                pillIndex = tab.index
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.295) {
            guard animationRevision == revision else { return }
            withAnimation(.easeOut(duration: 0.125)) {
                pillStretch = 1
            }
        }
    }
}
