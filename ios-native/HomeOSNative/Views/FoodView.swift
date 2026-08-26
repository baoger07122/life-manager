import SwiftUI

struct FoodView: View {
    @EnvironmentObject private var store: HomeStore
    @State private var search = ""

    private var foods: [FoodItem] {
        search.isEmpty ? store.data.foods : store.data.foods.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                if foods.isEmpty {
                    EmptyState(icon: "refrigerator.fill", title: search.isEmpty ? "还没有食品" : "没有搜索结果", message: "食品新增、详情和库存操作将在食品模块阶段完整实现。")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(foods) { item in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 9).fill(HomeTheme.background).frame(width: 42, height: 42).overlay(Text(item.icon).font(.title3))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name).font(.body.weight(.semibold))
                                Text("\(item.category) · \(item.location)").font(.caption).foregroundStyle(HomeTheme.muted)
                            }
                            Spacer()
                            Text("\(item.quantity.formatted())\(item.unit)").font(.subheadline.weight(.semibold))
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(HomeTheme.background)
            .navigationTitle("食品")
            .searchable(text: $search, prompt: "搜索食品")
            .toolbar { Button(action: NativeHaptics.tap) { Image(systemName: "plus") } }
        }
    }
}
