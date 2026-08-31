import SwiftUI

struct RecipesView: View {
    @EnvironmentObject private var store: HomeStore

    private var recipes: [RecipeItem] {
        store.data.recipes
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
                    EmptyState(icon: "list.clipboard.fill", title: "还没有菜谱", message: "我的菜谱、收藏、食材库和三餐计划将在菜谱阶段完整实现。")
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                } else {
                    ForEach(recipes) { recipe in
                        HomeCard(padding: 14) {
                            HStack(spacing: 12) {
                                Image(systemName: "fork.knife")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(HomeTheme.blue)
                                    .frame(width: 38, height: 38)
                                    .background(HomeTheme.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(recipe.name).font(HomeTypography.cardTitle)
                                    Text(recipe.main.joined(separator: "、"))
                                        .font(HomeTypography.supporting)
                                        .foregroundStyle(HomeTheme.muted)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .listRowInsets(.init(top: 5, leading: HomeMetrics.pageInset, bottom: 5, trailing: HomeMetrics.pageInset))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 1)
                .scrollContentBackground(.hidden)
            }
            .background(HomeTheme.background)
        }
    }
}
