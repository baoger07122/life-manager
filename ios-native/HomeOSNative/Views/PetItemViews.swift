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
    @State private var primaryID = "pet-root-food"
    @State private var secondaryID = "all"
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
        store.activePetItems.filter {
            guard let selectedPrimary else { return false }
            let secondaryName = secondaryCategories.first { $0.id == secondaryID }?.name
            return $0.resolvedPrimaryCategory == selectedPrimary.name
                && (secondaryName == nil || $0.resolvedSecondaryCategory == secondaryName)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
                Divider()
                if items.isEmpty {
                    VStack(spacing: 12) {
                        EmptyState(icon: "shippingbox.fill", title: "暂无宠物物品", message: "按具体产品添加食品、猫砂或其他用品。")
                        NavigationLink("添加宠物物品") { PetItemEditorView() }
                            .buttonStyle(HomeSecondaryButtonStyle())
                            .padding(.horizontal, 14)
                            .padding(.bottom, 14)
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            itemRow(item)
                            if index < items.count - 1 { Divider() }
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
            expandedItemID = nil
        }
    }

    private func itemRow(_ item: PetItem) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                NavigationLink { PetItemDetailView(itemID: item.id) } label: {
                    HStack(spacing: 11) {
                        productImage(item)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "无品牌" : item.brand)
                                .font(.system(size: 12))
                                .foregroundStyle(HomeTheme.muted)
                                .lineLimit(1)
                            Text(item.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(HomeTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
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
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(store.petInventory(for: item.id).formatted())\(item.unit)")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(HomeTheme.ink)
                        if let rating = store.petProductRating(productID: item.id) {
                            Label(rating.overall.formatted(.number.precision(.fractionLength(1))), systemImage: "star.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(HomeTheme.orange)
                        } else {
                            Text("暂无评价").font(.system(size: 12)).foregroundStyle(HomeTheme.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

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
            NavigationLink { PetItemEditorView() } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(HomeTheme.muted)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(HomePressButtonStyle())
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

struct PetRatingsListView: View {
    @EnvironmentObject private var store: HomeStore
    @State private var primaryID = "pet-root-food"
    @State private var secondaryID = "all"
    @State private var sheet: PetRatingsSheet?

    private var primaryCategories: [ManagedCategory] { store.categories(for: .pet) }
    private var selectedPrimary: ManagedCategory? { primaryCategories.first { $0.id == primaryID } ?? primaryCategories.first }
    private var secondaryCategories: [ManagedCategory] {
        selectedPrimary.map { store.categories(for: .pet, parentID: $0.id) } ?? []
    }
    private var items: [PetItem] {
        store.activePetItems.filter { item in
            guard let selectedPrimary, store.petProductRating(productID: item.id) != nil else { return false }
            let secondaryName = secondaryCategories.first { $0.id == secondaryID }?.name
            return item.resolvedPrimaryCategory == selectedPrimary.name
                && (secondaryName == nil || item.resolvedSecondaryCategory == secondaryName)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HomeSectionHeader(title: "物品评价", actionTitle: "添加评价") { sheet = .productPicker }
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
        }
        .sheet(item: $sheet) { _ in PetRatingProductPickerSheet() }
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
                    PageTitle(title: item.displayTitle, subtitle: "\(item.resolvedPrimaryCategory) · \(item.resolvedSecondaryCategory)")
                    basicCard(item)
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
        .background(HomeTheme.background).navigationBarTitleDisplayMode(.inline)
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
            case .productReview: PetProductReviewEditorView(productID: itemID)
            case .palatability: PetPalatabilityEditorView(productID: itemID)
            }
        }
        .alert("停用这个宠物物品？", isPresented: $showArchive) {
            Button("取消", role: .cancel) {}
            Button("停用", role: .destructive) { store.deletePetItem(id: itemID); dismiss() }
        } message: { Text("产品会从日常列表隐藏，但库存、价格和评价历史会保留。") }
    }

    private func basicCard(_ item: PetItem) -> some View {
        HomeCard {
            VStack(spacing: 10) {
                if let image = item.image, !image.isEmpty {
                    PetStoredImage(reference: image).frame(height: 210).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                detailRow("品牌", item.brand); detailRow("口味/型号", item.variant ?? item.model)
                detailRow("规格", item.spec); detailRow("库存单位", item.unit)
                if let notes = item.notes { detailRow("备注", notes) }
            }
        }
    }

    private func inventoryCard(_ item: PetItem) -> some View {
        HomeCard {
            VStack(alignment: .leading, spacing: 12) {
                HomeSectionHeader(title: "当前库存")
                Text("\(store.petInventory(for: item.id).formatted()) \(item.unit)").font(HomeTypography.metric).foregroundStyle(HomeTheme.blue)
                HStack(spacing: 8) {
                    Button("入库") { sheet = .inbound }.buttonStyle(HomePrimaryButtonStyle())
                    Button("出库") { sheet = .outbound }.buttonStyle(HomeSecondaryButtonStyle())
                    Button("修正") { sheet = .adjustment }.buttonStyle(HomeSecondaryButtonStyle())
                }
            }
        }
    }

    private func transactionCard(_ item: PetItem) -> some View {
        let records = Array(store.petTransactions(for: item.id).prefix(5))
        return HomeCard {
            VStack(alignment: .leading, spacing: 9) {
                HomeSectionHeader(title: "进出库记录", actionTitle: store.petTransactions(for: item.id).count > 5 ? "最近 5 条" : nil)
                if records.isEmpty { Text("暂无库存流水").font(HomeTypography.body).foregroundStyle(HomeTheme.muted) }
                ForEach(records) { record in
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.reason).font(HomeTypography.body.weight(.medium))
                            Text("\(record.occurrenceDate) · \(sourceText(record.source))").font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
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
        return HomeCard {
            VStack(alignment: .leading, spacing: 9) {
                HomeSectionHeader(title: "价格历史")
                detailRow("最近单位价格", records.first?.unitPrice.map { "\(currency2($0))/\(item.unit)" } ?? "暂无")
                detailRow("历史最低", records.compactMap(\.unitPrice).min().map { "\(currency2($0))/\(item.unit)" } ?? "暂无")
                ForEach(records.prefix(3)) { record in
                    Text("\(record.occurrenceDate) · 总价 \(currency2(record.totalPrice ?? 0)) · 单价 \(currency2(record.unitPrice ?? 0))/\(record.unit)")
                        .font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                }
            }
        }
    }

    private var productReviewCard: some View {
        let records = store.data.petProductReviews.filter { $0.productID == itemID }.sorted { $0.reviewDate > $1.reviewDate }
        return HomeCard {
            VStack(alignment: .leading, spacing: 9) {
                HomeSectionHeader(title: "物品评价", actionTitle: "添加评价") { sheet = .productReview }
                if let item, let summary = store.petProductRating(productID: itemID) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(summary.overall.formatted(.number.precision(.fractionLength(1))))
                            .font(HomeTypography.metric)
                            .foregroundStyle(HomeTheme.blue)
                        Label("\(summary.count)次评价", systemImage: "star.fill")
                            .font(HomeTypography.supporting)
                            .foregroundStyle(HomeTheme.orange)
                    }
                    let dimensions = petRatingDimensions(item)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                        ForEach(dimensions, id: \.self) { name in
                            HStack {
                                Text(name).font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                                Spacer()
                                Text(summary.dimensionAverages[name]?.formatted(.number.precision(.fractionLength(1))) ?? "--")
                                    .font(HomeTypography.body.weight(.medium))
                            }
                        }
                    }
                } else {
                    Text("暂无物品评价").font(HomeTypography.body).foregroundStyle(HomeTheme.muted)
                }
                ForEach(records.prefix(5)) { review in
                    Divider()
                    HStack {
                        Text(review.reviewDate).font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                        Spacer()
                        Text("本次 \(review.overallScore.formatted(.number.precision(.fractionLength(1))))")
                            .font(HomeTypography.cardTitle).foregroundStyle(HomeTheme.blue)
                    }
                    if !review.reviewText.isEmpty { Text(review.reviewText).font(HomeTypography.body) }
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
                    Text(review.reviewDate).font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                }
            }
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) { Text(title).font(HomeTypography.body).foregroundStyle(HomeTheme.muted); Spacer(); Text(value.isEmpty ? "未记录" : value).font(HomeTypography.body.weight(.medium)).multilineTextAlignment(.trailing) }
    }

    private func isPetFood(_ item: PetItem) -> Bool {
        item.resolvedPrimaryCategory == store.petRootCategory(capabilityKey: "petFood")?.name
    }
}

private enum PetItemDetailSheet: String, Identifiable { case inbound, outbound, adjustment, productReview, palatability; var id: String { rawValue } }
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
