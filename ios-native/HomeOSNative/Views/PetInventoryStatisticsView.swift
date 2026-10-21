import SwiftUI

struct PetInventoryStatisticsView: View {
    @EnvironmentObject private var store: HomeStore
    let capabilityKey: String

    private var rootCategory: ManagedCategory? { store.petRootCategory(capabilityKey: capabilityKey) }
    private var snapshot: PetInventoryStatisticsSnapshot {
        PetInventoryStatisticsSnapshot.make(store: store, capabilityKey: capabilityKey)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: HomeMetrics.sectionSpacing) {
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("库存总览")
                    overviewCard
                }
                if snapshot.categories.isEmpty {
                    HomeCard {
                        EmptyState(icon: "shippingbox.fill", title: "暂无当前库存", message: "新增库存后会自动按分类和规格汇总。")
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("分类明细")
                        ForEach(snapshot.categories) { category in
                            categoryCard(category)
                        }
                    }
                }
            }
            .padding(HomeMetrics.pageInset)
            .padding(.bottom, 96)
        }
        .background(HomeTheme.background)
        .navigationTitle("\(rootCategory?.name ?? "宠物物品")统计")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var overviewCard: some View {
        HomeCard(padding: 14) {
            VStack(spacing: 12) {
                HStack(spacing: 0) {
                    overviewMetric(
                        icon: "shippingbox.fill",
                        title: "库存数量",
                        value: quantity(snapshot.totalQuantity),
                        suffix: "件"
                    )
                    if snapshot.totalMassGrams > 0 || snapshot.totalVolumeMilliliters > 0 {
                        Divider().frame(height: 52)
                        overviewMetric(
                            icon: snapshot.totalMassGrams > 0 ? "scalemass.fill" : "drop.fill",
                            title: "总净含量",
                            value: netContent,
                            suffix: ""
                        )
                    }
                }

                Divider()

                HStack(spacing: 10) {
                    statisticIcon("dollarsign.circle.fill", size: 38, symbolSize: 17)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(snapshot.valuation.title)
                            .font(HomeTypography.supporting)
                            .foregroundStyle(HomeTheme.muted)
                        Text(snapshot.valuation.amountText)
                            .font(.system(size: 21, weight: .semibold, design: .rounded))
                            .foregroundStyle(HomeTheme.blue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                        Text("按当前库存数量 × 入库加权单价估算")
                            .font(.system(size: 11))
                            .foregroundStyle(HomeTheme.muted)
                        if let detailText = snapshot.valuation.detailText {
                            Text(detailText)
                                .font(.system(size: 11))
                                .foregroundStyle(HomeTheme.orange)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(HomeTypography.sectionTitle)
            .foregroundStyle(HomeTheme.ink)
            .padding(.leading, 2)
    }

    private func overviewMetric(icon: String, title: String, value: String, suffix: String) -> some View {
        HStack(spacing: 10) {
            statisticIcon(icon, size: 38, symbolSize: 17)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(HomeTypography.supporting)
                    .foregroundStyle(HomeTheme.muted)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                        .foregroundStyle(HomeTheme.blue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                    if !suffix.isEmpty {
                        Text(suffix).font(HomeTypography.supporting).foregroundStyle(HomeTheme.blue)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }

    private func categoryCard(_ category: PetInventoryCategorySummary) -> some View {
        HomeCard(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    statisticIcon(categoryIcon(for: category.name), size: 32, symbolSize: 15)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(HomeTheme.ink)
                        Text(category.packageSummary)
                            .font(HomeTypography.supporting)
                            .foregroundStyle(HomeTheme.muted)
                    }
                    Spacer()
                    Text("共\(quantity(category.totalQuantity))件")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(HomeTheme.blue)
                }
                .padding(.horizontal, HomeMetrics.cardPadding)
                .frame(minHeight: 58)
                .background(HomeTheme.blue.opacity(0.045))

                HStack {
                    Text("规格")
                    Spacer()
                    Text("库存")
                }
                .font(HomeTypography.supporting)
                .foregroundStyle(HomeTheme.muted)
                .padding(.horizontal, HomeMetrics.cardPadding)
                .frame(height: 32)

                ForEach(category.specifications) { specification in
                    Divider().padding(.horizontal, HomeMetrics.cardPadding)
                    HStack(spacing: 12) {
                        Text(specification.label)
                            .font(HomeTypography.body)
                            .foregroundStyle(specification.isUnspecified ? HomeTheme.muted : HomeTheme.ink)
                        Spacer()
                        Text(specification.packageSummary)
                            .font(HomeTypography.body)
                            .foregroundStyle(HomeTheme.muted)
                    }
                    .padding(.horizontal, HomeMetrics.cardPadding)
                    .frame(minHeight: 42)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(category.name)，\(specification.label)，\(specification.packageSummary)")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: HomeMetrics.cardRadius, style: .continuous))
        }
    }

    private func statisticIcon(_ name: String, size: CGFloat, symbolSize: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: symbolSize, weight: .semibold))
            .foregroundStyle(HomeTheme.blue)
            .frame(width: size, height: size)
            .background(HomeTheme.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }

    private func categoryIcon(for name: String) -> String {
        if name.contains("零食") { return "heart.fill" }
        if name.contains("主食") || name.contains("罐") { return "cylinder.fill" }
        if name.contains("冻干") { return "snowflake" }
        if name.contains("猫粮") || name.contains("粮") { return "fish.fill" }
        if name.contains("砂") { return "circle.grid.3x3.fill" }
        if name.contains("清洁") { return "sparkles" }
        return "shippingbox.fill"
    }

    private func quantity(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private var netContent: String {
        var values: [String] = []
        if snapshot.totalMassGrams > 0 { values.append(mass(snapshot.totalMassGrams)) }
        if snapshot.totalVolumeMilliliters > 0 { values.append(volume(snapshot.totalVolumeMilliliters)) }
        return values.joined(separator: " · ")
    }

    private func mass(_ grams: Double) -> String {
        grams >= 1_000
            ? "\((grams / 1_000).formatted(.number.precision(.fractionLength(0...2))))kg"
            : "\(grams.formatted(.number.precision(.fractionLength(0...2))))g"
    }

    private func volume(_ milliliters: Double) -> String {
        milliliters >= 1_000
            ? "\((milliliters / 1_000).formatted(.number.precision(.fractionLength(0...2))))L"
            : "\(milliliters.formatted(.number.precision(.fractionLength(0...2))))ml"
    }
}

private struct PetInventoryStatisticsSnapshot {
    var totalQuantity: Double
    var totalMassGrams: Double
    var totalVolumeMilliliters: Double
    var categories: [PetInventoryCategorySummary]
    var valuation: PetInventoryValuationSummary

    @MainActor
    static func make(store: HomeStore, capabilityKey: String) -> Self {
        guard let root = store.petRootCategory(capabilityKey: capabilityKey) else {
            return .init(
                totalQuantity: 0,
                totalMassGrams: 0,
                totalVolumeMilliliters: 0,
                categories: [],
                valuation: PetInventoryValuation.summarize([])
            )
        }

        let items = store.activePetItems.filter { $0.resolvedPrimaryCategory == root.name }
        var inventoryByProduct: [String: Double] = [:]
        var valuationInputs: [PetInventoryValuationInput] = []
        for item in items {
            let stock = store.petInventory(for: item.id)
            inventoryByProduct[item.id] = stock
            if stock > 0 || !stock.isFinite {
                valuationInputs.append(
                    PetInventoryValuationInput(
                        productID: item.id,
                        quantity: stock,
                        weightedUnitPrice: store.petWeightedAverageInboundUnitPrice(for: item.id)
                    )
                )
            }
        }
        let valuation = PetInventoryValuation.summarize(valuationInputs)
        let categoryOrder = Dictionary(uniqueKeysWithValues: store.categories(for: .pet, parentID: root.id).enumerated().map { ($1.name, $0) })
        var accumulators: [String: PetInventoryCategoryAccumulator] = [:]
        var totalQuantity = 0.0
        var totalMass = 0.0
        var totalVolume = 0.0

        for item in items {
            let stock = inventoryByProduct[item.id] ?? 0
            guard stock.isFinite, stock > 0 else { continue }
            totalQuantity += stock

            let cleanPackage = item.packageType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let cleanUnit = item.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            let package = !cleanPackage.isEmpty ? cleanPackage : (!cleanUnit.isEmpty ? cleanUnit : "件")
            let resolved = PetSpecificationResolver.resolve(item: item)
            let rawSpec = item.spec.trimmingCharacters(in: .whitespacesAndNewlines)
            let specKey = resolved?.groupingKey ?? (rawSpec.isEmpty ? "unspecified" : "raw-\(rawSpec.lowercased())")
            let specLabel = resolved?.displayText ?? (rawSpec.isEmpty ? "未设置规格" : rawSpec)
            let sortValue = resolved?.baseValue ?? Double.greatestFiniteMagnitude

            var category = accumulators[item.resolvedSecondaryCategory]
                ?? PetInventoryCategoryAccumulator(name: item.resolvedSecondaryCategory)
            category.add(
                specificationKey: specKey,
                specificationLabel: specLabel,
                sortValue: sortValue,
                package: package,
                quantity: stock,
                unspecified: resolved == nil && rawSpec.isEmpty
            )
            accumulators[item.resolvedSecondaryCategory] = category

            if let resolved {
                switch resolved.dimension {
                case .mass: totalMass += resolved.baseValue * stock
                case .volume: totalVolume += resolved.baseValue * stock
                }
            }
        }

        let categories = accumulators.values
            .map { $0.summary }
            .sorted {
                let left = categoryOrder[$0.name] ?? Int.max
                let right = categoryOrder[$1.name] ?? Int.max
                return left == right ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : left < right
            }
        return .init(
            totalQuantity: totalQuantity,
            totalMassGrams: totalMass,
            totalVolumeMilliliters: totalVolume,
            categories: categories,
            valuation: valuation
        )
    }
}

private struct PetInventoryCategoryAccumulator {
    let name: String
    var totalQuantity = 0.0
    var packages: [String: Double] = [:]
    var specifications: [String: PetInventorySpecificationAccumulator] = [:]

    mutating func add(
        specificationKey: String,
        specificationLabel: String,
        sortValue: Double,
        package: String,
        quantity: Double,
        unspecified: Bool
    ) {
        totalQuantity += quantity
        packages[package, default: 0] += quantity
        var specification = specifications[specificationKey]
            ?? PetInventorySpecificationAccumulator(id: specificationKey, label: specificationLabel, sortValue: sortValue, isUnspecified: unspecified)
        specification.packages[package, default: 0] += quantity
        specifications[specificationKey] = specification
    }

    var summary: PetInventoryCategorySummary {
        PetInventoryCategorySummary(
            name: name,
            totalQuantity: totalQuantity,
            packageSummary: Self.packageSummary(packages),
            specifications: specifications.values
                .sorted { $0.sortValue == $1.sortValue ? $0.label < $1.label : $0.sortValue < $1.sortValue }
                .map {
                    PetInventorySpecificationSummary(
                        id: $0.id,
                        label: $0.label,
                        packageSummary: Self.packageSummary($0.packages),
                        isUnspecified: $0.isUnspecified
                    )
                }
        )
    }

    private static func packageSummary(_ values: [String: Double]) -> String {
        values.keys.sorted().map { package in
            "\(values[package, default: 0].formatted(.number.precision(.fractionLength(0...2))))\(package)"
        }.joined(separator: " · ")
    }
}

private struct PetInventorySpecificationAccumulator {
    let id: String
    let label: String
    let sortValue: Double
    let isUnspecified: Bool
    var packages: [String: Double] = [:]
}

private struct PetInventoryCategorySummary: Identifiable {
    var id: String { name }
    let name: String
    let totalQuantity: Double
    let packageSummary: String
    let specifications: [PetInventorySpecificationSummary]
}

private struct PetInventorySpecificationSummary: Identifiable {
    let id: String
    let label: String
    let packageSummary: String
    let isUnspecified: Bool
}
