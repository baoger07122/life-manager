import SwiftUI

enum RootTab: String, CaseIterable, Identifiable {
    case home, food, recipes, pet, settings
    var id: String { rawValue }
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
        ZStack {
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
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            NativeBottomBar(selection: $selection)
                .padding(.horizontal, 14)
                .padding(.top, 5)
        }
    }
}

struct NativeBottomBar: View {
    @Binding var selection: RootTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(RootTab.allCases) { tab in
                Button {
                    guard selection != tab else { return }
                    NativeHaptics.selection()
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(selection == tab ? "\(tab.asset)-selected" : tab.asset)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 25, height: 25)
                        Text(tab.title)
                            .font(.system(size: 11.5, weight: selection == tab ? .semibold : .regular))
                            .foregroundStyle(selection == tab ? HomeTheme.blue : .black)
                    }
                    .frame(maxWidth: .infinity, minHeight: 57)
                    .background(selection == tab ? Color(red: 0.94, green: 0.95, blue: 0.97) : .clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white.opacity(0.78), lineWidth: 1))
        .shadow(color: .black.opacity(0.11), radius: 18, y: 7)
    }
}
