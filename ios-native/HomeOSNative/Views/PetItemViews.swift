import SwiftUI
import PhotosUI

extension PetItem {
    var resolvedPrimaryCategory: String { primaryCategory ?? (type.contains("食品") ? "宠物食品" : "宠物用品") }
    var resolvedSecondaryCategory: String { secondaryCategory ?? type }
}

struct PetItemsListView: View {
    @EnvironmentObject private var store: HomeStore
    @State private var primaryID = "pet-root-food"
    @State private var secondaryID = "all"
    @State private var expandedItemID: String?
    @State private var quickMode: PetInventoryTransactionType = .outbound
    @State private var quickQuantity = 1.0

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
                NavigationLink { PetItemDetailView(itemID: item.id) } label: { productImage(item) }
                    .buttonStyle(HomePressButtonStyle())
                    .accessibilityLabel("查看\(item.name)详情")

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        expandedItemID = expandedItemID == item.id ? nil : item.id
                        quickMode = .outbound
                        quickQuantity = quickStep(for: item)
                    }
                    NativeHaptics.selection()
                } label: {
                    HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                            Text(item.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(HomeTheme.ink).lineLimit(1)
                            Text(item.resolvedSecondaryCategory).font(.system(size: 13)).foregroundStyle(HomeTheme.muted)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(store.petInventory(for: item.id).formatted())\(item.unit)")
                                .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(isLowStock(item) ? HomeTheme.orange : HomeTheme.ink)
                            if isLowStock(item) { Text("库存偏低").font(.system(size: 12)).foregroundStyle(HomeTheme.orange) }
                    }
                        Image(systemName: expandedItemID == item.id ? "chevron.up" : "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(HomeTheme.muted)
                            .frame(width: 22)
                    }
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
        HStack(spacing: 6) {
            Picker("操作", selection: $quickMode) {
                Text("出库").tag(PetInventoryTransactionType.outbound)
                Text("入库").tag(PetInventoryTransactionType.inbound)
            }
            .pickerStyle(.segmented)
            .frame(width: 104)

            HStack(spacing: 0) {
                compactStepButton("minus") { quickQuantity = max(quickStep(for: item), quickQuantity - quickStep(for: item)) }
                Text(quickQuantity.formatted(.number.precision(.fractionLength(0...2))))
                    .font(.system(size: 14, weight: .medium))
                    .frame(minWidth: 28)
                compactStepButton("plus") { quickQuantity += quickStep(for: item) }
            }
            .frame(height: 36)
            .background(HomeTheme.card, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(HomeTheme.line, lineWidth: 0.8) }

            Text(item.unit).font(.system(size: 13)).foregroundStyle(HomeTheme.muted)
            Spacer(minLength: 0)
            Button("确认") { confirmQuickAction(item) }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(HomeTheme.blue, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .buttonStyle(HomePressButtonStyle())
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
                .frame(width: 28, height: 36)
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
            reason: quickMode == .inbound ? "快捷入库" : "快捷出库"
        )
        if success {
            withAnimation(.easeInOut(duration: 0.18)) { expandedItemID = nil }
        }
    }

    private func quickStep(for item: PetItem) -> Double {
        ["kg", "公斤", "千克", "l", "L", "升"].contains(item.unit) ? 0.1 : 1
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

    private func isLowStock(_ item: PetItem) -> Bool {
        item.lowStockThreshold.map { store.petInventory(for: item.id) <= $0 } ?? false
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
                    PageTitle(title: item.name, subtitle: "\(item.resolvedPrimaryCategory) · \(item.resolvedSecondaryCategory)")
                    basicCard(item)
                    inventoryCard(item)
                    transactionCard(item)
                    priceCard(item)
                    productReviewCard
                    if isPetFood(item) { palatabilityCard }
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
                detailRow("最近单位价格", records.first?.unitPrice.map { "¥\($0.formatted())/\(item.unit)" } ?? "暂无")
                detailRow("历史最低", records.compactMap(\.unitPrice).min().map { "¥\($0.formatted())/\(item.unit)" } ?? "暂无")
                ForEach(records.prefix(3)) { record in
                    Text("\(record.occurrenceDate) · \(record.quantityChange.formatted())\(record.unit) · ¥\((record.totalPrice ?? 0).formatted())")
                        .font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                }
            }
        }
    }

    private var productReviewCard: some View {
        let records = store.data.petProductReviews.filter { $0.productID == itemID }.sorted { $0.reviewDate > $1.reviewDate }
        return HomeCard {
            VStack(alignment: .leading, spacing: 9) {
                HomeSectionHeader(title: "我的产品评价", actionTitle: "添加") { sheet = .productReview }
                if records.isEmpty { Text("暂无回购评价").font(HomeTypography.body).foregroundStyle(HomeTheme.muted) }
                ForEach(records.prefix(5)) { review in
                    Divider(); Text(repurchaseText(review.repurchaseLevel)).font(HomeTypography.cardTitle).foregroundStyle(HomeTheme.blue)
                    if !review.reviewText.isEmpty { Text(review.reviewText).font(HomeTypography.body) }
                    Text(review.reviewDate).font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
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
func repurchaseText(_ level: Int) -> String {
    switch level { case 1: "不会回购"; case 2: "回购意愿较低"; case 3: "一般"; case 4: "回购意愿较高"; default: "一定会回购" }
}
func preferenceColor(_ value: String) -> Color { value == "喜欢" ? HomeTheme.success : value == "不喜欢" ? HomeTheme.danger : HomeTheme.muted }
func sourceText(_ value: PetInventorySource) -> String {
    switch value { case .manual: "手动"; case .migration: "旧数据迁移"; case .litterRefill: "猫砂补砂"; case .litterReplace: "猫砂换砂" }
}
