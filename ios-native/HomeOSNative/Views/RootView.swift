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
        TabView(selection: $selection) {
            tab(HomeView(), for: .home)
            tab(FoodView(), for: .food)
            tab(RecipesView(), for: .recipes)
            tab(PetView(), for: .pet)
            tab(SettingsView(), for: .settings)
        }
        .tint(HomeTheme.blue)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onChange(of: selection) { _, _ in
            NativeHaptics.selection()
        }
    }

    private func tab<Content: View>(_ content: Content, for tab: RootTab) -> some View {
        content
            .tag(tab)
            .tabItem {
                Image(tab.asset)
                    .renderingMode(.template)
                Text(tab.title)
            }
    }
}
