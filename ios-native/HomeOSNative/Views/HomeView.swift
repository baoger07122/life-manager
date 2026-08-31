import SwiftUI

private enum HomeActivityFilter: String, CaseIterable, Identifiable {
    case all, food, pet, recipe
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "全部"
        case .food: "食品"
        case .pet: "宠物"
        case .recipe: "菜谱"
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var store: HomeStore
    @State private var activityFilter: HomeActivityFilter = .all

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
            .alert("提示", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
                Button("知道了") { store.lastError = nil }
            } message: { Text(store.lastError ?? "") }
        }
    }

    private var petStatusSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("宠物状态").font(HomeTypography.sectionTitle)
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
                        NavigationLink { PetLitterManagementView() } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("猫砂余量").font(HomeTypography.body).foregroundStyle(HomeTheme.muted)
                                    Text("暂无数据").font(HomeTypography.sectionTitle).foregroundStyle(HomeTheme.ink)
                                    Text("点击进入补猫砂和换猫砂").font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                                }
                                Spacer()
                                Image(systemName: "gauge.with.dots.needle.33percent")
                                    .font(.system(size: 30)).foregroundStyle(HomeTheme.muted)
                            }
                            .padding(16)
                        }
                        .buttonStyle(HomePressButtonStyle())
                        .simultaneousGesture(TapGesture().onEnded { NativeHaptics.tap() })
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
            HStack(alignment: .firstTextBaseline) {
                Text("临期提醒").font(HomeTypography.sectionTitle)
                Spacer()
                if store.dueFoods.count > 3 {
                    NavigationLink("查看更多") { FoodExpiryListView() }
                        .font(HomeTypography.supporting.weight(.semibold))
                }
            }
            HStack(spacing: 8) {
                ForEach(store.dueFoods.prefix(3)) { item in
                    NavigationLink { FoodDetailView(itemID: item.id) } label: {
                        HStack(spacing: 7) {
                            FoodItemThumbnail(item: item, size: 30)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(HomeTypography.supporting.weight(.semibold))
                                    .foregroundStyle(HomeTheme.ink)
                                    .lineLimit(1)
                                Text(HomeDateText.display(item.expiry))
                                    .font(.system(size: 10))
                                    .foregroundStyle(HomeTheme.orange)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .frame(height: 58)
                        .background(HomeTheme.card, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(HomeTheme.line.opacity(0.82), lineWidth: 0.7)
                        }
                    }
                    .buttonStyle(HomePressButtonStyle())
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var quickFoodsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HomeSectionHeader(title: "食品快捷管理")
            HomeCard(padding: 0) {
                let items = store.data.foods.filter(\.quick)
                if items.isEmpty {
                    EmptyState(icon: "refrigerator.fill", title: "还没有快捷食品", message: "在食品详情中可加入首页快捷管理。")
                        .padding(.vertical, 12)
                } else {
                    FoodInventoryRows(items: Array(items.prefix(6)))
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
            HomeCard(padding: 0) {
                VStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 22) {
                            ForEach(HomeActivityFilter.allCases) { filter in
                                Button {
                                    activityFilter = filter
                                    NativeHaptics.selection()
                                } label: {
                                    HomeUnderlineTab(title: filter.title, selected: activityFilter == filter, prominent: true)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                    .frame(height: 48)
                    Divider()
                    if filteredActivities.isEmpty {
                        Text("暂无动态")
                            .font(HomeTypography.body)
                            .foregroundStyle(HomeTheme.muted)
                            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                            .padding(.horizontal, 14)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredActivities.prefix(5)) { item in
                                activityLink(item)
                                if item.id != filteredActivities.prefix(5).last?.id { Divider().padding(.leading, 52) }
                            }
                        }
                    }
                }
            }
        }
    }

    private var filteredActivities: [ActivityItem] {
        store.data.activities.filter { item in
            activityFilter == .all || item.type == activityFilter.rawValue
        }
    }

    @ViewBuilder
    private func activityLink(_ item: ActivityItem) -> some View {
        if item.type == "food", let targetID = item.targetId,
           store.data.foods.contains(where: { $0.id == targetID }) {
            NavigationLink { FoodDetailView(itemID: targetID) } label: { activityRow(item) }
                .buttonStyle(.plain)
        } else if item.type == "pet", let targetID = item.targetId,
                  store.activePetItems.contains(where: { $0.id == targetID }) {
            NavigationLink { PetItemDetailView(itemID: targetID) } label: { activityRow(item) }
                .buttonStyle(.plain)
        } else {
            activityRow(item)
        }
    }

    private func activityRow(_ item: ActivityItem) -> some View {
        HStack(spacing: 11) {
            Image(systemName: activityIcon(item))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(activityColor(item))
                .frame(width: 30, height: 30)
                .background(activityColor(item).opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.text).font(.system(size: 14, weight: .medium)).foregroundStyle(HomeTheme.ink).lineLimit(1)
                Text(activityDetails(item)).font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            if item.targetId != nil {
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private func activityDetails(_ item: ActivityItem) -> String {
        var parts = [item.time]
        if let quantity = item.quantity, let unit = item.unit {
            parts.append("\(quantity.formatted(.number.precision(.fractionLength(0...2))))\(unit)")
        }
        if let totalPrice = item.totalPrice, totalPrice > 0 {
            parts.append("¥\(totalPrice.formatted(.number.precision(.fractionLength(2))))")
        }
        return parts.joined(separator: " · ")
    }

    private func activityIcon(_ item: ActivityItem) -> String {
        if item.action == "入库" { return "arrow.down.circle.fill" }
        if item.action == "出库" { return "arrow.up.circle.fill" }
        switch item.type {
        case "food": return "refrigerator.fill"
        case "pet": return "pawprint.fill"
        case "recipe": return "list.bullet.clipboard.fill"
        default: return "clock.fill"
        }
    }

    private func activityColor(_ item: ActivityItem) -> Color {
        item.action == "出库" ? HomeTheme.orange : HomeTheme.blue
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
        NavigationLink {
            if items.count == 1, let item = items.first {
                PetItemDetailView(itemID: item.id)
            } else {
                PetStockItemsView(title: title, itemIDs: items.map(\.id))
            }
        } label: {
            VStack(spacing: 5) {
                Text(title).font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                Text(stockSummary(items)).font(HomeTypography.body.weight(.semibold)).foregroundStyle(HomeTheme.ink)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(HomePressButtonStyle())
        .simultaneousGesture(TapGesture().onEnded { NativeHaptics.tap() })
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

private struct PetStockItemsView: View {
    @EnvironmentObject private var store: HomeStore
    let title: String
    let itemIDs: [String]

    private var items: [PetItem] { store.activePetItems.filter { itemIDs.contains($0.id) } }

    var body: some View {
        List(items) { item in
            NavigationLink { PetItemDetailView(itemID: item.id) } label: {
                HStack(spacing: 11) {
                    PetStoredImage(reference: item.image ?? "")
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.displayTitle).font(HomeTypography.cardTitle)
                        Text("\(item.spec) · \(store.petInventory(for: item.id).formatted())\(item.unit)")
                            .font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
