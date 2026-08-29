import SwiftUI

struct RecipesView: View {
    @EnvironmentObject private var store: HomeStore
    @State private var search = ""

    private var recipes: [RecipeItem] {
        search.isEmpty
            ? store.data.recipes
            : store.data.recipes.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PageTitle(title: "菜谱")
                    .padding(.horizontal, HomeMetrics.pageInset)
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                List {
                if recipes.isEmpty {
                    EmptyState(
                        icon: "list.clipboard.fill",
                        title: search.isEmpty ? "还没有菜谱" : "没有搜索结果",
                        message: search.isEmpty ? "我的菜谱、收藏、食材库和三餐计划将在菜谱阶段完整实现。" : "请尝试其他菜谱名称。"
                    )
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                } else {
                    ForEach(recipes) { recipe in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(recipe.name).font(.body.weight(.semibold))
                            Text(recipe.main.joined(separator: "、")).font(.caption).foregroundStyle(HomeTheme.muted)
                        }.padding(.vertical, 5)
                    }
                }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .searchable(
                    text: $search,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: "搜索菜谱"
                )
            }
            .background(HomeTheme.background)
        }
    }
}
