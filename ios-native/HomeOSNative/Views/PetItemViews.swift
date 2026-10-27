import SwiftUI
import PhotosUI

extension PetItem {
    var resolvedPrimaryCategory: String { primaryCategory ?? (type.contains("食品") ? "宠物食品" : "宠物用品") }
    var resolvedSecondaryCategory: String { secondaryCategory ?? type }
    var isLitterProduct: Bool {
        let secondary = resolvedSecondaryCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyType = type.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = (litterKind ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let knownLitterCategories = ["猫砂", "矿砂", "木薯", "木薯砂", "豆腐砂", "膨润土砂", "混合砂"]
        return !kind.isEmpty
            || knownLitterCategories.contains(secondary)
            || secondary.contains("猫砂")
            || knownLitterCategories.contains(legacyType)
            || legacyType.contains("猫砂")
    }
    var displayVariant: String? {
        let cleanVariant = (variant ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSpecification = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanVariant.isEmpty, cleanVariant.caseInsensitiveCompare(cleanSpecification) != .orderedSame else { return nil }
        return cleanVariant
    }
    var displayNameAndVariant: String {
        guard let flavor = displayVariant else { return name }
        return "\(name) · \(flavor)"
    }
    var displayTitle: String {
        let cleanBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanBrand.isEmpty ? name : "\(cleanBrand) \(name)"
    }
    var resolvedWillRepurchase: Bool { willRepurchase ?? !isArchived }
}

struct PetItemsListView<HeaderContent: View, StatisticsContent: View, FooterContent: View>: View {
    @EnvironmentObject private var store: HomeStore
    @Binding var primaryID: String
    @Binding var petNavigationPath: [PetViewRoute]
    private let headerContent: HeaderContent
    private let statisticsContent: StatisticsContent
    private let footerContent: FooterContent
    @State private var secondaryID = ""
    @State private var selectedBrand = "all"
    @AppStorage("homeos.pet.items.sortMode") private var sortMode: PetItemListSortMode = .smart
    @State private var expandedItemID: String?
    @State private var quickMode: PetInventoryTransactionType = .outbound
    @State private var quickQuantity = 1.0
    @State private var quickTotalPriceText = ""
    @State private var quickNote = ""
    @State private var quickHasExpiration = false
    @State private var quickExpirationDate = Date()
    @State private var quickBatchAllocationRequest: PetInventoryBatchAllocationRequest?
    @State private var deleteCandidate: PetItem?
    @State private var route: PetItemsRoute?

    private var primaryCategories: [ManagedCategory] { store.categories(for: .pet) }
    private var selectedPrimary: ManagedCategory? {
        primaryCategories.first { $0.id == primaryID } ?? primaryCategories.first
    }
    private var secondaryCategories: [ManagedCategory] {
        guard let selectedPrimary else { return [] }
        return store.categories(for: .pet, parentID: selectedPrimary.id)
    }

    private var matchingItems: [PetItem] {
        let filtered = store.data.petItems.filter {
            guard let selectedPrimary else { return false }
            let secondaryName = secondaryCategories.first { $0.id == secondaryID }?.name
            return $0.resolvedWillRepurchase
                && $0.resolvedPrimaryCategory == selectedPrimary.name
                && $0.resolvedSecondaryCategory == secondaryName
                && (selectedBrand == "all" || $0.brand == selectedBrand)
        }
        let expiryDates = sortMode == .expiryNearest
            ? Dictionary(uniqueKeysWithValues: filtered.map { ($0.id, store.petInventoryEarliestExpirationDate(for: $0.id)) })
            : [:]
        return filtered.sorted { left, right in
            switch sortMode {
            case .smart:
                let leftRating = store.petProductRating(productID: left.id)?.overall
                let rightRating = store.petProductRating(productID: right.id)?.overall
                switch (leftRating, rightRating) {
                case let (.some(leftScore), .some(rightScore)):
                    if leftScore != rightScore { return leftScore > rightScore }
                    return isNewer(left, than: right)
                case (.some(_), .none):
                    return true
                case (.none, .some(_)):
                    return false
                case (.none, .none):
                    return isNewer(left, than: right)
                }
            case .createdNewest:
                return isNewer(left, than: right)
            case .ratingHigh:
                let leftScore = store.petProductRating(productID: left.id)?.overall ?? -1
                let rightScore = store.petProductRating(productID: right.id)?.overall ?? -1
                if leftScore != rightScore { return leftScore > rightScore }
                return isNewer(left, than: right)
            case .stockHigh:
                let leftStock = store.petInventory(for: left.id)
                let rightStock = store.petInventory(for: right.id)
                if leftStock != rightStock { return leftStock > rightStock }
                return isNewer(left, than: right)
            case .brandAndModel:
                return brandAndModelSortsBefore(left, right)
            case .expiryNearest:
                return expirySortsBefore(left, right, dates: expiryDates)
            }
        }
    }
    private var items: [PetItem] { matchingItems.filter { store.petInventory(for: $0.id) > 0 } }
    private var availableBrands: [String] {
        Array(Set(store.data.petItems.filter { item in
            item.resolvedWillRepurchase
                && (selectedPrimary.map { item.resolvedPrimaryCategory == $0.name } ?? true)
        }.map(\.brand).filter { !$0.isEmpty })).sorted()
    }

    private func isNewer(_ left: PetItem, than right: PetItem) -> Bool {
        let leftDate = left.createdAt ?? left.updatedAt ?? 0
        let rightDate = right.createdAt ?? right.updatedAt ?? 0
        return leftDate == rightDate ? left.name < right.name : leftDate > rightDate
    }

    private func expirySortsBefore(_ left: PetItem, _ right: PetItem, dates: [String: String?]) -> Bool {
        let leftDate = dates[left.id] ?? nil
        let rightDate = dates[right.id] ?? nil
        switch (leftDate, rightDate) {
        case let (.some(leftDate), .some(rightDate)) where leftDate != rightDate:
            return leftDate < rightDate
        case (.some(_), .none): return true
        case (.none, .some(_)): return false
        default:
            let leftCreated = left.createdAt ?? 0
            let rightCreated = right.createdAt ?? 0
            if leftCreated != rightCreated { return leftCreated < rightCreated }
            return left.id < right.id
        }
    }

    private func brandAndModelSortsBefore(_ left: PetItem, _ right: PetItem) -> Bool {
        let leftBrand = left.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let rightBrand = right.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        if leftBrand.isEmpty != rightBrand.isEmpty { return !leftBrand.isEmpty }
        if !leftBrand.isEmpty {
            let comparison = leftBrand.localizedStandardCompare(rightBrand)
            if comparison != .orderedSame { return comparison == .orderedAscending }
        }

        let leftVariant = left.displayVariant ?? left.model
        let rightVariant = right.displayVariant ?? right.model
        let comparableFields = [
            (left.name, right.name),
            (leftVariant, rightVariant),
            (left.spec, right.spec),
            (left.packageType ?? "", right.packageType ?? "")
        ]
        for (leftValue, rightValue) in comparableFields {
            let comparison = leftValue.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedStandardCompare(rightValue.trimmingCharacters(in: .whitespacesAndNewlines))
            if comparison != .orderedSame { return comparison == .orderedAscending }
        }

        let leftCreatedAt = left.createdAt ?? 0
        let rightCreatedAt = right.createdAt ?? 0
        if leftCreatedAt != rightCreatedAt { return leftCreatedAt < rightCreatedAt }
        return left.id < right.id
    }

    init(
        primaryID: Binding<String>,
        petNavigationPath: Binding<[PetViewRoute]>,
        @ViewBuilder header: () -> HeaderContent,
        @ViewBuilder statistics: () -> StatisticsContent,
        @ViewBuilder footer: () -> FooterContent
    ) {
        _primaryID = primaryID
        _petNavigationPath = petNavigationPath
        headerContent = header()
        statisticsContent = statistics()
        footerContent = footer()
    }

    var body: some View {
        List {
            pageHeader
                .listRowInsets(.init(top: 18, leading: HomeMetrics.pageInset, bottom: 7, trailing: HomeMetrics.pageInset))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            statisticsContent
                .listRowInsets(.init(top: 5, leading: HomeMetrics.pageInset, bottom: 10, trailing: HomeMetrics.pageInset))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            selectorPanelHeader
                .listRowInsets(.init(top: 10, leading: HomeMetrics.pageInset, bottom: 0, trailing: HomeMetrics.pageInset))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if items.isEmpty {
                VStack(spacing: 12) {
                    EmptyState(icon: "shippingbox.fill", title: "暂无当前库存", message: "可以新增物品，或从右上角查看待回购。")
                    Button("添加宠物物品") { openEditor() }
                    .buttonStyle(HomeSecondaryButtonStyle())
                }
                .padding(.vertical, 10)
                .background(HomeTheme.card)
                .overlay(alignment: .top) { panelDivider }
                .listRowInsets(panelRowInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(items) { item in
                    itemRow(item)
                        .background(HomeTheme.card)
                        .overlay(alignment: .top) { panelDivider }
                        .listRowInsets(panelRowInsets)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            nativeItemActions(item)
                        }
                    if expandedItemID == item.id {
                        quickManagerRow(item)
                    }
                }
            }

            panelBottomCap
                .listRowInsets(panelRowInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            footerContent
                .listRowInsets(.init(top: 13, leading: HomeMetrics.pageInset, bottom: 24, trailing: HomeMetrics.pageInset))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 1)
        .scrollContentBackground(.hidden)
        .background(HomeTheme.background)
        .scrollIndicators(.hidden)
        .onAppear {
            if !primaryCategories.contains(where: { $0.id == primaryID }) {
                primaryID = primaryCategories.first?.id ?? ""
            }
            selectDefaultSecondary()
        }
        .onChange(of: primaryID) { _, _ in
            selectedBrand = "all"
            expandedItemID = nil
            resetQuickEntry()
            selectDefaultSecondary()
        }
        .alert("永久删除这个物品？", isPresented: Binding(
            get: { deleteCandidate != nil },
            set: { if !$0 { deleteCandidate = nil } }
        ), presenting: deleteCandidate) { item in
            Button("取消", role: .cancel) { deleteCandidate = nil }
            Button("删除", role: .destructive) {
                store.permanentlyDeletePetItem(id: item.id)
                deleteCandidate = nil
            }
        } message: { item in
            Text("“\(item.displayTitle)”及其库存、价格和评价记录会被永久删除，无法恢复。")
        }
        .sheet(item: $quickBatchAllocationRequest) { request in
            PetInventoryBatchAllocationSheet(requests: [request]) { quantities in
                completeQuickAction(for: request.productID, batchGroupQuantities: quantities[request.productID])
            }
        }
        .navigationDestination(item: $route) { route in
            switch route {
            case .detail(let itemID):
                PetItemDetailView(itemID: itemID)
            case .ratings:
                PetRatingsListView()
            case .editor(let primaryID, let secondaryID):
                PetItemEditorView(initialPrimaryID: primaryID, initialSecondaryID: secondaryID)
            case .pendingRepurchase:
                PetPendingRepurchaseView()
            case .noRepurchase:
                PetNoRepurchaseLibraryView()
            }
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            headerContent
            Spacer(minLength: 12)
            Menu {
                Menu {
                    brandMenuButton(title: "全部品牌", value: "all")
                    ForEach(availableBrands, id: \.self) { brand in
                        brandMenuButton(title: brand, value: brand)
                    }
                } label: {
                    Label(selectedBrand == "all" ? "品牌筛选" : "品牌：\(selectedBrand)", systemImage: "tag")
                }
                Button {
                    route = .pendingRepurchase
                    NativeHaptics.selection()
                } label: {
                    Label("待回购", systemImage: "cart.badge.plus")
                }
                Button {
                    route = .noRepurchase
                    NativeHaptics.selection()
                } label: {
                    Label("不回购库", systemImage: "archivebox")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(HomeTheme.muted.opacity(0.72))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("宠物物品管理")
        }
    }

    private var panelRowInsets: EdgeInsets {
        .init(top: 0, leading: HomeMetrics.pageInset, bottom: 0, trailing: HomeMetrics.pageInset)
    }

    private var selectorPanelHeader: some View {
        VStack(spacing: 0) {
            primarySelector
                .padding(.horizontal, 14)
                .padding(.top, 10)
            secondaryAndSortRow
                .padding(.leading, 14)
                .padding(.trailing, 7)
                .padding(.bottom, 7)
        }
        .background(
            HomeTheme.card,
            in: UnevenRoundedRectangle(
                topLeadingRadius: 18,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 18,
                style: .continuous
            )
        )
    }

    private var panelBottomCap: some View {
        Color.clear
            .frame(height: 10)
            .background(
                HomeTheme.card,
                in: UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 18,
                    bottomTrailingRadius: 18,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )
    }

    private var panelDivider: some View {
        Rectangle()
            .fill(HomeTheme.line.opacity(0.72))
            .frame(height: 0.5)
            .padding(.horizontal, 14)
    }

    @ViewBuilder private func brandMenuButton(title: String, value: String) -> some View {
        Button {
            selectedBrand = value
            expandedItemID = nil
            resetQuickEntry()
            NativeHaptics.selection()
        } label: {
            if selectedBrand == value {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func openEditor() {
        NativeHaptics.tap()
        route = .editor(primaryID: primaryID, secondaryID: secondaryID)
    }

    @ViewBuilder private func nativeItemActions(_ item: PetItem) -> some View {
        Button {
            store.setPetItemRepurchase(id: item.id, willRepurchase: false)
        } label: {
            Label("不回购", systemImage: "cart.badge.minus")
        }
        .tint(HomeTheme.orange)
        Button(role: .destructive) {
            deleteCandidate = item
        } label: {
            Label("删除", systemImage: "trash")
        }
    }

    private func itemRow(_ item: PetItem) -> some View {
        let averagePriceText = PetItemHomepageAveragePrice.text(
            average: store.petWeightedAverageInboundUnitPrice(for: item.id),
            unit: item.unit
        )
        let expirationText = store.petInventoryEarliestExpirationDate(for: item.id)
            .map(petExpirationDisplayDate) ?? "未设日期"
        return HStack(spacing: 0) {
            Button {
                NativeHaptics.tap()
                route = .detail(itemID: item.id)
            } label: {
                PetProductThumbnail(item: item)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看\(item.name)详情")

            Button {
                toggleQuickManager(for: item)
            } label: {
                HStack(spacing: 11) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "无品牌" : item.brand)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(HomeTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        HStack(spacing: 4) {
                            Text(item.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(HomeTheme.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                                .layoutPriority(1)
                            if let flavor = item.displayVariant {
                                Text(flavor)
                                    .font(.system(size: 13))
                                    .foregroundStyle(HomeTheme.muted)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                            }
                        }
                        Text(expirationText)
                            .font(.system(size: 11))
                            .foregroundStyle(HomeTheme.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 5) {
                        if let rating = store.petProductRating(productID: item.id) {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Image(systemName: "star.fill")
                                Text(rating.overall.formatted(.number.precision(.fractionLength(1))))
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(HomeTheme.orange)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        } else {
                            Text("未评分")
                                .font(.system(size: 11))
                                .foregroundStyle(HomeTheme.muted)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        Text(averagePriceText ?? "—")
                            .font(.system(size: 12))
                            .foregroundStyle(averagePriceText == nil ? HomeTheme.muted : HomeTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(specificationAndStock(item))
                            .font(.system(size: 12))
                            .foregroundStyle(HomeTheme.muted)
                            .lineLimit(1)
                    }
                    .frame(width: 106, alignment: .trailing)
                    .frame(minHeight: 56, alignment: .trailing)
                }
                .padding(.leading, 11)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("展开\(item.name)快捷操作")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func quickManagerRow(_ item: PetItem) -> some View {
        compactQuickManager(item)
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
            .background(HomeTheme.card)
            .listRowInsets(panelRowInsets)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .id("quick-manager-\(item.id)")
    }

    private var primarySelector: some View {
        HStack(spacing: 4) {
            ForEach(primaryCategories) { category in
                Button {
                    primaryID = category.id
                    NativeHaptics.selection()
                } label: {
                    HomeUnderlineTab(
                        title: category.name,
                        selected: primaryID == category.id,
                        prominent: true
                    )
                    .padding(.horizontal, 6)
                    .frame(minWidth: HomeMetrics.minimumTapTarget, minHeight: HomeMetrics.minimumTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 0)
            Button {
                NativeHaptics.tap()
                route = .ratings
            } label: {
                VStack(spacing: 8) {
                    Text("评价")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(HomeTheme.muted)
                        .frame(height: 19, alignment: .center)
                    Capsule().fill(Color.clear).frame(width: 28, height: 3)
                }
                .frame(minWidth: 46, minHeight: HomeMetrics.minimumTapTarget, alignment: .center)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("进入物品评价")
            Button(action: openEditor) {
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(HomeTheme.muted)
                        .frame(height: 19, alignment: .center)
                    Capsule().fill(Color.clear).frame(width: 28, height: 3)
                }
                .frame(minWidth: 44, minHeight: HomeMetrics.minimumTapTarget, alignment: .center)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("新增宠物物品")
        }
    }

    private var secondaryAndSortRow: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(secondaryCategories) { category in
                        Button {
                            secondaryID = category.id
                            expandedItemID = nil
                            resetQuickEntry()
                            NativeHaptics.selection()
                        } label: {
                            HomeUnderlineTab(
                                title: category.name,
                                selected: secondaryID == category.id
                            )
                            .padding(.horizontal, 2)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(minHeight: HomeMetrics.minimumTapTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
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
                VStack(spacing: 5) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(HomeTheme.muted)
                        .frame(height: 17, alignment: .center)
                    Capsule().fill(Color.clear).frame(width: 20, height: 3)
                }
                    .frame(width: 44, height: HomeMetrics.minimumTapTarget, alignment: .center)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("排序：\(sortMode.title)")
        }
    }

    private func selectDefaultSecondary() {
        guard !secondaryCategories.isEmpty else {
            secondaryID = ""
            return
        }
        if secondaryCategories.contains(where: { $0.id == secondaryID }) { return }
        let preferredNames: [String]
        if selectedPrimary?.capabilityKey == "petFood" {
            preferredNames = ["主食罐"]
        } else {
            preferredNames = ["矿砂", "猫砂"]
        }
        secondaryID = preferredNames.compactMap { name in
            secondaryCategories.first { $0.name == name }?.id
        }.first ?? secondaryCategories.first?.id ?? ""
    }

    private func compactQuickManager(_ item: PetItem) -> some View {
        VStack(spacing: 6) {
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
                    TextField("¥0.00", text: $quickTotalPriceText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.leading)
                        .font(.system(size: 14))
                    Spacer()
                    Text(quickUnitPrice(item).map { "单价 ¥\($0.formatted(.number.precision(.fractionLength(2))))/\(item.unit)" } ?? "单价自动计算")
                        .font(.system(size: 12))
                        .foregroundStyle(HomeTheme.muted)
                }
                .frame(minHeight: 36)
                Toggle("记录到期日期", isOn: $quickHasExpiration)
                    .font(.system(size: 13))
                if quickHasExpiration {
                    DatePicker("到期日期", selection: $quickExpirationDate, displayedComponents: .date)
                        .font(.system(size: 13))
                }
                HStack(spacing: 8) {
                    Text("本次备注").font(.system(size: 13)).foregroundStyle(HomeTheme.muted)
                    TextField("可选", text: $quickNote)
                        .font(.system(size: 14))
                }
                .frame(minHeight: 32)
            }
        }
        .onChange(of: quickMode) { _, _ in
            resetQuickEntry(for: item)
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
        if quickMode == .outbound {
            let groups = store.petInventoryBatchGroups(for: item.id)
            if quickQuantity <= store.petInventory(for: item.id), groups.count > 1 {
                quickBatchAllocationRequest = PetInventoryBatchAllocationRequest(
                    productID: item.id,
                    productName: item.displayTitle,
                    quantity: quickQuantity,
                    unit: item.unit,
                    groups: groups
                )
                return
            }
        }
        completeQuickAction(for: item.id)
    }

    private func completeQuickAction(
        for productID: String,
        batchGroupQuantities: [String: Double]? = nil
    ) {
        guard let item = store.data.petItems.first(where: { $0.id == productID }) else { return }
        let note = quickNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let success = store.recordPetInventory(
            productID: item.id,
            type: quickMode,
            quantity: quickQuantity,
            occurrenceDate: LitterPredictionService.format(Date()),
            reason: quickMode == .inbound ? "快捷入库" : "快捷出库",
            totalPrice: quickMode == .inbound ? parsedQuickTotalPrice : nil,
            expirationDate: quickMode == .inbound && quickHasExpiration
                ? LitterPredictionService.format(quickExpirationDate)
                : nil,
            note: quickMode == .inbound && !note.isEmpty ? note : nil,
            batchGroupQuantities: batchGroupQuantities
        )
        if success {
            expandedItemID = nil
            resetQuickEntry()
        }
    }

    private func quickStep(for item: PetItem) -> Double {
        ["kg", "公斤", "千克", "l", "L", "升"].contains(item.unit) ? 0.1 : 1
    }

    private func quickUnitPrice(_ item: PetItem) -> Double? {
        guard quickMode == .inbound, quickQuantity.isFinite, quickQuantity > 0,
              let price = parsedQuickTotalPrice else { return nil }
        return price / quickQuantity
    }

    private var parsedQuickTotalPrice: Double? {
        let normalized = quickTotalPriceText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let price = Double(normalized), price.isFinite, price > 0 else { return nil }
        return price
    }

    private func toggleQuickManager(for item: PetItem) {
        if expandedItemID == item.id {
            expandedItemID = nil
            resetQuickEntry()
        } else {
            expandedItemID = item.id
            quickMode = store.petInventory(for: item.id) <= 0 ? .inbound : .outbound
            resetQuickEntry(for: item)
        }
        NativeHaptics.selection()
    }

    private func resetQuickEntry(for item: PetItem? = nil) {
        quickQuantity = item.map { quickStep(for: $0) } ?? 1
        quickTotalPriceText = ""
        quickNote = ""
        quickHasExpiration = false
        quickExpirationDate = Date()
    }

    private func specificationAndStock(_ item: PetItem) -> String {
        let quantity = store.petInventory(for: item.id).formatted()
        let package = (item.packageType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let stockText = "\(quantity)\(package.isEmpty ? item.unit : package)"
        let spec = item.spec.trimmingCharacters(in: .whitespacesAndNewlines)
        return spec.isEmpty ? stockText : "\(spec) × \(stockText)"
    }

}

private struct PetProductThumbnail: View {
    let item: PetItem

    @ViewBuilder
    var body: some View {
        if let image = item.image, !image.isEmpty {
            PetStoredImage(reference: image)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Image(systemName: item.resolvedSecondaryCategory == "猫砂" ? "circle.hexagongrid.fill" : "takeoutbag.and.cup.and.straw.fill")
                .foregroundStyle(HomeTheme.blue)
                .frame(width: 48, height: 48)
                .background(HomeTheme.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private enum PetItemsRoute: Hashable {
    case detail(itemID: String)
    case ratings
    case editor(primaryID: String, secondaryID: String)
    case pendingRepurchase
    case noRepurchase
}

private enum PetItemListSortMode: String, CaseIterable, Identifiable {
    case smart, createdNewest, ratingHigh, stockHigh, brandAndModel, expiryNearest
    var id: String { rawValue }
    var title: String {
        switch self {
        case .smart: "智能排序"
        case .createdNewest: "最近添加"
        case .ratingHigh: "评分从高到低"
        case .stockHigh: "库存从高到低"
        case .brandAndModel: "品牌 / 同款"
        case .expiryNearest: "保质期由近到远"
        }
    }
}

struct PetRatingsListView: View {
    @EnvironmentObject private var store: HomeStore
    @State private var primaryID = "pet-root-food"
    @State private var secondaryID = ""
    @State private var ratingSubjectID = "overall"
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
            guard let selectedPrimary,
                  let secondaryName = secondaryCategories.first(where: { $0.id == secondaryID })?.name,
                  store.petProductRating(productID: item.id) != nil else { return false }
            return item.resolvedPrimaryCategory == selectedPrimary.name
                && item.resolvedSecondaryCategory == secondaryName
                && (selectedBrand == "all" || item.brand == selectedBrand)
        }
        return filtered.sorted { left, right in
            switch sortMode {
            case .name:
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            case .scoreHigh, .scoreLow:
                let leftRating = ratingSummary(for: left)?.overall
                let rightRating = ratingSummary(for: right)?.overall
                switch (leftRating, rightRating) {
                case let (.some(leftScore), .some(rightScore)):
                    if leftScore == rightScore { return left.name < right.name }
                    return sortMode == .scoreHigh ? leftScore > rightScore : leftScore < rightScore
                case (.some(_), .none): return true
                case (.none, .some(_)): return false
                case (.none, .none): return left.name < right.name
                }
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
                    HStack(spacing: 14) {
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
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(secondaryCategories) { category in ratingFilter(title: category.name, id: category.id) }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 2)
                    HStack(spacing: 4) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 0) {
                                ratingSubjectButton(title: "整体", id: "overall")
                                if selectedPrimary?.capabilityKey == "petFood" {
                                    ForEach(store.activePets) { pet in
                                        ratingSubjectButton(title: pet.name, id: pet.id)
                                    }
                                }
                            }
                            .padding(.horizontal, 3)
                            .background(HomeTheme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        Spacer(minLength: 4)
                        Menu {
                            Button("全部品牌") { selectedBrand = "all" }
                            ForEach(availableBrands, id: \.self) { brand in
                                Button(brand) { selectedBrand = brand }
                            }
                        } label: {
                            Image(systemName: "tag")
                                .frame(width: 34, height: 32)
                        }
                        Menu {
                            ForEach(PetRatingSortMode.allCases) { mode in
                                Button(mode.title) { sortMode = mode }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .frame(width: 34, height: 32)
                        }
                    }
                    .font(HomeTypography.supporting.weight(.medium))
                    .foregroundStyle(HomeTheme.muted)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
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
            selectDefaultRatingSecondary()
            if ratingSubjectID != "overall", !store.activePets.contains(where: { $0.id == ratingSubjectID }) {
                ratingSubjectID = "overall"
            }
        }
        .onChange(of: primaryID) { _, _ in
            selectedBrand = "all"
            if selectedPrimary?.capabilityKey != "petFood" { ratingSubjectID = "overall" }
            selectDefaultRatingSecondary()
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

    private func selectDefaultRatingSecondary() {
        guard !secondaryCategories.isEmpty else {
            secondaryID = ""
            return
        }
        if secondaryCategories.contains(where: { $0.id == secondaryID }) { return }
        let preferredNames = selectedPrimary?.capabilityKey == "petFood"
            ? ["主食罐"]
            : ["矿砂", "猫砂"]
        secondaryID = preferredNames.compactMap { name in
            secondaryCategories.first { $0.name == name }?.id
        }.first ?? secondaryCategories.first?.id ?? ""
    }

    private func ratingSubjectButton(title: String, id: String) -> some View {
        Button {
            ratingSubjectID = id
            NativeHaptics.selection()
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ratingSubjectID == id ? HomeTheme.blue : HomeTheme.muted)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .frame(height: 30)
                .contentShape(Rectangle())
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
                    Text(item.displayNameAndVariant)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(HomeTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if ratingSubjectID == "overall", let summary = store.petProductRating(productID: item.id) {
                        Text(dimensionSummary(item: item, rating: summary))
                            .font(.system(size: 12))
                            .foregroundStyle(HomeTheme.muted)
                            .lineLimit(2)
                    } else if let note = latestPetNote(for: item) {
                        Text(note)
                            .font(.system(size: 12))
                            .foregroundStyle(HomeTheme.muted)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 6)
                if let summary = ratingSummary(for: item) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(summary.overall.formatted(.number.precision(.fractionLength(1))))
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundStyle(HomeTheme.blue)
                        Text("\(summary.count)次评价").font(.system(size: 11)).foregroundStyle(HomeTheme.muted)
                    }
                } else {
                    Text("未评分")
                        .font(.system(size: 12))
                        .foregroundStyle(HomeTheme.muted)
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

    private func ratingSummary(for item: PetItem) -> (overall: Double, count: Int)? {
        if ratingSubjectID == "overall" {
            guard let summary = store.petProductRating(productID: item.id) else { return nil }
            return (summary.overall, summary.count)
        }
        return store.petPalatabilityRating(productID: item.id, petID: ratingSubjectID)
    }

    private func latestPetNote(for item: PetItem) -> String? {
        guard ratingSubjectID != "overall" else { return nil }
        let review = store.data.petPalatabilityReviews
            .filter { $0.productID == item.id && $0.petID == ratingSubjectID }
            .max {
                $0.reviewDate == $1.reviewDate
                    ? $0.createdAt < $1.createdAt
                    : $0.reviewDate < $1.reviewDate
            }
        guard let note = review?.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else { return nil }
        return note
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
                        if let flavor = item.displayVariant {
                            Text(flavor).font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                        }
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

struct PetPendingRepurchaseView: View {
    @EnvironmentObject private var store: HomeStore
    @State private var primaryID = ""
    @State private var secondaryID = ""
    @State private var detailItemID: String?

    private var primaryCategories: [ManagedCategory] { store.categories(for: .pet) }
    private var selectedPrimary: ManagedCategory? {
        primaryCategories.first { $0.id == primaryID }
            ?? primaryCategories.first { $0.capabilityKey == "petFood" }
            ?? primaryCategories.first
    }
    private var secondaryCategories: [ManagedCategory] {
        selectedPrimary.map { store.categories(for: .pet, parentID: $0.id) } ?? []
    }
    private var selectedSecondary: ManagedCategory? {
        secondaryCategories.first { $0.id == secondaryID } ?? preferredSecondary
    }
    private var preferredSecondary: ManagedCategory? {
        let preferredNames = selectedPrimary?.capabilityKey == "petFood" ? ["主食罐"] : ["矿砂"]
        return preferredNames.compactMap { name in secondaryCategories.first { $0.name == name } }.first
            ?? secondaryCategories.first
    }
    private var items: [PetItem] {
        guard let selectedPrimary, let selectedSecondary else { return [] }
        return PetPendingRepurchaseFilter.items(
            from: store.activePetItems,
            primaryCategory: selectedPrimary.name,
            secondaryCategory: selectedSecondary.name,
            inventoryForItem: { store.petInventory(for: $0) }
        )
            .sorted {
                let left = $0.updatedAt ?? $0.createdAt ?? 0
                let right = $1.updatedAt ?? $1.createdAt ?? 0
                return left == right ? $0.name < $1.name : left > right
            }
    }

    var body: some View {
        List {
            categorySelectorPanel
                .listRowInsets(.init(top: 10, leading: HomeMetrics.pageInset, bottom: 0, trailing: HomeMetrics.pageInset))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if items.isEmpty {
                VStack(spacing: 12) {
                    EmptyState(
                        icon: "cart.badge.plus",
                        title: "暂无待回购商品",
                        message: "“\(selectedSecondary?.name ?? selectedPrimary?.name ?? "当前")”分类里没有库存为 0 且计划回购的商品。"
                    )
                    .padding(.vertical, 10)
                }
                .background(HomeTheme.card)
                .overlay(alignment: .top) { panelDivider }
                .listRowInsets(panelRowInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(items) { item in
                    pendingItemRow(item)
                        .background(HomeTheme.card)
                        .overlay(alignment: .top) { panelDivider }
                        .listRowInsets(panelRowInsets)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            panelBottomCap
                .listRowInsets(panelRowInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 1)
        .scrollContentBackground(.hidden)
        .background(HomeTheme.background)
        .scrollIndicators(.hidden)
        .navigationTitle("待回购")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $detailItemID) { itemID in
            PetItemDetailView(itemID: itemID)
        }
        .onAppear(perform: synchronizeSelections)
        .onChange(of: primaryID) { _, _ in
            secondaryID = preferredSecondary?.id ?? ""
            NativeHaptics.selection()
        }
        .onChange(of: primaryCategories.map(\.id)) { _, _ in synchronizeSelections() }
        .onChange(of: secondaryCategories.map(\.id)) { _, _ in synchronizeSelections() }
    }

    private var categorySelectorPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(primaryCategories) { category in
                    Button {
                        primaryID = category.id
                    } label: {
                        HomeUnderlineTab(
                            title: category.name,
                            selected: selectedPrimary?.id == category.id,
                            prominent: true
                        )
                        .padding(.horizontal, 6)
                        .frame(minWidth: HomeMetrics.minimumTapTarget, minHeight: HomeMetrics.minimumTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(secondaryCategories) { category in
                        Button {
                            secondaryID = category.id
                            NativeHaptics.selection()
                        } label: {
                            HomeUnderlineTab(title: category.name, selected: selectedSecondary?.id == category.id)
                                .padding(.horizontal, 2)
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(minHeight: HomeMetrics.minimumTapTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 7)
            .padding(.bottom, 7)
        }
        .background(
            HomeTheme.card,
            in: UnevenRoundedRectangle(
                topLeadingRadius: 18,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 18,
                style: .continuous
            )
        )
    }

    private var panelRowInsets: EdgeInsets {
        .init(top: 0, leading: HomeMetrics.pageInset, bottom: 0, trailing: HomeMetrics.pageInset)
    }

    private var panelDivider: some View {
        Rectangle()
            .fill(HomeTheme.line.opacity(0.72))
            .frame(height: 0.5)
            .padding(.horizontal, 14)
    }

    private var panelBottomCap: some View {
        Color.clear
            .frame(height: 10)
            .background(
                HomeTheme.card,
                in: UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 18,
                    bottomTrailingRadius: 18,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )
    }

    private func synchronizeSelections() {
        if !primaryCategories.contains(where: { $0.id == primaryID }) {
            primaryID = primaryCategories.first(where: { $0.capabilityKey == "petFood" })?.id
                ?? primaryCategories.first?.id
                ?? ""
        }
        if !secondaryCategories.contains(where: { $0.id == secondaryID }) {
            secondaryID = preferredSecondary?.id ?? ""
        }
    }

    private func pendingItemRow(_ item: PetItem) -> some View {
        let averagePriceText = PetItemHomepageAveragePrice.text(
            average: store.petWeightedAverageInboundUnitPrice(for: item.id),
            unit: item.unit
        )
        let expirationText = store.petInventoryEarliestExpirationDate(for: item.id)
            .map(petExpirationDisplayDate) ?? "未设日期"
        return Button {
            NativeHaptics.tap()
            detailItemID = item.id
        } label: {
            HStack(spacing: 0) {
                PetProductThumbnail(item: item)
                HStack(spacing: 11) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "无品牌" : item.brand)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(HomeTheme.ink)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(item.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(HomeTheme.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                                .layoutPriority(1)
                            if let flavor = item.displayVariant {
                                Text(flavor)
                                    .font(.system(size: 13))
                                    .foregroundStyle(HomeTheme.muted)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                            }
                        }
                        Text(expirationText)
                            .font(.system(size: 11))
                            .foregroundStyle(HomeTheme.muted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 5) {
                        if let rating = store.petProductRating(productID: item.id) {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Image(systemName: "star.fill")
                                Text(rating.overall.formatted(.number.precision(.fractionLength(1))))
                            }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(HomeTheme.orange)
                                .lineLimit(1)
                        } else {
                            Text("未评分")
                                .font(.system(size: 11))
                                .foregroundStyle(HomeTheme.muted)
                                .lineLimit(1)
                        }
                        Text(averagePriceText ?? "—")
                            .font(.system(size: 12))
                            .foregroundStyle(averagePriceText == nil ? HomeTheme.muted : HomeTheme.ink)
                            .lineLimit(1)
                        Text(specificationAndStock(item))
                            .font(.system(size: 12))
                            .foregroundStyle(HomeTheme.muted)
                            .lineLimit(1)
                    }
                    .frame(width: 106, alignment: .trailing)
                    .frame(minHeight: 56, alignment: .trailing)
                }
                .padding(.leading, 11)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                store.setPetItemRepurchase(id: item.id, willRepurchase: false)
            } label: {
                Label("不回购", systemImage: "cart.badge.minus")
            }
            .tint(HomeTheme.orange)
        }
    }

    private func specificationAndStock(_ item: PetItem) -> String {
        let quantity = store.petInventory(for: item.id).formatted()
        let package = (item.packageType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let stockText = "\(quantity)\(package.isEmpty ? item.unit : package)"
        let spec = item.spec.trimmingCharacters(in: .whitespacesAndNewlines)
        return spec.isEmpty ? stockText : "\(spec) × \(stockText)"
    }
}

struct PetNoRepurchaseLibraryView: View {
    @EnvironmentObject private var store: HomeStore
    @State private var primaryID = ""
    @State private var secondaryID = ""
    @State private var detailItemID: String?
    @State private var deleteCandidate: PetItem?

    private var primaryCategories: [ManagedCategory] { store.categories(for: .pet) }
    private var selectedPrimary: ManagedCategory? {
        primaryCategories.first { $0.id == primaryID }
            ?? primaryCategories.first { $0.capabilityKey == "petFood" }
            ?? primaryCategories.first
    }
    private var secondaryCategories: [ManagedCategory] {
        selectedPrimary.map { store.categories(for: .pet, parentID: $0.id) } ?? []
    }
    private var selectedSecondary: ManagedCategory? {
        secondaryCategories.first { $0.id == secondaryID } ?? preferredSecondary
    }
    private var preferredSecondary: ManagedCategory? {
        let preferredNames = selectedPrimary?.capabilityKey == "petFood" ? ["主食罐"] : ["矿砂"]
        return preferredNames.compactMap { name in secondaryCategories.first { $0.name == name } }.first
            ?? secondaryCategories.first
    }
    private var items: [PetItem] {
        guard let selectedPrimary, let selectedSecondary else { return [] }
        return store.data.petItems
            .filter {
                !$0.resolvedWillRepurchase
                    && $0.resolvedPrimaryCategory == selectedPrimary.name
                    && $0.resolvedSecondaryCategory == selectedSecondary.name
            }
            .sorted {
                let left = $0.updatedAt ?? $0.createdAt ?? 0
                let right = $1.updatedAt ?? $1.createdAt ?? 0
                return left == right ? $0.name < $1.name : left > right
            }
    }

    var body: some View {
        List {
            categorySelectorPanel
                .listRowInsets(.init(top: 10, leading: HomeMetrics.pageInset, bottom: 0, trailing: HomeMetrics.pageInset))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if items.isEmpty {
                EmptyState(
                    icon: "archivebox",
                    title: "不回购库为空",
                    message: "“\(selectedSecondary?.name ?? selectedPrimary?.name ?? "当前")”分类里没有设置为不回购的商品。"
                )
                .padding(.vertical, 10)
                .background(HomeTheme.card)
                .overlay(alignment: .top) { panelDivider }
                .listRowInsets(panelRowInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(items) { item in
                    noRepurchaseItemRow(item)
                        .background(HomeTheme.card)
                        .overlay(alignment: .top) { panelDivider }
                        .listRowInsets(panelRowInsets)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                store.setPetItemRepurchase(id: item.id, willRepurchase: true)
                            } label: {
                                Label("恢复回购", systemImage: "cart.badge.plus")
                            }
                            .tint(HomeTheme.success)
                            Button(role: .destructive) { deleteCandidate = item } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                }
            }

            panelBottomCap
                .listRowInsets(panelRowInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 1)
        .scrollContentBackground(.hidden)
        .background(HomeTheme.background)
        .scrollIndicators(.hidden)
        .navigationTitle("不回购库")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $detailItemID) { itemID in
            PetItemDetailView(itemID: itemID)
        }
        .onAppear(perform: synchronizeSelections)
        .onChange(of: primaryID) { _, _ in
            secondaryID = preferredSecondary?.id ?? ""
            NativeHaptics.selection()
        }
        .onChange(of: primaryCategories.map(\.id)) { _, _ in synchronizeSelections() }
        .onChange(of: secondaryCategories.map(\.id)) { _, _ in synchronizeSelections() }
        .alert("永久删除这个物品？", isPresented: Binding(
            get: { deleteCandidate != nil },
            set: { if !$0 { deleteCandidate = nil } }
        ), presenting: deleteCandidate) { item in
            Button("取消", role: .cancel) { deleteCandidate = nil }
            Button("删除", role: .destructive) {
                store.permanentlyDeletePetItem(id: item.id)
                deleteCandidate = nil
            }
        } message: { item in
            Text("“\(item.displayTitle)”及其历史记录会被永久删除。")
        }
    }

    private var categorySelectorPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(primaryCategories) { category in
                    Button {
                        primaryID = category.id
                    } label: {
                        HomeUnderlineTab(
                            title: category.name,
                            selected: selectedPrimary?.id == category.id,
                            prominent: true
                        )
                        .padding(.horizontal, 6)
                        .frame(minWidth: HomeMetrics.minimumTapTarget, minHeight: HomeMetrics.minimumTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(secondaryCategories) { category in
                        Button {
                            secondaryID = category.id
                            NativeHaptics.selection()
                        } label: {
                            HomeUnderlineTab(title: category.name, selected: selectedSecondary?.id == category.id)
                                .padding(.horizontal, 2)
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(minHeight: HomeMetrics.minimumTapTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 7)
            .padding(.bottom, 7)
        }
        .background(
            HomeTheme.card,
            in: UnevenRoundedRectangle(
                topLeadingRadius: 18,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 18,
                style: .continuous
            )
        )
    }

    private var panelRowInsets: EdgeInsets {
        .init(top: 0, leading: HomeMetrics.pageInset, bottom: 0, trailing: HomeMetrics.pageInset)
    }

    private var panelDivider: some View {
        Rectangle()
            .fill(HomeTheme.line.opacity(0.72))
            .frame(height: 0.5)
            .padding(.horizontal, 14)
    }

    private var panelBottomCap: some View {
        Color.clear
            .frame(height: 10)
            .background(
                HomeTheme.card,
                in: UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 18,
                    bottomTrailingRadius: 18,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )
    }

    private func synchronizeSelections() {
        if !primaryCategories.contains(where: { $0.id == primaryID }) {
            primaryID = primaryCategories.first(where: { $0.capabilityKey == "petFood" })?.id
                ?? primaryCategories.first?.id
                ?? ""
        }
        if !secondaryCategories.contains(where: { $0.id == secondaryID }) {
            secondaryID = preferredSecondary?.id ?? ""
        }
    }

    private func noRepurchaseItemRow(_ item: PetItem) -> some View {
        Button {
            NativeHaptics.tap()
            detailItemID = item.id
        } label: {
            HStack(spacing: 0) {
                PetProductThumbnail(item: item)
                HStack(spacing: 11) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "无品牌" : item.brand)
                            .font(.system(size: 12))
                            .foregroundStyle(HomeTheme.muted)
                            .lineLimit(1)
                        Text(item.displayNameAndVariant)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(HomeTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.84)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(specificationAndStock(item))
                            .font(.system(size: 12))
                            .foregroundStyle(HomeTheme.muted)
                            .lineLimit(1)
                        Text("不回购")
                            .font(.system(size: 12))
                            .foregroundStyle(HomeTheme.muted)
                    }
                    .frame(width: 106, alignment: .trailing)
                    .frame(minHeight: 48, alignment: .trailing)
                }
                .padding(.leading, 11)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func specificationAndStock(_ item: PetItem) -> String {
        let quantity = store.petInventory(for: item.id).formatted()
        let package = (item.packageType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let stockText = "\(quantity)\(package.isEmpty ? item.unit : package)"
        let spec = item.spec.trimmingCharacters(in: .whitespacesAndNewlines)
        return spec.isEmpty ? stockText : "\(spec) × \(stockText)"
    }
}

struct PetItemDetailView: View {
    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    let itemID: String
    @State private var showArchive = false
    @State private var sheet: PetItemDetailSheet?
    @State private var expandedPalatabilityPetIDs = Set<String>()
    private var item: PetItem? { store.data.petItems.first { $0.id == itemID } }

    var body: some View {
        ScrollView {
            if let item {
                LazyVStack(alignment: .leading, spacing: HomeMetrics.sectionSpacing) {
                    productHeroCard(item)
                    inventoryCard(item)
                    productReviewCard
                    if isPetFood(item) { palatabilityCard }
                    priceCard(item)
                    productNotesCard(item)
                    transactionCard(item)
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
                    Menu {
                        NavigationLink {
                            PetItemEditorView(copyingItemID: item.id)
                        } label: {
                            Label("复制商品", systemImage: "doc.on.doc")
                        }
                        Button { showArchive = true } label: {
                            Label(
                                item.resolvedWillRepurchase ? "设为不回购" : "恢复回购",
                                systemImage: item.resolvedWillRepurchase ? "cart.badge.minus" : "cart.badge.plus"
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("更多商品操作")
                }
            }
        }
        .sheet(item: $sheet) { value in
            switch value {
            case .inbound: PetInventoryEditorView(productID: itemID, mode: .inbound)
            case .outbound: PetInventoryEditorView(productID: itemID, mode: .outbound)
            case .adjustment: PetInventoryEditorView(productID: itemID, mode: .adjustment)
            case .productReview(let reviewID): PetProductReviewEditorView(productID: itemID, reviewID: reviewID)
            case .palatability(let reviewID): PetPalatabilityEditorView(productID: itemID, reviewID: reviewID)
            case .image: PetItemImageEditorSheet(itemID: itemID, initialImage: item?.image)
            case .transaction(let transactionID): PetInventoryTransactionEditorView(transactionID: transactionID)
            }
        }
        .alert(item?.resolvedWillRepurchase == false ? "恢复回购这个物品？" : "设为不回购？", isPresented: $showArchive) {
            Button("取消", role: .cancel) {}
            Button(item?.resolvedWillRepurchase == false ? "恢复回购" : "不回购") {
                store.setPetItemRepurchase(id: itemID, willRepurchase: item?.resolvedWillRepurchase == false)
                dismiss()
            }
        } message: {
            Text(item?.resolvedWillRepurchase == false
                ? "恢复后，有库存时回到当前列表；库存为 0 时进入待回购。"
                : "产品会移入不回购库，但库存、价格、评价和历史记录都会保留。")
        }
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
                    Text(item.displayNameAndVariant)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(HomeTheme.ink)
                    productSpecificationLine(item)
                    Text("\(item.resolvedPrimaryCategory) · \(item.resolvedSecondaryCategory)")
                        .font(HomeTypography.supporting)
                        .foregroundStyle(HomeTheme.muted)
                }
                Spacer(minLength: 4)
            }
        }
    }

    @ViewBuilder
    private func productNotesCard(_ item: PetItem) -> some View {
        let note = item.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !note.isEmpty {
            HomeCard(padding: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("备注").font(HomeTypography.cardTitle)
                    Text(note).font(HomeTypography.body).foregroundStyle(HomeTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func inventoryCard(_ item: PetItem) -> some View {
        let expiryGroups = store.petInventoryBatchBreakdown(for: item.id)
        return HomeCard(padding: 12) {
            VStack(spacing: 9) {
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
                if !expiryGroups.isEmpty {
                    Divider().overlay(HomeTheme.line)
                    VStack(spacing: 4) {
                        ForEach(expiryGroups) { group in
                            HStack {
                                Text(group.expirationDate.map(petExpirationDisplayDate) ?? "未设日期")
                                    .foregroundStyle(HomeTheme.muted)
                                Spacer()
                                Text("\(group.remainingQuantity.formatted())\(item.unit)")
                                    .foregroundStyle(HomeTheme.ink)
                            }
                            .font(HomeTypography.supporting)
                            .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private func transactionCard(_ item: PetItem) -> some View {
        let allRecords = store.petTransactions(for: item.id)
        let recentRecord = allRecords.first
        return HomeCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("进出库记录").font(HomeTypography.cardTitle)
                    Text("共 \(allRecords.count) 条")
                        .font(HomeTypography.supporting)
                        .foregroundStyle(HomeTheme.muted)
                    Spacer()
                    NavigationLink {
                        PetInventoryTransactionHistoryView(productID: item.id, priceHistoryOnly: false) { transactionID in
                            sheet = .transaction(transactionID: transactionID)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("查看全部").font(HomeTypography.supporting)
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(HomeTheme.muted)
                    }
                    .buttonStyle(.plain)
                }
                if let recentRecord {
                    Divider()
                    Text("最近 · \(HomeDateText.display(recentRecord.occurrenceDate)) · \(recentRecord.quantityChange > 0 ? "+" : "")\(recentRecord.quantityChange.formatted())\(recentRecord.unit)")
                        .font(HomeTypography.supporting)
                        .foregroundStyle(HomeTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                } else {
                    Text("暂无库存流水")
                        .font(HomeTypography.body)
                        .foregroundStyle(HomeTheme.muted)
                    }
            }
        }
    }

    private func priceCard(_ item: PetItem) -> some View {
        let records = store.petTransactions(for: item.id).filter {
            $0.recordedInboundTotalPrice != nil
        }
        let minimumUnitPrice = records.compactMap(\.recordedInboundUnitPrice).min()
        let recentUnitPrice = records.first?.recordedInboundUnitPrice
        let averageUnitPrice = store.petWeightedAverageInboundUnitPrice(for: item.id)
        return HomeCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("价格历史").font(HomeTypography.cardTitle)
                    Spacer()
                    if records.count > 4 {
                        NavigationLink {
                            PetInventoryTransactionHistoryView(productID: item.id, priceHistoryOnly: true) { transactionID in
                                sheet = .transaction(transactionID: transactionID)
                            }
                        } label: {
                            Text("查看全部").font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Text("日期").frame(maxWidth: .infinity, alignment: .leading)
                    Text("总价").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("单价").frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.system(size: 11))
                .foregroundStyle(HomeTheme.muted)
                ForEach(records.prefix(4)) { record in
                    Divider()
                    Button {
                        NativeHaptics.tap()
                        sheet = .transaction(transactionID: record.id)
                    } label: {
                        HStack {
                            Text(HomeDateText.display(record.occurrenceDate)).frame(maxWidth: .infinity, alignment: .leading)
                            Text(record.recordedInboundTotalPrice.map(currency2) ?? "未记录").frame(maxWidth: .infinity, alignment: .trailing)
                            Text(record.recordedInboundUnitPrice.map { "\(currency2($0))/\(record.unit)" } ?? "未记录").frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(HomeTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Divider()
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 16) {
                        Spacer(minLength: 0)
                        Text("最低 \(minimumUnitPrice.map { "\(currency2($0))/\(item.unit)" } ?? "暂无")")
                        Text("最近 \(recentUnitPrice.map { "\(currency2($0))/\(item.unit)" } ?? "暂无")")
                    }
                    Text("入库加权均价 \(averageUnitPrice.map { "\(currency2($0))/\(item.unit)" } ?? "暂无")")
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
                LazyVStack(spacing: 0) {
                    ForEach(records) { review in
                        Divider()
                        Button {
                            NativeHaptics.selection()
                            sheet = .productReview(reviewID: review.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Spacer(minLength: 4)
                                    Text("本次 \(review.overallScore.formatted(.number.precision(.fractionLength(1))))")
                                        .font(HomeTypography.cardTitle).foregroundStyle(HomeTheme.blue)
                                    Image(systemName: "pencil")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(HomeTheme.muted)
                                }
                                if !review.reviewText.isEmpty {
                                    Text(review.reviewText)
                                        .font(HomeTypography.body)
                                        .foregroundStyle(HomeTheme.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Text(orderedPetReviewDimensions(review.resolvedDimensionScores, item: item).map { dimension in
                                    "\(dimension) \(review.resolvedDimensionScores[dimension] ?? 0)"
                                }.joined(separator: " · "))
                                .font(HomeTypography.supporting)
                                .foregroundStyle(HomeTheme.muted)
                                Text(PetReviewDateText.display(review.reviewDate))
                                    .font(HomeTypography.supporting)
                                    .foregroundStyle(HomeTheme.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var palatabilityCard: some View {
        let groups = PetPalatabilityReviewGrouping.groups(
            productID: itemID,
            reviews: store.data.petPalatabilityReviews,
            activePets: store.activePets
        )
        return HomeCard {
            VStack(alignment: .leading, spacing: 9) {
                HomeSectionHeader(title: "猫咪评价", actionTitle: "添加") { sheet = .palatability(reviewID: nil) }
                if groups.isEmpty { Text("暂无猫咪评价").font(HomeTypography.body).foregroundStyle(HomeTheme.muted) }
                ForEach(groups) { group in
                    Divider()
                    palatabilityGroupView(group)
                }
            }
        }
    }

    @ViewBuilder
    private func palatabilityGroupView(_ group: PetPalatabilityReviewGroup) -> some View {
        if group.count == 1, let review = group.latestRecord {
            Button {
                NativeHaptics.selection()
                sheet = .palatability(reviewID: review.id)
            } label: {
                palatabilitySingleReviewRow(group: group, review: review)
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    togglePalatabilityGroup(group)
                } label: {
                    palatabilityGroupSummary(group)
                }
                .buttonStyle(.plain)

                if expandedPalatabilityPetIDs.contains(group.petID) {
                    LazyVStack(spacing: 0) {
                        ForEach(group.oldestFirstRecords) { review in
                            Divider()
                            palatabilityHistoryEntry(review)
                                .padding(.vertical, 5)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.leading, 10)
                }
            }
        }
    }

    private func togglePalatabilityGroup(_ group: PetPalatabilityReviewGroup) {
        if expandedPalatabilityPetIDs.contains(group.petID) {
            expandedPalatabilityPetIDs.remove(group.petID)
        } else {
            expandedPalatabilityPetIDs.insert(group.petID)
        }
        NativeHaptics.selection()
    }

    private func palatabilityGroupSummary(_ group: PetPalatabilityReviewGroup) -> some View {
        let average = store.petPalatabilityRating(productID: itemID, petID: group.petID)?.overall ?? group.averageScore
        let isExpanded = expandedPalatabilityPetIDs.contains(group.petID)
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(group.petName)
                        .font(HomeTypography.cardTitle)
                        .foregroundStyle(HomeTheme.ink)
                    if group.count > 1 {
                        Text("\(group.count)条")
                            .font(HomeTypography.supporting)
                            .foregroundStyle(HomeTheme.muted)
                    }
                }
                if !isExpanded,
                   let latest = group.latestRecord,
                   let note = latest.note?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !note.isEmpty {
                    Text(note)
                        .font(HomeTypography.supporting)
                        .foregroundStyle(HomeTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            Text("\(average.formatted(.number.precision(.fractionLength(1))))分")
                .font(HomeTypography.body)
                .foregroundStyle(palatabilityScoreColor(average))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func palatabilitySingleReviewRow(group: PetPalatabilityReviewGroup, review: PetPalatabilityReview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.petName)
                    .font(HomeTypography.cardTitle)
                    .foregroundStyle(HomeTheme.ink)
                Spacer(minLength: 4)
                Text("\(review.resolvedScore)分")
                    .font(HomeTypography.body)
                    .foregroundStyle(palatabilityScoreColor(Double(review.resolvedScore)))
            }
            if let note = review.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                Text(note)
                    .font(HomeTypography.supporting)
                    .foregroundStyle(HomeTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(PetReviewDateText.display(review.reviewDate))
                .font(HomeTypography.supporting)
                .foregroundStyle(HomeTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func palatabilityHistoryEntry(_ review: PetPalatabilityReview) -> some View {
        Button {
            NativeHaptics.selection()
            sheet = .palatability(reviewID: review.id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    if let note = review.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                        Text(note)
                            .font(HomeTypography.supporting)
                            .foregroundStyle(HomeTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Text("\(review.resolvedScore)分")
                        .font(HomeTypography.body)
                        .foregroundStyle(palatabilityScoreColor(Double(review.resolvedScore)))
                }
                Text(PetReviewDateText.display(review.reviewDate))
                    .font(HomeTypography.supporting)
                    .foregroundStyle(HomeTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private func productSpecificationLine(_ item: PetItem) -> some View {
        let specification = productSpecification(item)
        let averagePrice = store.petWeightedAverageInboundUnitPrice(for: item.id)
        let averagePriceText = PetItemHeroAveragePrice.text(average: averagePrice, unit: item.unit)
        return Group {
            if let averagePriceText {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(specification)
                        Text(averagePriceText)
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(specification)
                        Text(averagePriceText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(specification)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(HomeTypography.supporting)
        .foregroundStyle(HomeTheme.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func isPetFood(_ item: PetItem) -> Bool {
        item.resolvedPrimaryCategory == store.petRootCategory(capabilityKey: "petFood")?.name
    }
}

func petExpirationDisplayDate(_ storedDate: String) -> String {
    guard let date = LitterPredictionService.parse(storedDate) else { return storedDate }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy.MM.dd"
    return formatter.string(from: date)
}

private enum PetItemDetailSheet: Identifiable {
    case inbound
    case outbound
    case adjustment
    case productReview(reviewID: String?)
    case palatability(reviewID: String?)
    case image
    case transaction(transactionID: String)

    var id: String {
        switch self {
        case .inbound: "inbound"
        case .outbound: "outbound"
        case .adjustment: "adjustment"
        case .productReview(let reviewID): "product-review-\(reviewID ?? "new")"
        case .palatability(let reviewID): "palatability-\(reviewID ?? "new")"
        case .image: "image"
        case .transaction(let transactionID): "transaction-\(transactionID)"
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
func palatabilityScoreColor(_ score: Int) -> Color {
    score >= 4 ? HomeTheme.success : score <= 2 ? HomeTheme.danger : HomeTheme.muted
}
func palatabilityScoreColor(_ score: Double) -> Color {
    score >= 4 ? HomeTheme.success : score <= 2 ? HomeTheme.danger : HomeTheme.muted
}
func sourceText(_ value: PetInventorySource) -> String {
    switch value { case .manual: "手动"; case .migration: "旧数据迁移"; case .litterRefill: "猫砂补砂"; case .litterReplace: "猫砂换砂" }
}

func petRatingDimensions(_ item: PetItem) -> [String] {
    if item.resolvedPrimaryCategory.contains("食品") {
        return ["适口性", "品质", "性价比", "回购意愿"]
    }
    if item.isLitterProduct {
        return ["除臭性", "结团性", "耐用性", "性价比"]
    }
    return ["使用效果", "便利性", "耐用性", "性价比"]
}

func orderedPetReviewDimensions(_ scores: [String: Int], item: PetItem?) -> [String] {
    PetProductReviewDimensionOrdering.ordered(
        scores: scores,
        standardOrder: item.map(petRatingDimensions) ?? []
    )
}

func transactionTypeTitle(_ type: PetInventoryTransactionType) -> String {
    switch type {
    case .inbound: "入库"
    case .outbound: "出库"
    case .adjustment: "库存修正"
    }
}

func petTransactionAmountSummary(_ transaction: PetInventoryTransaction) -> String {
    switch transaction.type {
    case .inbound:
        guard let total = transaction.recordedInboundTotalPrice,
              let unit = transaction.recordedInboundUnitPrice else { return "价格未记录" }
        return "总价 \(currency2(total)) · 单价 \(currency2(unit))/\(transaction.unit)"
    case .outbound:
        guard let total = transaction.recordedOutboundTotalPrice,
              let unit = transaction.unitPrice, unit > 0 else { return "价格未记录 · 无法计算" }
        return "总价 \(currency2(total)) · 单价 \(currency2(unit))/\(transaction.unit)"
    case .adjustment:
        return "价格不适用"
    }
}

func currency2(_ value: Double) -> String {
    "¥\(value.formatted(.number.precision(.fractionLength(2))))"
}
