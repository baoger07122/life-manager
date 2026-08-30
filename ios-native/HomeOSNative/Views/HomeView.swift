import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: HomeStore

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: HomeMetrics.sectionSpacing) {
                    PageTitle(title: "我的物品")
                    petStatusSection
                    if !store.dueFoods.isEmpty { expirySection }
                    quickFoodsSection
                    mealPlansSection
                    activitiesSection
                }
                .padding(.horizontal, HomeMetrics.pageInset)
                .padding(.top, 18)
                .padding(.bottom, 12)
            }
            .background(HomeTheme.background)
            .scrollIndicators(.hidden)
        }
    }

    private var petStatusSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("宠物状态").font(HomeTypography.sectionTitle)
                Spacer()
                NavigationLink("查看全部") { PetLitterManagementView() }
                    .font(HomeTypography.supporting.weight(.semibold))
            }
            HomeCard(padding: 0) {
                VStack(spacing: 0) {
                    if let prediction = store.litterPrediction {
                        HStack(spacing: 18) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("猫砂余量").font(HomeTypography.body).foregroundStyle(HomeTheme.muted)
                                Text(prediction.hasEnoughData ? "\(prediction.daysRemaining ?? 0) 天" : "数据积累中")
                                    .font(HomeTypography.metric)
                            Text(prediction.shouldRefill ? "建议尽快补充" : "预计 \(HomeDateText.display(prediction.thresholdDate)) 前补充")
                                    .font(HomeTypography.supporting)
                                    .foregroundStyle(prediction.shouldRefill ? HomeTheme.orange : HomeTheme.muted)
                            }
                            Spacer()
                            NavigationLink {
                                PetLitterManagementView()
                            } label: {
                                statusRing(prediction)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(HomePressButtonStyle())
                            .simultaneousGesture(TapGesture().onEnded { NativeHaptics.tap() })
                            .accessibilityLabel("进入补猫砂和换猫砂")
                        }
                        .padding(16)
                    } else {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("猫砂余量").font(HomeTypography.body).foregroundStyle(HomeTheme.muted)
                                Text("暂无数据").font(HomeTypography.sectionTitle)
                                Text("点击“查看全部”进行初始化").font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                            }
                            Spacer()
                            Image(systemName: "gauge.with.dots.needle.33percent")
                                .font(.system(size: 30)).foregroundStyle(HomeTheme.muted)
                        }
                        .padding(16)
                    }
                    Divider()
                    HStack(spacing: 0) {
                        petStockMetric(title: categoryName(id: "pet-food-1", fallback: "主食罐"), items: petItems(categoryID: "pet-food-1"))
                        Divider().frame(height: 58)
                        petStockMetric(title: categoryName(id: "pet-food-3", fallback: "零食罐"), items: petItems(categoryID: "pet-food-3"))
                        Divider().frame(height: 58)
                        petStockMetric(title: "矿砂", items: mineralLitterItems)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var expirySection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HomeSectionHeader(title: "临期提醒")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.dueFoods.prefix(6)) { item in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(item.name).font(HomeTypography.cardTitle)
                            Text(HomeDateText.display(item.expiry)).font(HomeTypography.supporting).foregroundStyle(HomeTheme.orange)
                        }
                        .frame(width: 130, alignment: .leading)
                        .padding(13)
                        .background(HomeTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(HomeTheme.line, lineWidth: 0.8) }
                    }
                }
            }
        }
    }

    private var quickFoodsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HomeSectionHeader(title: "食品快捷管理")
            HomeCard {
                let items = store.data.foods.filter(\.quick)
                if items.isEmpty {
                    EmptyState(icon: "refrigerator.fill", title: "还没有快捷食品", message: "在食品详情中可加入首页快捷管理。")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(items.prefix(6).enumerated()), id: \.element.id) { index, item in
                            HStack {
                                Text(item.name).font(HomeTypography.body.weight(.medium))
                                Spacer()
                                Text(item.quantity.formatted()).font(HomeTypography.body.weight(.semibold))
                            }
                            .frame(minHeight: 42)
                            if index < min(items.count, 6) - 1 { Divider() }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var mealPlansSection: some View {
        if !store.data.plans.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                HomeSectionHeader(title: "菜谱计划")
                HomeCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(store.data.plans.prefix(3)) { plan in
                            HStack {
                                Text("\(HomeDateText.display(plan.date)) · \(plan.meal)").font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                                Spacer()
                                Text(store.data.recipes.first(where: { $0.id == plan.recipeId })?.name ?? "未找到菜谱").font(HomeTypography.body.weight(.medium))
                            }
                        }
                    }
                }
            }
        }
    }

    private var activitiesSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HomeSectionHeader(title: "最近动态")
            HomeCard {
                if store.data.activities.isEmpty {
                    Text("暂无动态").font(HomeTypography.body).foregroundStyle(HomeTheme.muted).frame(minHeight: 42)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(store.data.activities.prefix(3)) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.text).font(HomeTypography.body)
                                Text(item.time).font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                            }
                        }
                    }
                }
            }
        }
    }

    private func statusRing(_ prediction: LitterPrediction) -> some View {
        ZStack {
            Circle().stroke(HomeTheme.blue.opacity(0.16), lineWidth: 8)
            Circle()
                .trim(from: 0, to: prediction.progress)
                .stroke(prediction.shouldRefill ? HomeTheme.orange : HomeTheme.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((prediction.progress * 100).rounded()))%")
                .font(HomeTypography.cardTitle)
                .foregroundStyle(prediction.shouldRefill ? HomeTheme.orange : HomeTheme.blue)
        }
        .frame(width: 76, height: 76)
    }

    private func petStockMetric(title: String, items: [PetItem]) -> some View {
        VStack(spacing: 5) {
            Text(title).font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
            Text(stockSummary(items)).font(HomeTypography.body.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
    }

    private func categoryName(id: String, fallback: String) -> String {
        for root in store.categories(for: .pet) {
            if let category = store.categories(for: .pet, parentID: root.id).first(where: { $0.id == id }) {
                return category.name
            }
        }
        return fallback
    }

    private func petItems(categoryID: String) -> [PetItem] {
        let name = categoryName(id: categoryID, fallback: "")
        return store.activePetItems.filter { $0.resolvedSecondaryCategory == name }
    }

    private var mineralLitterItems: [PetItem] {
        store.activePetItems.filter {
            let secondary = $0.resolvedSecondaryCategory.trimmingCharacters(in: .whitespacesAndNewlines)
            let kind = ($0.litterKind ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return secondary == "矿砂" || (secondary == "猫砂" && kind == "矿砂")
        }
    }

    private func stockSummary(_ items: [PetItem]) -> String {
        guard !items.isEmpty else { return "0" }
        let units = Set(items.map(\.unit))
        guard units.count == 1, let unit = units.first else { return "\(items.count)种" }
        let total = items.reduce(0) { $0 + store.petInventory(for: $1.id) }
        return "\(total.formatted())\(unit)"
    }
}
