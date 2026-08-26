import SwiftUI

struct RecipesView: View {
    @EnvironmentObject private var store: HomeStore

    var body: some View {
        NavigationStack {
            List {
                if store.data.recipes.isEmpty {
                    EmptyState(icon: "list.clipboard.fill", title: "还没有菜谱", message: "我的菜谱、收藏、食材库和三餐计划将在菜谱阶段完整实现。")
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                } else {
                    ForEach(store.data.recipes) { recipe in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(recipe.name).font(.body.weight(.semibold))
                            Text(recipe.main.joined(separator: "、")).font(.caption).foregroundStyle(HomeTheme.muted)
                        }.padding(.vertical, 5)
                    }
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden).background(HomeTheme.background)
            .navigationTitle("菜谱")
            .toolbar { Button(action: NativeHaptics.tap) { Image(systemName: "plus") } }
        }
    }
}
