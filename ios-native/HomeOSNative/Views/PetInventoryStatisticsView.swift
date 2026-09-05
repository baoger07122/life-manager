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
                overviewCard
                if snapshot.categories.isEmpty {
                    HomeCard {
                        EmptyState(icon: "shippingbox.fill", title: "暂无当前库存", message: "新增库存后会自动按分类和规格汇总。")
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    ForEach(snapshot.categories) { category in
                        categoryCard(category)
                    }
                }
            }
            .padding(HomeMetrics.pageInset)
        }
        .background(HomeTheme.background)
        .navigationTitle("\(rootCategory?.name ?? "宠物物品")统计")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var overviewCard: some View {
        HomeCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("当前库存").font(HomeTypography.sectionTitle)
                HStack(spacing: 0) {
                    overviewMetric(title: "库存数量", value: quantity(snapshot.totalQuantity), suffix: "件")
                    if snapshot.totalMassGrams > 0 {
                        Divider().frame(height: 42)
                        overviewMetric(title: "可计算重量", value: mass(snapshot.totalMassGrams), suffix: "")
                    }
                    if snapshot.totalVolumeMilliliters > 0 {
                        Divider().frame(height: 42)
                        overviewMetric(title: "可计算容量", value: volume(snapshot.totalVolumeMilliliters), suffix: "")
                    }
                }
            }
        }
    }

    private func overviewMetric(title: String, value: String, suffix: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 20, weight: .semibold)).foregroundStyle(HomeTheme.blue)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if !suffix.isEmpty {
                    Text(suffix).font(HomeTypography.supporting).foregroundStyle(HomeTheme.blue)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func categoryCard(_ category: PetInventoryCategorySummary) -> some View {
        HomeCard(padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text(category.name).font(HomeTypography.cardTitle)
                    Spacer()
                    Text(category.packageSummary)
                        .font(HomeTypography.body.weight(.medium))
                        .foregroundStyle(HomeTheme.blue)
                }
                .padding(.horizontal, HomeMetrics.cardPadding)
                .frame(minHeight: 50)

                ForEach(category.specifications) { specification in
                    Divider().padding(.leading, HomeMetrics.cardPadding)
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
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(category.name)，\(specification.label)，\(specification.packageSummary)")
                }
            }
        }
    }

    private func quantity(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
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

    @MainActor
    static func make(store: HomeStore, capabilityKey: String) -> Self {
        guard let root = store.petRootCategory(capabilityKey: capabilityKey) else {
            return .init(totalQuantity: 0, totalMassGrams: 0, totalVolumeMilliliters: 0, categories: [])
        }

        let inventoryByProduct = Dictionary(grouping: store.data.petInventoryTransactions, by: \.productID)
            .mapValues { transactions in max(0, transactions.reduce(0) { $0 + $1.quantityChange }) }
        let categoryOrder = Dictionary(uniqueKeysWithValues: store.categories(for: .pet, parentID: root.id).enumerated().map { ($1.name, $0) })
        var accumulators: [String: PetInventoryCategoryAccumulator] = [:]
        var totalQuantity = 0.0
        var totalMass = 0.0
        var totalVolume = 0.0

        for item in store.activePetItems where item.resolvedPrimaryCategory == root.name {
            let stock = inventoryByProduct[item.id] ?? 0
            guard stock > 0 else { continue }
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
        return .init(totalQuantity: totalQuantity, totalMassGrams: totalMass, totalVolumeMilliliters: totalVolume, categories: categories)
    }
}

private struct PetInventoryCategoryAccumulator {
    let name: String
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
        packages[package, default: 0] += quantity
        var specification = specifications[specificationKey]
            ?? PetInventorySpecificationAccumulator(id: specificationKey, label: specificationLabel, sortValue: sortValue, isUnspecified: unspecified)
        specification.packages[package, default: 0] += quantity
        specifications[specificationKey] = specification
    }

    var summary: PetInventoryCategorySummary {
        PetInventoryCategorySummary(
            name: name,
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
    let packageSummary: String
    let specifications: [PetInventorySpecificationSummary]
}

private struct PetInventorySpecificationSummary: Identifiable {
    let id: String
    let label: String
    let packageSummary: String
    let isUnspecified: Bool
}
