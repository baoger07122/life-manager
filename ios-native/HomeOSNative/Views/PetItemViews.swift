import SwiftUI
import PhotosUI

extension PetItem {
    var resolvedPrimaryCategory: String { primaryCategory ?? (type.contains("食品") ? "宠物食品" : "宠物用品") }
    var resolvedSecondaryCategory: String { secondaryCategory ?? type }
    var displayTitle: String {
        let cleanBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanBrand.isEmpty ? name : "\(cleanBrand) \(name)"
    }
}

struct PetItemsListView: View {
    @EnvironmentObject private var store: HomeStore
    @Binding var primaryID: String
    @State private var secondaryID = "all"
    @State private var selectedBrand = "all"
    @State private var sortMode: PetItemListSortMode = .createdNewest
    @State private var listSheet: PetItemListSheet?
    @State private var expandedItemID: String?
    @State private var quickMode: PetInventoryTransactionType = .outbound
    @State private var quickQuantity = 1.0
    @State private var quickTotalPrice = 0.0

    private var primaryCategories: [ManagedCategory] { store.categories(for: .pet) }
    private var selectedPrimary: ManagedCategory? {
        primaryCategories.first { $0.id == primaryID } ?? primaryCategories.first
    }
    private var secondaryCategories: [ManagedCategory] {
        guard let selectedPrimary else { return [] }
        return store.categories(for: .pet, parentID: selectedPrimary.id)
    }

    private var items: [PetItem] {
        let filtered = store.activePetItems.filter {
            guard let selectedPrimary else { return false }
            let secondaryName = secondaryCategories.first { $0.id == secondaryID }?.name
            return $0.resolvedPrimaryCategory == selectedPrimary.name
                && (secondaryName == nil || $0.resolvedSecondaryCategory == secondaryName)
                && (selectedBrand == "all" || $0.brand == selectedBrand)
        }
        return filtered.sorted { left, right in
            switch sortMode {
            case .createdNewest:
                let leftDate = left.createdAt ?? left.updatedAt ?? 0
                let rightDate = right.createdAt ?? right.updatedAt ?? 0
                return leftDate == rightDate ? left.name < right.name : leftDate > rightDate
            case .stockHigh:
                let leftStock = store.petInventory(for: left.id)
                let rightStock = store.petInventory(for: right.id)
                return leftStock == rightStock ? left.name < right.name : leftStock > rightStock
            }
        }
    }
    private var availableBrands: [String] {
        Array(Set(store.activePetItems.filter { item in
            selectedPrimary.map { item.resolvedPrimaryCategory == $0.name } ?? true
        }.map(\.brand).filter { !$0.isEmpty })).sorted()
    }

    var body: some View {
        HomeCard(padding: 0) {
            VStack(spacing: 0) {
                primarySelector
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                secondarySelector
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
                HStack(spacing: 10) {
                    filterButton(selectedBrand == "all" ? "品牌" : selectedBrand, icon: "tag", active: selectedBrand != "all")
                    Spacer()
                    Menu {
                        ForEach(PetItemListSortMode.allCases) { option in
                            Button {
                                sortMode = option
                                NativeHaptics.selection()
                            } label: {
                                if sortMode == option {
                                    Label(option.title, systemImage: "checkmark")
                                } else {
                                    Text(option.title)
                                }
                            }
                        }
                    } label: {
                        Label(sortMode.title, systemImage: "arrow.up.arrow.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(HomeTheme.muted)
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(HomeTheme.background, in: Capsule())
                            .overlay { Capsule().stroke(HomeTheme.line, lineWidth: 0.8) }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                Divider()
                if items.isEmpty {
                    VStack(spacing: 12) {
                        EmptyState(icon: "shippingbox.fill", title: "暂无宠物物品", message: "按具体产品添加食品、猫砂或其他用品。")
                        NavigationLink("添加宠物物品") {
                            PetItemEditorView(
                                initialPrimaryID: primaryID,
                                initialSecondaryID: secondaryID == "all" ? nil : secondaryID
                            )
                        }
                            .buttonStyle(HomeSecondaryButtonStyle())
                            .simultaneousGesture(TapGesture().onEnded { NativeHaptics.tap() })
                            .padding(.horizontal, 14)
                            .padding(.bottom, 14)
                    }
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            itemRow(item)
                            if item.id != items.last?.id { Divider() }
                        }
                    }
                }
            }
        }
        .onAppear {
            if !primaryCategories.contains(where: { $0.id == primaryID }) {
                primaryID = primaryCategories.first?.id ?? ""
            }
        }
        .onChange(of: primaryID) { _, _ in
            secondaryID = "all"
            selectedBrand = "all"
            expandedItemID = nil
        }
        .sheet(item: $listSheet) { _ in
            PetBrandFilterSheet(
                brands: availableBrands,
                selectedBrand: $selectedBrand
            )
        }
    }

    private func itemRow(_ item: PetItem) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                NavigationLink { PetItemDetailView(itemID: item.id) } label: {
                    HStack(spacing: 11) {
                        productImage(item)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "无品牌" : item.brand)
                                .font(.system(size: 12))
                                .foregroundStyle(HomeTheme.muted)
                                .lineLimit(1)
                            Text(productNameAndFlavor(item))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(HomeTheme.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.84)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(HomePressButtonStyle())
                .accessibilityLabel("查看\(item.name)详情")

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        expandedItemID = expandedItemID == item.id ? nil : item.id
                        quickMode = .outbound
                        quickQuantity = quickStep(for: item)
                        quickTotalPrice = 0
                    }
                    NativeHaptics.selection()
                } label: {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(specificationAndStock(item))
                            .font(.system(size: 12))
                            .foregroundStyle(HomeTheme.muted)
                            .lineLimit(1)
                        if let rating = store.petProductRating(productID: item.id) {
                            Label(rating.overall.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(HomeTheme.orange)
                        } else {
                            Text("未评分").font(.system(size: 12)).foregroundStyle(HomeTheme.muted)
                        }
                    }
                    .frame(width: 118, alignment: .trailing)
                    .frame(minHeight: 48, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            if expandedItemID == item.id {
                compactQuickManager(item)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var primarySelector: some View {
        HStack(spacing: 22) {
            ForEach(primaryCategories) { category in
                Button {
                    primaryID = category.id
                    NativeHaptics.selection()
                } label: {
                    HomeUnderlineTab(title: category.name, selected: primaryID == category.id, prominent: true)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            NavigationLink { PetRatingsListView() } label: {
                VStack(spacing: 8) {
                    Text("评价")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(HomeTheme.muted)
                        .frame(height: 19, alignment: .center)
                    Capsule().fill(Color.clear).frame(width: 28, height: 3)
                }
                .frame(minWidth: 46, minHeight: HomeMetrics.minimumTapTarget, alignment: .center)
            }
            .buttonStyle(HomePressButtonStyle())
            .simultaneousGesture(TapGesture().onEnded { NativeHaptics.tap() })
            .accessibilityLabel("进入物品评价")
            NavigationLink {
                PetItemEditorView(
                    initialPrimaryID: primaryID,
                    initialSecondaryID: secondaryID == "all" ? nil : secondaryID
                )
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(HomeTheme.muted)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(HomePressButtonStyle())
            .simultaneousGesture(TapGesture().onEnded { NativeHaptics.tap() })
            .accessibilityLabel("新增宠物物品")
        }
    }

    private var secondarySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                Button {
                    secondaryID = "all"
                    expandedItemID = nil
                    NativeHaptics.selection()
                } label: {
                    HomeUnderlineTab(title: "全部", selected: secondaryID == "all")
                }
                .buttonStyle(.plain)
                ForEach(secondaryCategories) { category in
                    Button {
                        secondaryID = category.id
                        expandedItemID = nil
                        NativeHaptics.selection()
                    } label: {
                        HomeUnderlineTab(title: category.name, selected: secondaryID == category.id)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func filterButton(_ title: String, icon: String, active: Bool) -> some View {
        Button {
            listSheet = .brand
            NativeHaptics.selection()
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? HomeTheme.blue : HomeTheme.muted)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(active ? HomeTheme.blue.opacity(0.10) : HomeTheme.background, in: Capsule())
                .overlay { Capsule().stroke(active ? HomeTheme.blue.opacity(0.35) : HomeTheme.line, lineWidth: 0.8) }
        }
        .buttonStyle(.plain)
    }

    private func compactQuickManager(_ item: PetItem) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Picker("操作", selection: $quickMode) {
                    Text("出库").tag(PetInventoryTransactionType.outbound)
                    Text("入库").tag(PetInventoryTransactionType.inbound)
                }
                .pickerStyle(.segmented)
                Spacer(minLength: 0)
                Text(item.unit).font(.system(size: 13)).foregroundStyle(HomeTheme.muted)
            }
            HStack(spacing: 6) {
                compactStepButton("minus") { quickQuantity = max(quickStep(for: item), quickQuantity - quickStep(for: item)) }
                TextField("数量", value: $quickQuantity, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 58, height: 38)
                    .background(HomeTheme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                compactStepButton("plus") { quickQuantity += quickStep(for: item) }
                Spacer(minLength: 4)
                Button(quickMode == .inbound ? "确认入库" : "确认出库") { confirmQuickAction(item) }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .frame(height: 38)
                    .background(HomeTheme.blue, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .buttonStyle(HomePressButtonStyle())
            }
            if quickMode == .inbound {
                HStack(spacing: 8) {
                    Text("购入总价").font(.system(size: 13)).foregroundStyle(HomeTheme.muted)
                    TextField("¥0.00", value: $quickTotalPrice, format: .currency(code: "CNY"))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.leading)
                        .font(.system(size: 14))
                    Spacer()
                    Text(quickUnitPrice(item).map { "单价 ¥\($0.formatted(.number.precision(.fractionLength(2))))/\(item.unit)" } ?? "单价自动计算")
                        .font(.system(size: 12))
                        .foregroundStyle(HomeTheme.muted)
                }
                .frame(minHeight: 36)
            }
        }
        .padding(9)
        .background(HomeTheme.background.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func compactStepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            NativeHaptics.selection()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(HomeTheme.ink)
                .frame(width: 34, height: 34)
                .background(HomeTheme.card, in: Circle())
                .overlay { Circle().stroke(HomeTheme.line, lineWidth: 0.8) }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func confirmQuickAction(_ item: PetItem) {
        let success = store.recordPetInventory(
            productID: item.id,
            type: quickMode,
            quantity: quickQuantity,
            occurrenceDate: LitterPredictionService.format(Date()),
            reason: quickMode == .inbound ? "快捷入库" : "快捷出库",
            totalPrice: quickMode == .inbound && quickTotalPrice > 0 ? quickTotalPrice : nil
        )
        if success {
            withAnimation(.easeInOut(duration: 0.18)) { expandedItemID = nil }
        }
    }

    private func quickStep(for item: PetItem) -> Double {
        ["kg", "公斤", "千克", "l", "L", "升"].contains(item.unit) ? 0.1 : 1
    }

    private func quickUnitPrice(_ item: PetItem) -> Double? {
        guard quickMode == .inbound, quickQuantity > 0, quickTotalPrice > 0 else { return nil }
        return quickTotalPrice / quickQuantity
    }

    private func productNameAndFlavor(_ item: PetItem) -> String {
        let flavor = (item.variant ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flavor.isEmpty, flavor.caseInsensitiveCompare(item.spec) != .orderedSame else { return item.name }
        return "\(item.name) · \(flavor)"
    }

    private func specificationAndStock(_ item: PetItem) -> String {
        let quantity = store.petInventory(for: item.id).formatted()
        let package = (item.packageType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let stockText = "\(quantity)\(package.isEmpty ? item.unit : package)"
        let spec = item.spec.trimmingCharacters(in: .whitespacesAndNewlines)
        return spec.isEmpty ? stockText : "\(spec) × \(stockText)"
    }

    @ViewBuilder private func productImage(_ item: PetItem) -> some View {
        if let image = item.image, !image.isEmpty {
            PetStoredImage(reference: image).frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Image(systemName: item.resolvedSecondaryCategory == "猫砂" ? "circle.hexagongrid.fill" : "takeoutbag.and.cup.and.straw.fill")
                .foregroundStyle(HomeTheme.blue).frame(width: 48, height: 48)
                .background(HomeTheme.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

}

private enum PetItemListSheet: String, Identifiable {
    case brand
    var id: String { rawValue }
}

private enum PetItemListSortMode: String, CaseIterable, Identifiable {
    case createdNewest, stockHigh
    var id: String { rawValue }
    var title: String {
        switch self {
        case .createdNewest: "最近添加"
        case .stockHigh: "库存从高到低"
        }
    }
}

private struct PetBrandFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    let brands: [String]
    @Binding private var selectedBrand: String
    @State private var draftBrand: String

    init(
        brands: [String],
        selectedBrand: Binding<String>
    ) {
        self.brands = brands
        _selectedBrand = selectedBrand
        _draftBrand = State(initialValue: selectedBrand.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    selectionRow("全部品牌", selected: draftBrand == "all") { draftBrand = "all" }
                    ForEach(brands, id: \.self) { brand in
                        selectionRow(brand, selected: draftBrand == brand) { draftBrand = brand }
                    }
                }
            }
            .navigationTitle("选择品牌")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("应用") { apply() }.fontWeight(.semibold) }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button("重置") {
                        draftBrand = "all"
                        NativeHaptics.selection()
                    }
                    .buttonStyle(HomeSecondaryButtonStyle())
                    Button("应用筛选", action: apply)
                        .buttonStyle(HomePrimaryButtonStyle())
                }
                .padding(.horizontal, HomeMetrics.pageInset)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func selectionRow(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            NativeHaptics.selection()
        } label: {
            HStack {
                Text(title).foregroundStyle(HomeTheme.ink)
                Spacer()
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(HomeTheme.blue) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func apply() {
        selectedBrand = draftBrand
        NativeHaptics.success()
        dismiss()
    }
}

struct PetRatingsListView: View {
    @EnvironmentObject private var store: HomeStore
    @State private var primaryID = "pet-root-food"
    @State private var secondaryID = "all"
    @State private var selectedBrand = "all"
    @State private var sortMode: PetRatingSortMode = .scoreHigh
    @State private var sheet: PetRatingsSheet?

    private var primaryCategories: [ManagedCategory] { store.categories(for: .pet) }
    private var selectedPrimary: ManagedCategory? { primaryCategories.first { $0.id == primaryID } ?? primaryCategories.first }
    private var secondaryCategories: [ManagedCategory] {
        selectedPrimary.map { store.categories(for: .pet, parentID: $0.id) } ?? []
    }
    private var items: [PetItem] {
        let filtered = store.activePetItems.filter { item in
            guard let selectedPrimary, store.petProductRating(productID: item.id) != nil else { return false }
            let secondaryName = secondaryCategories.first { $0.id == secondaryID }?.name
            return item.resolvedPrimaryCategory == selectedPrimary.name
                && (secondaryName == nil || item.resolvedSecondaryCategory == secondaryName)
                && (selectedBrand == "all" || item.brand == selectedBrand)
        }
        return filtered.sorted { left, right in
            let leftRating = store.petProductRating(productID: left.id)?.overall ?? 0
            let rightRating = store.petProductRating(productID: right.id)?.overall ?? 0
            switch sortMode {
            case .scoreHigh: return leftRating == rightRating ? left.name < right.name : leftRating > rightRating
            case .scoreLow: return leftRating == rightRating ? left.name < right.name : leftRating < rightRating
            case .name: return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
        }
    }
    private var availableBrands: [String] {
        Array(Set(store.activePetItems.map(\.brand).filter { !$0.isEmpty })).sorted()
    }

    var body: some View {
        ScrollView {
            HomeCard(padding: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 22) {
                        ForEach(primaryCategories) { category in
                            Button {
                                primaryID = category.id
                                secondaryID = "all"
                                NativeHaptics.selection()
                            } label: {
                                HomeUnderlineTab(title: category.name, selected: primaryID == category.id, prominent: true)
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 20) {
                            ratingFilter(title: "全部", id: "all")
                            ForEach(secondaryCategories) { category in ratingFilter(title: category.name, id: category.id) }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
                    HStack(spacing: 10) {
                        Menu {
                            Button("全部品牌") { selectedBrand = "all" }
                            ForEach(availableBrands, id: \.self) { brand in
                                Button(brand) { selectedBrand = brand }
                            }
                        } label: {
                            Label(selectedBrand == "all" ? "品牌" : selectedBrand, systemImage: "tag")
                        }
                        Menu {
                            ForEach(PetRatingSortMode.allCases) { mode in
                                Button(mode.title) { sortMode = mode }
                            }
                        } label: {
                            Label(sortMode.title, systemImage: "arrow.up.arrow.down")
                        }
                        Spacer()
                    }
                    .font(HomeTypography.supporting.weight(.medium))
                    .foregroundStyle(HomeTheme.blue)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                    Divider()

                    if items.isEmpty {
                        EmptyState(icon: "star.fill", title: "暂无评价", message: "添加评价后会在这里显示历史平均分。")
                    } else {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            ratingRow(item)
                            if index < items.count - 1 { Divider() }
                        }
                    }
                }
            }
            .padding(.horizontal, HomeMetrics.pageInset)
            .padding(.vertical, 16)
        }
        .background(HomeTheme.background)
        .navigationTitle("物品评价")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    NativeHaptics.tap()
                    sheet = .productPicker
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加物品评价")
            }
        }
        .sheet(item: $sheet) { _ in PetRatingProductPickerSheet() }
        .onAppear {
            if !primaryCategories.contains(where: { $0.id == primaryID }) {
                primaryID = primaryCategories.first?.id ?? ""
            }
        }
        .onChange(of: primaryID) { _, _ in
            secondaryID = "all"
            selectedBrand = "all"
        }
    }

    private func ratingFilter(title: String, id: String) -> some View {
        Button {
            secondaryID = id
            NativeHaptics.selection()
        } label: {
            HomeUnderlineTab(title: title, selected: secondaryID == id)
        }
        .buttonStyle(.plain)
    }

    private func ratingRow(_ item: PetItem) -> some View {
        NavigationLink { PetItemDetailView(itemID: item.id) } label: {
            HStack(spacing: 11) {
                ratingImage(item)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.brand.isEmpty ? "无品牌" : item.brand)
                        .font(.system(size: 12))
                        .foregroundStyle(HomeTheme.muted)
                    Text(item.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(HomeTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let summary = store.petProductRating(productID: item.id) {
                        Text(dimensionSummary(item: item, rating: summary))
                            .font(.system(size: 12))
                            .foregroundStyle(HomeTheme.muted)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 6)
                if let summary = store.petProductRating(productID: item.id) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(summary.overall.formatted(.number.precision(.fractionLength(1))))
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundStyle(HomeTheme.blue)
                        Text("\(summary.count)次评价").font(.system(size: 11)).foregroundStyle(HomeTheme.muted)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dimensionSummary(item: PetItem, rating: PetRatingSummary) -> String {
        petRatingDimensions(item).compactMap { name in
            rating.dimensionAverages[name].map { "\(name) \($0.formatted(.number.precision(.fractionLength(1))))" }
        }.joined(separator: " · ")
    }

    @ViewBuilder private func ratingImage(_ item: PetItem) -> some View {
        if let image = item.image, !image.isEmpty {
            PetStoredImage(reference: image).frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Image(systemName: item.resolvedSecondaryCategory == "猫砂" ? "circle.hexagongrid.fill" : "takeoutbag.and.cup.and.straw.fill")
                .foregroundStyle(HomeTheme.blue).frame(width: 48, height: 48)
                .background(HomeTheme.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private enum PetRatingsSheet: String, Identifiable {
    case productPicker
    var id: String { rawValue }
}

private enum PetRatingSortMode: String, CaseIterable, Identifiable {
    case scoreHigh, scoreLow, name
    var id: String { rawValue }
    var title: String {
        switch self {
        case .scoreHigh: "评分从高到低"
        case .scoreLow: "评分从低到高"
        case .name: "按名称"
        }
    }
}

private struct PetRatingProductPickerSheet: View {
    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(store.activePetItems) { item in
                NavigationLink {
                    PetProductReviewEditorView(productID: item.id)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.displayTitle).font(HomeTypography.body.weight(.medium))
                        Text(item.resolvedPrimaryCategory + " · " + item.resolvedSecondaryCategory)
                            .font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                    }
                }
            }
            .navigationTitle("选择评价物品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

struct PetItemDetailView: View {
    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    let itemID: String
    @State private var showArchive = false
    @State private var sheet: PetItemDetailSheet?
    private var item: PetItem? { store.data.petItems.first { $0.id == itemID } }

    var body: some View {
        ScrollView {
            if let item {
                LazyVStack(alignment: .leading, spacing: HomeMetrics.sectionSpacing) {
                    productHeroCard(item)
                    inventoryCard(item)
                    transactionCard(item)
                    productReviewCard
                    if isPetFood(item) { palatabilityCard }
                    priceCard(item)
                }.padding(HomeMetrics.pageInset)
            } else {
                EmptyState(icon: "exclamationmark.triangle.fill", title: "物品不存在", message: "该物品可能已停用。")
            }
        }
        .background(HomeTheme.background)
        .navigationTitle(item?.displayTitle ?? "物品详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let item {
                ToolbarItemGroup(placement: .primaryAction) {
                    NavigationLink("编辑") { PetItemEditorView(itemID: item.id) }
                    Button(role: .destructive) { showArchive = true } label: { Image(systemName: "archivebox") }
                }
            }
        }
        .sheet(item: $sheet) { value in
            switch value {
            case .inbound: PetInventoryEditorView(productID: itemID, mode: .inbound)
            case .outbound: PetInventoryEditorView(productID: itemID, mode: .outbound)
            case .adjustment: PetInventoryEditorView(productID: itemID, mode: .adjustment)
            case .productReview(let reviewID): PetProductReviewEditorView(productID: itemID, reviewID: reviewID)
            case .palatability: PetPalatabilityEditorView(productID: itemID)
            case .image: PetItemImageEditorSheet(itemID: itemID, initialImage: item?.image)
            }
        }
        .alert("停用这个宠物物品？", isPresented: $showArchive) {
            Button("取消", role: .cancel) {}
            Button("停用", role: .destructive) { store.deletePetItem(id: itemID); dismiss() }
        } message: { Text("产品会从日常列表隐藏，但库存、价格和评价历史会保留。") }
    }

    private func productHeroCard(_ item: PetItem) -> some View {
        HomeCard(padding: 12) {
            HStack(spacing: 12) {
                Button {
                    sheet = .image
                    NativeHaptics.tap()
                } label: {
                    detailProductImage(item)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 20))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, HomeTheme.blue)
                                .offset(x: 4, y: 4)
                        }
                }
                .buttonStyle(HomePressButtonStyle())
                .accessibilityLabel("修改商品图片")
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.brand.isEmpty ? "无品牌" : item.brand)
                        .font(HomeTypography.supporting)
                        .foregroundStyle(HomeTheme.muted)
                    Text(detailProductName(item))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(HomeTheme.ink)
                    Text(productSpecification(item))
                        .font(HomeTypography.supporting)
                        .foregroundStyle(HomeTheme.muted)
                    Text("\(item.resolvedPrimaryCategory) · \(item.resolvedSecondaryCategory)")
                        .font(HomeTypography.supporting)
                        .foregroundStyle(HomeTheme.muted)
                }
                Spacer(minLength: 4)
            }
        }
    }

    private func inventoryCard(_ item: PetItem) -> some View {
        HomeCard(padding: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("当前库存").font(HomeTypography.cardTitle)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(store.petInventory(for: item.id).formatted())
                            .font(HomeTypography.metric)
                            .foregroundStyle(HomeTheme.blue)
                        Text(item.unit).font(HomeTypography.body).foregroundStyle(HomeTheme.muted)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    inventoryAction("入库", icon: "square.and.arrow.down", color: HomeTheme.blue) { sheet = .inbound }
                    inventoryAction("出库", icon: "square.and.arrow.up", color: HomeTheme.blue) { sheet = .outbound }
                    inventoryAction("修正", icon: "pencil", color: HomeTheme.blue) { sheet = .adjustment }
                }
            }
        }
    }

    private func transactionCard(_ item: PetItem) -> some View {
        let records = Array(store.petTransactions(for: item.id).prefix(5))
        return HomeCard {
            VStack(alignment: .leading, spacing: 9) {
                Text("进出库记录").font(HomeTypography.cardTitle)
                if records.isEmpty { Text("暂无库存流水").font(HomeTypography.body).foregroundStyle(HomeTheme.muted) }
                ForEach(records) { record in
                    Divider()
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: record.quantityChange >= 0 ? "arrow.down.circle" : "arrow.up.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(record.quantityChange >= 0 ? HomeTheme.blue : HomeTheme.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.reason).font(HomeTypography.body.weight(.medium))
                            Text("\(HomeDateText.display(record.occurrenceDate)) · \(sourceText(record.source))").font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                            if record.type == .inbound, let totalPrice = record.totalPrice, let unitPrice = record.unitPrice {
                                Text("总价 \(currency2(totalPrice)) · 单价 \(currency2(unitPrice))/\(record.unit)")
                                    .font(HomeTypography.supporting)
                                    .foregroundStyle(HomeTheme.muted)
                            }
                        }
                        Spacer()
                        Text("\(record.quantityChange > 0 ? "+" : "")\(record.quantityChange.formatted())\(record.unit)")
                            .font(HomeTypography.body.weight(.semibold)).foregroundStyle(record.quantityChange >= 0 ? HomeTheme.success : HomeTheme.orange)
                    }
                }
            }
        }
    }

    private func priceCard(_ item: PetItem) -> some View {
        let records = store.petTransactions(for: item.id).filter { $0.type == .inbound && $0.unitPrice != nil }
        return HomeCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("价格历史").font(HomeTypography.cardTitle)
                HStack {
                    Text("日期").frame(maxWidth: .infinity, alignment: .leading)
                    Text("总价").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("单价").frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.system(size: 11))
                .foregroundStyle(HomeTheme.muted)
                ForEach(records.prefix(4)) { record in
                    Divider()
                    HStack {
                        Text(HomeDateText.display(record.occurrenceDate)).frame(maxWidth: .infinity, alignment: .leading)
                        Text(currency2(record.totalPrice ?? 0)).frame(maxWidth: .infinity, alignment: .trailing)
                        Text("\(currency2(record.unitPrice ?? 0))/\(record.unit)").frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(HomeTheme.muted)
                }
                Divider()
                HStack(spacing: 16) {
                    Spacer()
                    Text("最低 \(records.compactMap(\.unitPrice).min().map { "\(currency2($0))/\(item.unit)" } ?? "暂无")")
                    Text("最近 \(records.first?.unitPrice.map { "\(currency2($0))/\(item.unit)" } ?? "暂无")")
                }
                .font(.system(size: 11))
                .foregroundStyle(HomeTheme.muted)
            }
        }
    }

    private var productReviewCard: some View {
        let records = store.data.petProductReviews.filter { $0.productID == itemID }.sorted { $0.reviewDate > $1.reviewDate }
        return HomeCard(padding: 12) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("物品评价").font(HomeTypography.cardTitle)
                    Spacer()
                    Button("添加评价") { NativeHaptics.tap(); sheet = .productReview(reviewID: nil) }
                        .font(HomeTypography.supporting.weight(.medium))
                }
                if let item, let summary = store.petProductRating(productID: itemID) {
                    HStack(spacing: 12) {
                        VStack(spacing: 3) {
                            Text(summary.overall.formatted(.number.precision(.fractionLength(1))))
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(HomeTheme.blue)
                            ratingStars(summary.overall)
                            Text("综合评分 · \(summary.count)次")
                                .font(.system(size: 10))
                                .foregroundStyle(HomeTheme.muted)
                        }
                        .frame(width: 94)
                        Divider()
                        let dimensions = petRatingDimensions(item)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                            ForEach(dimensions, id: \.self) { name in
                                HStack(spacing: 5) {
                                    Image(systemName: ratingIcon(name))
                                        .foregroundStyle(HomeTheme.blue)
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(name).font(.system(size: 10)).foregroundStyle(HomeTheme.muted)
                                        Text(summary.dimensionAverages[name]?.formatted(.number.precision(.fractionLength(1))) ?? "--")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Text("暂无物品评价").font(HomeTypography.body).foregroundStyle(HomeTheme.muted)
                }
                ForEach(records.prefix(5)) { review in
                    Divider()
                    Button {
                        NativeHaptics.selection()
                        sheet = .productReview(reviewID: review.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(HomeDateText.display(review.reviewDate)).font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                                Spacer()
                                Text("本次 \(review.overallScore.formatted(.number.precision(.fractionLength(1))))")
                                    .font(HomeTypography.cardTitle).foregroundStyle(HomeTheme.blue)
                                Image(systemName: "pencil")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(HomeTheme.muted)
                            }
                            if !review.reviewText.isEmpty { Text(review.reviewText).font(HomeTypography.body).foregroundStyle(HomeTheme.ink) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var palatabilityCard: some View {
        let records = store.data.petPalatabilityReviews.filter { $0.productID == itemID }.sorted { $0.reviewDate > $1.reviewDate }
        return HomeCard {
            VStack(alignment: .leading, spacing: 9) {
                HomeSectionHeader(title: "猫咪评价", actionTitle: "添加") { sheet = .palatability }
                if records.isEmpty { Text("暂无猫咪评价").font(HomeTypography.body).foregroundStyle(HomeTheme.muted) }
                ForEach(records.prefix(6)) { review in
                    Divider()
                    HStack { Text(review.petNameSnapshot).font(HomeTypography.cardTitle); Spacer(); Text(review.preference).font(HomeTypography.body).foregroundStyle(preferenceColor(review.preference)) }
                    if let note = review.note { Text(note).font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted) }
                    Text(HomeDateText.display(review.reviewDate)).font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                }
            }
        }
    }

    @ViewBuilder private func detailProductImage(_ item: PetItem) -> some View {
        if let image = item.image, !image.isEmpty {
            PetStoredImage(reference: image)
                .frame(width: 78, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Image(systemName: item.resolvedSecondaryCategory == "猫砂" ? "circle.hexagongrid.fill" : "takeoutbag.and.cup.and.straw.fill")
                .font(.system(size: 30))
                .foregroundStyle(HomeTheme.blue)
                .frame(width: 78, height: 78)
                .background(HomeTheme.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func inventoryAction(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            action()
            NativeHaptics.tap()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 36, height: 32)
                    .background(HomeTheme.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 9).stroke(HomeTheme.line, lineWidth: 0.8) }
                Text(title).font(.system(size: 10)).foregroundStyle(HomeTheme.muted)
            }
            .frame(minWidth: 44, minHeight: 50)
        }
        .buttonStyle(HomePressButtonStyle())
    }

    private func ratingStars(_ score: Double) -> some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { index in
                let remainder = score - Double(index - 1)
                Image(systemName: remainder >= 1 ? "star.fill" : remainder >= 0.5 ? "star.leadinghalf.filled" : "star")
                    .font(.system(size: 12))
                    .foregroundStyle(HomeTheme.orange)
            }
        }
    }

    private func ratingIcon(_ name: String) -> String {
        switch name {
        case "适口性": "takeoutbag.and.cup.and.straw"
        case "品质": "shield.checkered"
        case "性价比": "tag"
        case "回购意愿": "heart"
        case "使用效果": "sparkles"
        case "便利性": "hand.tap"
        case "耐用性": "clock.arrow.circlepath"
        default: "star"
        }
    }

    private func productSpecification(_ item: PetItem) -> String {
        let values = [item.packageType ?? "", item.spec]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? "规格未记录" : values.joined(separator: " · ")
    }

    private func detailProductName(_ item: PetItem) -> String {
        let flavor = (item.variant ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !flavor.isEmpty, flavor.caseInsensitiveCompare(item.spec) != .orderedSame else { return item.name }
        return "\(item.name) · \(flavor)"
    }

    private func isPetFood(_ item: PetItem) -> Bool {
        item.resolvedPrimaryCategory == store.petRootCategory(capabilityKey: "petFood")?.name
    }
}

private enum PetItemDetailSheet: Identifiable {
    case inbound
    case outbound
    case adjustment
    case productReview(reviewID: String?)
    case palatability
    case image

    var id: String {
        switch self {
        case .inbound: "inbound"
        case .outbound: "outbound"
        case .adjustment: "adjustment"
        case .productReview(let reviewID): "product-review-\(reviewID ?? "new")"
        case .palatability: "palatability"
        case .image: "image"
        }
    }
}

private struct PetItemImageEditorSheet: View {
    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    let itemID: String
    @State private var imageReference: String?
    @State private var selectedPhoto: PhotosPickerItem?

    init(itemID: String, initialImage: String?) {
        self.itemID = itemID
        _imageReference = State(initialValue: initialImage)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Group {
                    if let imageReference, !imageReference.isEmpty {
                        PetStoredImage(reference: imageReference)
                            .frame(maxWidth: .infinity)
                            .frame(height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 44))
                            .foregroundStyle(HomeTheme.muted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 260)
                            .background(HomeTheme.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(imageReference == nil ? "选择图片" : "更换图片", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(HomePrimaryButtonStyle())
                if imageReference != nil {
                    Button("移除图片", role: .destructive) {
                        imageReference = nil
                        NativeHaptics.warning()
                    }
                    .frame(minHeight: HomeMetrics.minimumTapTarget)
                }
                Spacer()
            }
            .padding(HomeMetrics.pageInset)
            .background(HomeTheme.background)
            .navigationTitle("修改商品图片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).fontWeight(.semibold) }
            }
        }
        .presentationDetents([.medium, .large])
        .onChange(of: selectedPhoto) { _, photo in
            Task {
                guard let data = try? await photo?.loadTransferable(type: Data.self) else { return }
                imageReference = "data:image/jpeg;base64," + data.base64EncodedString()
                NativeHaptics.selection()
            }
        }
    }

    private func save() {
        guard var item = store.data.petItems.first(where: { $0.id == itemID }) else { return }
        item.image = imageReference
        store.upsertPetItem(item)
        NativeHaptics.success()
        dismiss()
    }
}
func preferenceColor(_ value: String) -> Color { value == "喜欢" ? HomeTheme.success : value == "不喜欢" ? HomeTheme.danger : HomeTheme.muted }
func sourceText(_ value: PetInventorySource) -> String {
    switch value { case .manual: "手动"; case .migration: "旧数据迁移"; case .litterRefill: "猫砂补砂"; case .litterReplace: "猫砂换砂" }
}

func petRatingDimensions(_ item: PetItem) -> [String] {
    if item.resolvedPrimaryCategory.contains("食品") {
        return ["适口性", "品质", "性价比", "回购意愿"]
    }
    return ["使用效果", "便利性", "耐用性", "性价比"]
}

func currency2(_ value: Double) -> String {
    "¥\(value.formatted(.number.precision(.fractionLength(2))))"
}
