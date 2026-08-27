import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: HomeStore

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    PageTitle(title: "我的物品", subtitle: "原生版 · 对应 Web v8.25.1")
                    SystemIconComparisonSection()
                    petStatus
                    if !store.dueFoods.isEmpty { expirySection }
                    quickFoods
                    mealPlans
                    activities
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var petStatus: some View {
        HomeCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("宠物状态").font(.headline)
                let litter = store.data.petItems.filter { $0.type == "猫砂" || $0.type == "除臭包" }
                if litter.isEmpty {
                    EmptyState(icon: "pawprint.fill", title: "还没有宠物用品", message: "后续可在宠物页面添加猫砂和补给。")
                } else {
                    ForEach(litter.prefix(3)) { item in
                        HStack {
                            Text(item.name).font(.subheadline.weight(.medium))
                            Spacer()
                            Text("预计 \(item.days) 天").foregroundStyle(HomeTheme.muted).font(.subheadline)
                        }
                    }
                }
            }
        }
    }

    private var expirySection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("临期提醒").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.dueFoods.prefix(3)) { item in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(item.name).font(.subheadline.weight(.semibold))
                            Text(item.expiry).font(.caption).foregroundStyle(HomeTheme.orange)
                        }
                        .frame(width: 130, alignment: .leading)
                        .padding(13)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
    }

    private var quickFoods: some View {
        HomeCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("食品快捷管理").font(.headline)
                let items = store.data.foods.filter(\.quick)
                if items.isEmpty {
                    EmptyState(icon: "refrigerator.fill", title: "还没有快捷食品", message: "在食品详情中可加入首页快捷管理。")
                } else {
                    ForEach(items.prefix(6)) { item in
                        HStack {
                            Text(item.name).font(.subheadline.weight(.medium))
                            Spacer()
                            Text(item.quantity.formatted()).font(.subheadline.weight(.semibold))
                        }
                        if item.id != items.prefix(6).last?.id { Divider() }
                    }
                }
            }
        }
    }

    private var mealPlans: some View {
        Group {
            if !store.data.plans.isEmpty {
                HomeCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("菜谱计划").font(.headline)
                        ForEach(store.data.plans.prefix(3)) { plan in
                            HStack {
                                Text("\(plan.date) · \(plan.meal)").font(.caption).foregroundStyle(HomeTheme.muted)
                                Spacer()
                                Text(store.data.recipes.first(where: { $0.id == plan.recipeId })?.name ?? "未找到菜谱").font(.subheadline.weight(.medium))
                            }
                        }
                    }
                }
            }
        }
    }

    private var activities: some View {
        HomeCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("最近动态").font(.headline)
                if store.data.activities.isEmpty {
                    Text("暂无动态").font(.subheadline).foregroundStyle(HomeTheme.muted)
                } else {
                    ForEach(store.data.activities.prefix(3)) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.text).font(.subheadline)
                            Text(item.time).font(.caption).foregroundStyle(HomeTheme.muted)
                        }
                    }
                }
            }
        }
    }
}

private struct SystemIconComparisonSection: View {
    var body: some View {
        HomeCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("系统图标方案对比")
                        .font(.headline)
                    Text("点击图标可预览选中状态；蓝色为选中，黑色为未选中。")
                        .font(.caption)
                        .foregroundStyle(HomeTheme.muted)
                }

                SystemIconPreviewRow(
                    title: "A · 填充风格",
                    symbols: ["house.fill", "refrigerator.fill", "book.closed.fill", "pawprint.fill", "gearshape.fill"]
                )

                Divider()

                SystemIconPreviewRow(
                    title: "B · 线性风格",
                    symbols: ["house", "refrigerator", "book.closed", "pawprint", "gearshape"]
                )

                Divider()

                SystemIconPreviewRow(
                    title: "C · 语义风格",
                    symbols: ["shippingbox.fill", "basket.fill", "fork.knife", "cat.fill", "slider.horizontal.3"]
                )
            }
        }
    }
}

private struct SystemIconPreviewRow: View {
    private let tabTitles = ["首页", "食品", "菜谱", "宠物", "设置"]

    let title: String
    let symbols: [String]
    @State private var selectedIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(HomeTheme.muted)

            HStack(spacing: 0) {
                ForEach(symbols.indices, id: \.self) { index in
                    Button {
                        selectedIndex = index
                        NativeHaptics.selection()
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: symbols[index])
                                .font(.system(size: 22, weight: .medium))
                                .frame(height: 24)
                            Text(tabTitles[index])
                                .font(.system(size: 9, weight: selectedIndex == index ? .semibold : .medium))
                        }
                        .foregroundStyle(selectedIndex == index ? HomeTheme.blue : .black)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
