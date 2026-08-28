import SwiftUI
import PhotosUI

let petFoodCategories = ["猫粮", "主食罐", "零食罐", "冻干", "汤罐", "其他食品"]
let petSupplyCategories = ["猫砂", "除臭用品", "清洁用品", "其他用品"]

extension PetItem {
    var resolvedPrimaryCategory: String { primaryCategory ?? (type.contains("食品") ? "宠物食品" : "宠物用品") }
    var resolvedSecondaryCategory: String { secondaryCategory ?? type }
}

struct PetItemsListView: View {
    @EnvironmentObject private var store: HomeStore
    @State private var primary = "全部"
    @State private var secondary = "全部"
    @State private var quickOutboundID: String?

    private var items: [PetItem] {
        store.activePetItems.filter {
            (primary == "全部" || $0.resolvedPrimaryCategory == primary)
                && (secondary == "全部" || $0.resolvedSecondaryCategory == secondary)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var secondaryOptions: [String] {
        let defaults = primary == "宠物食品" ? petFoodCategories : primary == "宠物用品" ? petSupplyCategories : petFoodCategories + petSupplyCategories
        return ["全部"] + Array(Set(defaults + store.activePetItems.map(\.resolvedSecondaryCategory))).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeSectionHeader(title: "宠物物品")
            filterRow(["全部", "宠物食品", "宠物用品"], selection: $primary)
            filterRow(secondaryOptions, selection: $secondary)
            HomeCard(padding: 12) {
                if items.isEmpty {
                    VStack(spacing: 12) {
                        EmptyState(icon: "shippingbox.fill", title: "暂无宠物物品", message: "按具体产品添加食品、猫砂或其他用品。")
                        NavigationLink("添加宠物物品") { PetItemEditorView() }.buttonStyle(HomeSecondaryButtonStyle())
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            itemRow(item)
                            if index < items.count - 1 { Divider() }
                        }
                        NavigationLink("新增宠物物品") { PetItemEditorView() }
                            .font(HomeTypography.body.weight(.semibold)).padding(.top, 12)
                    }
                }
            }
        }
        .sheet(item: Binding(get: { quickOutboundID.map { IdentifiedPetItem(id: $0) } }, set: { quickOutboundID = $0?.id })) { value in
            PetInventoryEditorView(productID: value.id, mode: .outbound, quick: true)
        }
        .onChange(of: primary) { _, _ in secondary = "全部" }
    }

    private func itemRow(_ item: PetItem) -> some View {
        HStack(spacing: 8) {
            NavigationLink {
                PetItemDetailView(itemID: item.id)
            } label: {
                HStack(spacing: 11) {
                    productImage(item)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name).font(HomeTypography.cardTitle).foregroundStyle(HomeTheme.ink).lineLimit(1)
                        Text(item.resolvedSecondaryCategory).font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                        if item.resolvedPrimaryCategory == "宠物食品" {
                            let reviews = store.latestPalatabilityReviews(for: item.id)
                            if !reviews.isEmpty {
                                Text(reviews.map { "\($0.petNameSnapshot)：\($0.preference)" }.joined(separator: " · "))
                                    .font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted).lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(store.petInventory(for: item.id).formatted())\(item.unit)")
                            .font(HomeTypography.body.weight(.semibold))
                            .foregroundStyle(isLowStock(item) ? HomeTheme.orange : HomeTheme.ink)
                        if let review = store.latestProductReview(for: item.id) {
                            Text(repurchaseText(review.repurchaseLevel)).font(HomeTypography.supporting).foregroundStyle(HomeTheme.blue)
                        }
                    }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)

            Button { quickOutboundID = item.id; NativeHaptics.tap() } label: {
                Image(systemName: "minus.circle.fill").font(.system(size: 24)).foregroundStyle(HomeTheme.blue).frame(width: 44, height: 44)
            }.buttonStyle(HomePressButtonStyle()).accessibilityLabel("快速出库")
        }.padding(.vertical, 8)
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

    private func filterRow(_ values: [String], selection: Binding<String>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    Button { selection.wrappedValue = value; NativeHaptics.selection() } label: {
                        HomeChip(title: value, selected: selection.wrappedValue == value)
                    }.buttonStyle(.plain)
                }
            }
        }
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
                    if item.resolvedPrimaryCategory == "宠物食品" { palatabilityCard }
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
}

private enum PetItemDetailSheet: String, Identifiable { case inbound, outbound, adjustment, productReview, palatability; var id: String { rawValue } }
private struct IdentifiedPetItem: Identifiable { let id: String }

func repurchaseText(_ level: Int) -> String {
    switch level { case 1: "不会回购"; case 2: "回购意愿较低"; case 3: "一般"; case 4: "回购意愿较高"; default: "一定会回购" }
}
func preferenceColor(_ value: String) -> Color { value == "喜欢" ? HomeTheme.success : value == "不喜欢" ? HomeTheme.danger : HomeTheme.muted }
func sourceText(_ value: PetInventorySource) -> String {
    switch value { case .manual: "手动"; case .migration: "旧数据迁移"; case .litterRefill: "猫砂补砂"; case .litterReplace: "猫砂换砂" }
}
