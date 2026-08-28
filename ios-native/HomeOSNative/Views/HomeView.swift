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
                Text("宠物状态").font(HomeTypography.sectionTitle)
                let petFoods = store.activePetItems.filter { $0.resolvedPrimaryCategory == "宠物食品" }
                if let prediction = store.litterPrediction {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("猫砂盆预计余量").font(HomeTypography.cardTitle)
                            Spacer()
                            Text("\(prediction.currentAmount.formatted(.number.precision(.fractionLength(1)))) kg")
                                .font(HomeTypography.body.weight(.semibold))
                        }
                        ProgressView(value: prediction.progress)
                            .tint(prediction.shouldRefill ? HomeTheme.orange : HomeTheme.blue)
                        HStack {
                            Text(prediction.hasEnoughData ? "预计可用 \(prediction.daysRemaining ?? 0) 天" : "预计可用天数：数据不足")
                            Spacer()
                            Text(prediction.shouldRefill ? "建议补充猫砂" : "预计 \(prediction.thresholdDate ?? "数据不足") 达到 40%")
                                .foregroundStyle(prediction.shouldRefill ? HomeTheme.orange : HomeTheme.muted)
                        }
                        .font(HomeTypography.supporting)
                    }
                }
                if petFoods.isEmpty && store.litterPrediction == nil {
                    EmptyState(icon: "pawprint.fill", title: "还没有宠物用品", message: "可前往宠物页面添加猫砂和宠物食品。")
                } else {
                    ForEach(petFoods.prefix(3)) { item in
                        HStack {
                            Text(item.name).font(HomeTypography.body.weight(.medium))
                            Spacer()
                            Text("\(store.petInventory(for: item.id).formatted())\(item.unit)").foregroundStyle(HomeTheme.muted).font(HomeTypography.body)
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
