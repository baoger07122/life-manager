import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: HomeStore

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    PageTitle(title: "我的物品", subtitle: "原生版 · 对应 Web v8.25.1")
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
