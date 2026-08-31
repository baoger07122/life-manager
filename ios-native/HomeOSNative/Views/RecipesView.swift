import SwiftUI

private struct RecipeScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct RecipesView: View {
    @EnvironmentObject private var store: HomeStore
    @State private var query = ""
    @State private var showSearch = false
    @FocusState private var searchFocused: Bool

    private var recipes: [RecipeItem] {
        guard !query.isEmpty else { return store.data.recipes }
        return store.data.recipes.filter { recipe in
            recipe.name.localizedCaseInsensitiveContains(query)
                || recipe.main.contains { $0.localizedCaseInsensitiveContains(query) }
                || recipe.ingredients.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: RecipeScrollOffsetPreferenceKey.self,
                        value: proxy.frame(in: .named("recipe-scroll")).minY
                    )
                }
                .frame(height: 0)

                LazyVStack(spacing: 10) {
                    PageTitle(title: "菜谱").padding(.bottom, 2)
                    if recipes.isEmpty {
                        HomeCard {
                            EmptyState(
                                icon: "list.clipboard.fill",
                                title: query.isEmpty ? "还没有菜谱" : "没有符合条件的菜谱",
                                message: query.isEmpty ? "我的菜谱、收藏、食材库和三餐计划将在菜谱阶段完整实现。" : "可以更换关键词后重试。"
                            )
                        }
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
                        }
                    }
                }
                .padding(.horizontal, HomeMetrics.pageInset)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .coordinateSpace(name: "recipe-scroll")
            .background(HomeTheme.background)
            .onPreferenceChange(RecipeScrollOffsetPreferenceKey.self) { offset in
                if offset > 44, !showSearch {
                    withAnimation(.easeOut(duration: 0.18)) { showSearch = true }
                    NativeHaptics.selection()
                } else if offset < -100, showSearch, query.isEmpty, !searchFocused {
                    withAnimation(.easeOut(duration: 0.16)) { showSearch = false }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if showSearch { recipeSearchField.transition(.move(edge: .top).combined(with: .opacity)) }
            }
        }
    }

    private var recipeSearchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").foregroundStyle(HomeTheme.muted)
            TextField("搜索菜谱", text: $query)
                .font(HomeTypography.body)
                .focused($searchFocused)
            if !query.isEmpty {
                Button { query = ""; NativeHaptics.tap() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            Button("收起") {
                query = ""
                searchFocused = false
                withAnimation(.easeOut(duration: 0.16)) { showSearch = false }
                NativeHaptics.tap()
            }
            .font(HomeTypography.supporting.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(HomeTheme.line, lineWidth: 0.7) }
        .padding(.horizontal, HomeMetrics.pageInset)
        .padding(.vertical, 6)
        .background(HomeTheme.background.opacity(0.96))
    }
}
