import SwiftUI
import UIKit

enum RootTab: String, CaseIterable, Identifiable {
    case home, food, pet, recipes, settings

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

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .food: "fork.knife"
        case .recipes: "list.bullet.clipboard.fill"
        case .pet: "cat.fill"
        case .settings: "gearshape.fill"
        }
    }
}

struct RootView: View {
    @State private var selection: RootTab = .home

    init() {
        UITabBar.appearance().unselectedItemTintColor = .black
    }

    var body: some View {
        TabView(selection: $selection) {
            tab(HomeView(), for: .home)
            tab(FoodView(), for: .food)
            tab(PetView(), for: .pet)
            tab(RecipesView(), for: .recipes)
            tab(SettingsView(), for: .settings)
        }
        .tint(HomeTheme.blue)
        .onChange(of: selection) { _, _ in
            NativeHaptics.selection()
        }
    }

    private func tab<Content: View>(_ content: Content, for tab: RootTab) -> some View {
        content
            .tag(tab)
            .tabItem {
                Image(systemName: tab.symbol)
                Text(tab.title)
            }
    }
}
