import SwiftUI
import UIKit

private enum RootPreferences {
    static let showsHomeTab = "homeos.navigation.showsHomeTab"
}

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
    @AppStorage(RootPreferences.showsHomeTab) private var showsHomeTab = true
    @State private var selection: RootTab

    init() {
        let showsHomeTab = UserDefaults.standard.object(forKey: RootPreferences.showsHomeTab) as? Bool ?? true
        _selection = State(initialValue: showsHomeTab ? .home : .pet)
        UITabBar.appearance().unselectedItemTintColor = .secondaryLabel
    }

    var body: some View {
        TabView(selection: visibleSelection) {
            if showsHomeTab {
                tab(HomeView(), for: .home)
            }
            tab(FoodView(), for: .food)
            tab(PetView(), for: .pet)
            tab(RecipesView(), for: .recipes)
            tab(SettingsView(isHomeVisible: homeVisibility), for: .settings)
        }
        .tint(HomeTheme.blue)
        .sensoryFeedback(.selection, trigger: selection)
        .onAppear { NativeHaptics.prepareSelection() }
        .onChange(of: showsHomeTab) { _, isVisible in
            if !isVisible && selection == .home {
                selection = .pet
            }
        }
    }

    private var visibleSelection: Binding<RootTab> {
        Binding(
            get: { !showsHomeTab && selection == .home ? .pet : selection },
            set: { newSelection in
                selection = !showsHomeTab && newSelection == .home ? .pet : newSelection
            }
        )
    }

    private var homeVisibility: Binding<Bool> {
        Binding(
            get: { showsHomeTab },
            set: { isVisible in
                if !isVisible && selection == .home {
                    selection = .pet
                }
                showsHomeTab = isVisible
            }
        )
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
