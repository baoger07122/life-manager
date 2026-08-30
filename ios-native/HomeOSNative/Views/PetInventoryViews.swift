import SwiftUI
import PhotosUI
import UIKit

struct PetItemEditorView: View {
    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    let itemID: String?
    @State private var primaryID = "pet-root-food"
    @State private var secondaryID = "pet-food-0"
    @State private var name = ""
    @State private var brand = ""
    @State private var variant = ""
    @State private var spec = ""
    @State private var packageType = ""
    @State private var unit = "件"
    @State private var initialStock = 0.0
    @State private var purchaseTotalText = ""
    @State private var notes = ""
    @State private var litterKind = ""
    @State private var conversion = 0.0
    @State private var imageReference: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var loaded = false
    @State private var sheet: PetItemEditorSheet?
    @State private var showDuplicateAlert = false

    init(itemID: String? = nil) { self.itemID = itemID }
    private var primaryCategories: [ManagedCategory] { store.categories(for: .pet) }
    private var selectedPrimary: ManagedCategory? { primaryCategories.first { $0.id == primaryID } ?? primaryCategories.first }
    private var secondaryCategories: [ManagedCategory] { selectedPrimary.map { store.categories(for: .pet, parentID: $0.id) } ?? [] }
    private var selectedSecondary: ManagedCategory? { secondaryCategories.first { $0.id == secondaryID } ?? secondaryCategories.first }
    private var purchaseTotal: Double? {
        let normalized = purchaseTotalText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }
    private var calculatedUnitPrice: Double? {
        guard let purchaseTotal, initialStock > 0 else { return nil }
        return purchaseTotal / initialStock
    }

    var body: some View {
        ScrollView {
            VStack(spacing: HomeMetrics.sectionSpacing) {
                imageCard

                Button { sheet = .category; NativeHaptics.selection() } label: {
                    HomeCard(padding: 0) {
                        HStack(spacing: 10) {
                            Text("分类").font(HomeTypography.cardTitle)
                            Spacer()
                            Text(categorySummary).font(HomeTypography.body).foregroundStyle(HomeTheme.muted).lineLimit(1)
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, HomeMetrics.cardPadding)
                        .frame(minHeight: 56)
                    }
                }
                .buttonStyle(.plain)

                HomeCard {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("基本信息").font(HomeTypography.sectionTitle).padding(.bottom, 8)
                        editorButtonRow(title: "品牌", value: brand.isEmpty ? "无品牌" : brand) { sheet = .brand }
                        divider
                        editorTextRow(title: "名称", placeholder: "请输入名称", text: $name)
                        divider
                        editorTextRow(title: selectedPrimary?.capabilityKey == "petFood" ? "口味" : "型号 / 款式", placeholder: "选填", text: $variant)
                        divider
                        packageTypeRow
                        divider
                        editorTextRow(title: "单件规格", placeholder: "例如5.4kg、185g", text: $spec)
                        divider
                        if packageType.isEmpty {
                            editorTextRow(title: "库存单位", placeholder: "例如kg、件", text: $unit)
                        } else {
                            HStack {
                                Text("库存单位").font(HomeTypography.body)
                                Spacer()
                                Text(packageType).font(HomeTypography.body).foregroundStyle(HomeTheme.muted)
                            }
                            .frame(minHeight: HomeMetrics.controlHeight)
                        }
                    }
                }

                HomeCard {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("库存设置").font(HomeTypography.sectionTitle).padding(.bottom, 8)
                        if itemID == nil {
                            editorNumberRow(title: "初始库存", value: $initialStock)
                            divider
                            editorTextRow(title: "本次购入总额（选填）", placeholder: "¥0", text: $purchaseTotalText, keyboard: .decimalPad)
                            divider
                            HStack {
                                Text("折算单价").font(HomeTypography.body)
                                Spacer()
                                Text(calculatedUnitPrice.map { "¥\($0.formatted(.number.precision(.fractionLength(2))))/\(unit.isEmpty ? "单位" : unit)" } ?? "自动计算")
                                    .font(HomeTypography.body)
                                    .foregroundStyle(HomeTheme.muted)
                            }
                            .frame(minHeight: HomeMetrics.controlHeight)
                        } else {
                            Text("库存数量请通过入库、出库或修正库存进行调整。")
                                .font(HomeTypography.supporting)
                                .foregroundStyle(HomeTheme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                if selectedSecondary?.name == "猫砂" {
                    HomeCard {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("猫砂信息").font(HomeTypography.sectionTitle).padding(.bottom, 8)
                            editorTextRow(title: "猫砂种类", placeholder: "例如矿砂", text: $litterKind)
                            divider
                            editorNumberRow(title: "每个库存单位折合 kg", value: $conversion)
                        }
                    }
                }

                HomeCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("备注").font(HomeTypography.sectionTitle)
                        TextField("选填", text: $notes, axis: .vertical)
                            .font(HomeTypography.body)
                            .multilineTextAlignment(.leading)
                            .lineLimit(1...4)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .frame(minHeight: 52, alignment: .leading)
                            .background(HomeTheme.background, in: RoundedRectangle(cornerRadius: HomeMetrics.controlRadius, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: HomeMetrics.controlRadius, style: .continuous)
                                    .stroke(HomeTheme.line, lineWidth: 0.6)
                            }
                    }
                }

                Button("保存", action: save)
                    .buttonStyle(HomePrimaryButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.horizontal, 42)
            }
            .padding(.horizontal, HomeMetrics.pageInset)
            .padding(.vertical, 16)
        }
        .background(HomeTheme.background)
        .navigationTitle(itemID == nil ? "新增宠物物品" : "编辑宠物物品")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadExisting() }
        .onChange(of: selectedPhoto) { _, photo in Task { if let data = try? await photo?.loadTransferable(type: Data.self) { imageReference = "data:image/jpeg;base64," + data.base64EncodedString() } } }
        .onChange(of: packageType) { _, value in
            if !value.isEmpty { unit = value }
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .category:
                PetCategorySelectionSheet(primaryID: $primaryID, secondaryID: $secondaryID)
            case .brand:
                PetBrandSelectionSheet(brand: $brand)
            }
        }
        .alert("可能是重复物品", isPresented: $showDuplicateAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("已存在品牌、名称、口味、包装形式和规格完全相同的物品。不同口味请分别建立产品。")
        }
    }

    private var categorySummary: String {
        [selectedPrimary?.name, selectedSecondary?.name].compactMap { $0 }.joined(separator: " · ")
    }

    private var imageCard: some View {
        HomeCard {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Group {
                    if let imageReference {
                        PetStoredImage(reference: imageReference)
                            .frame(maxWidth: .infinity)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "pawprint.fill").font(.system(size: 34)).foregroundStyle(HomeTheme.muted)
                            Label("添加物品图片", systemImage: "photo").font(HomeTypography.body).foregroundStyle(HomeTheme.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var divider: some View { Divider().overlay(HomeTheme.line) }

    private var packageTypeRow: some View {
        HStack {
            Text("包装形式").font(HomeTypography.body)
            Spacer()
            Picker("包装形式", selection: $packageType) {
                Text("未设置").tag("")
                Text("袋").tag("袋")
                Text("罐").tag("罐")
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .frame(minHeight: HomeMetrics.controlHeight)
    }

    private func editorButtonRow(title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(HomeTypography.body).foregroundStyle(HomeTheme.ink)
                Spacer()
                Text(value).font(HomeTypography.body).foregroundStyle(HomeTheme.muted)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .frame(minHeight: HomeMetrics.controlHeight)
        }
        .buttonStyle(.plain)
    }

    private func editorTextRow(title: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 12) {
            Text(title).font(HomeTypography.body)
            Spacer()
            TextField(placeholder, text: text)
                .font(HomeTypography.body)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: HomeMetrics.controlHeight)
    }

    private func editorNumberRow(title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 12) {
            Text(title).font(HomeTypography.body)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...4)))
                .font(HomeTypography.body)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: HomeMetrics.controlHeight)
    }

    private func loadExisting() {
        guard !loaded else { return }; defer { loaded = true }
        guard let itemID, let item = store.data.petItems.first(where: { $0.id == itemID }) else {
            primaryID = primaryCategories.first?.id ?? ""
            secondaryID = secondaryCategories.first?.id ?? ""
            return
        }
        primaryID = primaryCategories.first(where: { $0.name == item.resolvedPrimaryCategory })?.id
            ?? (item.resolvedPrimaryCategory.contains("食品") ? store.petRootCategory(capabilityKey: "petFood")?.id : store.petRootCategory(capabilityKey: "petSupply")?.id)
            ?? primaryCategories.first?.id ?? ""
        secondaryID = store.categories(for: .pet, parentID: primaryID).first(where: { $0.name == item.resolvedSecondaryCategory })?.id
            ?? store.categories(for: .pet, parentID: primaryID).first?.id ?? ""
        name = item.name; brand = item.brand
        let storedVariant = item.variant ?? item.model
        variant = storedVariant.caseInsensitiveCompare(item.spec) == .orderedSame ? "" : storedVariant
        spec = item.spec; unit = item.unit
        packageType = item.packageType ?? ""
        notes = item.notes ?? ""; litterKind = item.litterKind ?? ""
        conversion = item.unitConversionToBase ?? 0; imageReference = item.image
    }

    private func save() {
        let existing = itemID.flatMap { id in store.data.petItems.first { $0.id == id } }
        let now = Date().timeIntervalSince1970
        guard let selectedPrimary, let selectedSecondary else { return }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanVariant = variant.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSpec = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPackageType = packageType.trimmingCharacters(in: .whitespacesAndNewlines)
        let duplicate = store.activePetItems.contains { candidate in
            candidate.id != (itemID ?? "")
                && candidate.brand.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(cleanBrand) == .orderedSame
                && candidate.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(cleanName) == .orderedSame
                && (candidate.variant ?? "").trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(cleanVariant) == .orderedSame
                && candidate.spec.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(cleanSpec) == .orderedSame
                && (candidate.packageType ?? "") == cleanPackageType
        }
        guard !duplicate else { showDuplicateAlert = true; NativeHaptics.warning(); return }
        var item = existing ?? PetItem(id: UUID().uuidString, type: selectedSecondary.name, name: name, brand: brand, model: variant, spec: spec, quantity: max(initialStock, 0), unit: unit, days: 0, weeklyUsage: nil, lastReplenishedAt: nil, purchaseHistory: nil, replenishmentHistory: nil, feedback: nil, price: nil, cat: "", preference: "", image: imageReference, unitConversionToBase: nil)
        let savedSecondary = selectedSecondary.name
        item.type = savedSecondary; item.name = cleanName; item.brand = cleanBrand; item.model = cleanVariant; item.spec = cleanSpec
        item.unit = cleanPackageType.isEmpty ? unit.trimmingCharacters(in: .whitespacesAndNewlines) : cleanPackageType
        item.primaryCategory = selectedPrimary.name; item.secondaryCategory = savedSecondary
        item.variant = cleanVariant.isEmpty ? nil : cleanVariant; item.lowStockThreshold = nil; item.notes = notes.isEmpty ? nil : notes
        item.packageType = cleanPackageType.isEmpty ? nil : cleanPackageType
        item.foodRole = nil; item.litterKind = savedSecondary == "猫砂" ? (litterKind.isEmpty ? nil : litterKind) : nil
        item.unitConversionToBase = conversion > 0 ? conversion : nil; item.image = imageReference; item.isArchived = false
        if itemID == nil, let calculatedUnitPrice { item.price = calculatedUnitPrice }
        item.createdAt = item.createdAt ?? now; item.updatedAt = now
        store.upsertPetItem(item, openingTotalPrice: itemID == nil ? purchaseTotal : nil); NativeHaptics.success(); dismiss()
    }
}

private enum PetItemEditorSheet: String, Identifiable {
    case category, brand
    var id: String { rawValue }
}

private struct PetCategorySelectionSheet: View {
    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    @Binding private var primaryID: String
    @Binding private var secondaryID: String
    @State private var draftPrimaryID: String
    @State private var draftSecondaryID: String

    init(primaryID: Binding<String>, secondaryID: Binding<String>) {
        _primaryID = primaryID
        _secondaryID = secondaryID
        _draftPrimaryID = State(initialValue: primaryID.wrappedValue)
        _draftSecondaryID = State(initialValue: secondaryID.wrappedValue)
    }

    private var primaryCategories: [ManagedCategory] { store.categories(for: .pet) }
    private var secondaryCategories: [ManagedCategory] { store.categories(for: .pet, parentID: draftPrimaryID) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 0) {
                    ForEach(primaryCategories) { category in
                        Button {
                            draftPrimaryID = category.id
                            draftSecondaryID = store.categories(for: .pet, parentID: category.id).first?.id ?? ""
                            NativeHaptics.selection()
                        } label: {
                            HomeUnderlineTab(title: category.name, selected: draftPrimaryID == category.id, prominent: true)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Divider()
                Text("具体分类").font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
                HomeTagFlowLayout(spacing: 8) {
                    ForEach(secondaryCategories) { category in
                        Button {
                            draftSecondaryID = category.id
                            NativeHaptics.selection()
                        } label: {
                            Text(category.name)
                                .font(HomeTypography.body)
                                .foregroundStyle(draftSecondaryID == category.id ? HomeTheme.blue : HomeTheme.ink)
                                .padding(.horizontal, 18)
                                .frame(height: 40)
                                .background(draftSecondaryID == category.id ? HomeTheme.blue.opacity(0.10) : HomeTheme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
                Button("完成") {
                    primaryID = draftPrimaryID
                    secondaryID = draftSecondaryID
                    NativeHaptics.success()
                    dismiss()
                }
                .buttonStyle(HomePrimaryButtonStyle())
            }
            .padding(.horizontal, HomeMetrics.pageInset)
            .padding(.bottom, 16)
            .navigationTitle("选择分类")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(390)])
        .presentationDragIndicator(.visible)
    }
}

private struct PetBrandSelectionSheet: View {
    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    @Binding private var brand: String
    @State private var query = ""
    @State private var draftBrand: String

    init(brand: Binding<String>) {
        _brand = brand
        _draftBrand = State(initialValue: brand.wrappedValue)
    }

    private var allBrands: [ManagedBrand] { store.brands(for: .pet) }
    private var filteredBrands: [ManagedBrand] {
        query.isEmpty ? allBrands : allBrands.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
    private var recentBrands: [ManagedBrand] { Array(allBrands.prefix(3)) }
    private var cleanQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canAddQuery: Bool {
        !cleanQuery.isEmpty && !allBrands.contains { $0.name.caseInsensitiveCompare(cleanQuery) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(HomeTheme.muted)
                    TextField("搜索品牌", text: $query).font(HomeTypography.body)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: HomeMetrics.controlHeight)
                .background(HomeTheme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                if query.isEmpty, !recentBrands.isEmpty {
                    brandSection(title: "最近使用", values: recentBrands)
                }
                brandSection(title: query.isEmpty ? "全部品牌" : "搜索结果", values: filteredBrands)

                if canAddQuery {
                    Button {
                        if store.addManagedBrand(name: cleanQuery, modules: [.pet]) {
                            draftBrand = cleanQuery
                            query = ""
                        }
                    } label: {
                        Label("新增品牌“\(cleanQuery)”", systemImage: "plus.circle.fill")
                            .font(HomeTypography.body)
                    }
                }
                Spacer(minLength: 0)
                Button("完成") {
                    brand = draftBrand
                    NativeHaptics.success()
                    dismiss()
                }
                .buttonStyle(HomePrimaryButtonStyle())
            }
            .padding(.horizontal, HomeMetrics.pageInset)
            .padding(.bottom, 16)
            .navigationTitle("选择品牌")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink("管理") { BrandManagementView() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func brandSection(title: String, values: [ManagedBrand]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(HomeTypography.supporting).foregroundStyle(HomeTheme.muted)
            HomeTagFlowLayout(spacing: 8) {
                ForEach(values) { value in brandChip(value.name) }
                if title == "全部品牌" { brandChip("无品牌") }
            }
        }
    }

    private func brandChip(_ value: String) -> some View {
        let storedValue = value == "无品牌" ? "" : value
        let selected = draftBrand.caseInsensitiveCompare(storedValue) == .orderedSame
        return Button {
            draftBrand = storedValue
            NativeHaptics.selection()
        } label: {
            Text(value)
                .font(HomeTypography.supporting.weight(.medium))
                .foregroundStyle(selected ? HomeTheme.blue : HomeTheme.ink)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(selected ? HomeTheme.blue.opacity(0.10) : HomeTheme.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct PetInventoryEditorView: View {
    enum Mode { case inbound, outbound, adjustment }
    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    let productID: String
    let mode: Mode
    var quick = false
    @State private var quantity = 0.0
    @State private var targetText = ""
    @State private var date = Date()
    @State private var reason = ""
    @State private var totalPriceText = ""
    @State private var channel = ""
    @State private var note = ""
    @State private var hasExpiration = false
    @State private var expirationDate = Date()
    @State private var localError: String?

    private var item: PetItem? { store.data.petItems.first { $0.id == productID } }
    private var title: String { mode == .inbound ? "入库" : mode == .outbound ? (quick ? "快速出库" : "出库") : "修正库存" }
    private var calculatedUnitPrice: Double? {
        guard mode == .inbound, quantity > 0, let totalPrice, totalPrice > 0 else { return nil }
        return totalPrice / quantity
    }
    private var totalPrice: Double? {
        let normalized = totalPriceText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }
    private var currentInventory: Double { store.petInventory(for: productID) }
    private var targetValue: Double? {
        let normalized = targetText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value >= 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                if let item { Section { LabeledContent("产品", value: item.name); LabeledContent("当前库存", value: "\(store.petInventory(for: productID).formatted())\(item.unit)") } }
                Section(title) {
                    if mode == .adjustment {
                        TextField("调整后数量", text: $targetText).keyboardType(.decimalPad)
                        if let targetValue, let item {
                            let change = targetValue - currentInventory
                            LabeledContent("库存变化", value: "\(change > 0 ? "+" : "")\(change.formatted(.number.precision(.fractionLength(0...4))))\(item.unit)")
                                .foregroundStyle(change == 0 ? HomeTheme.muted : change > 0 ? HomeTheme.success : HomeTheme.orange)
                        } else {
                            Text("请输入大于或等于 0 的有效数字")
                                .font(HomeTypography.supporting)
                                .foregroundStyle(HomeTheme.danger)
                        }
                    }
                    else { TextField("数量", value: $quantity, format: .number).keyboardType(.decimalPad) }
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    TextField(mode == .outbound ? "出库原因" : "原因（可选）", text: $reason).font(HomeTypography.body)
                }
                if mode == .inbound {
                    Section("购买信息") {
                        TextField("¥0.00（选填）", text: $totalPriceText)
                            .keyboardType(.decimalPad)
                        LabeledContent("折算单价", value: calculatedUnitPrice.map { "¥\($0.formatted(.number.precision(.fractionLength(2))))/\(item?.unit ?? "单位")" } ?? "自动计算")
                            .foregroundStyle(HomeTheme.muted)
                        TextField("购买渠道（可选）", text: $channel).font(HomeTypography.body)
                        Toggle("记录到期日期", isOn: $hasExpiration)
                        if hasExpiration { DatePicker("到期日期", selection: $expirationDate, displayedComponents: .date) }
                    }
                }
                Section("备注") { TextField("可选", text: $note, axis: .vertical).font(HomeTypography.body) }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: save)
                        .disabled(mode == .adjustment ? (targetValue == nil || targetValue == currentInventory) : quantity <= 0)
                }
            }
        }
        .presentationDetents(quick ? [.medium] : [.medium, .large])
        .task {
            if mode == .adjustment {
                targetText = currentInventory.formatted(.number.precision(.fractionLength(0...4)))
            }
        }
        .alert("库存操作失败", isPresented: Binding(
            get: { localError != nil },
            set: { if !$0 { localError = nil } }
        )) {
            Button("知道了") { localError = nil }
        } message: {
            Text(localError ?? "请检查输入后重试。")
        }
    }

    private func save() {
        let dateString = LitterPredictionService.format(date)
        let success: Bool
        if mode == .adjustment {
            guard let targetValue else { localError = "请输入有效的修正后库存"; NativeHaptics.error(); return }
            success = store.adjustPetInventory(productID: productID, target: targetValue, occurrenceDate: dateString, reason: reason)
        } else {
            success = store.recordPetInventory(productID: productID, type: mode == .inbound ? .inbound : .outbound, quantity: quantity, occurrenceDate: dateString, reason: reason.isEmpty ? (mode == .inbound ? "购买入库" : "日常使用") : reason, totalPrice: totalPrice, purchaseChannel: channel, expirationDate: hasExpiration ? LitterPredictionService.format(expirationDate) : nil, note: note)
        }
        if success { dismiss() }
        else { localError = store.lastError ?? "库存修正没有保存，请重试。" }
    }
}

struct PetProductReviewEditorView: View {
    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    let productID: String
    let reviewID: String?
    @State private var scores: [String: Int] = [:]
    @State private var review = ""
    @State private var date = Date()
    @State private var loaded = false

    init(productID: String, reviewID: String? = nil) {
        self.productID = productID
        self.reviewID = reviewID
    }
    private var item: PetItem? { store.data.petItems.first { $0.id == productID } }
    private var dimensions: [String] { item.map(petRatingDimensions) ?? ["使用体验", "品质", "性价比", "回购意愿"] }
    private var overallScore: Double {
        let values = dimensions.map { scores[$0] ?? 3 }
        return Double(values.reduce(0, +)) / Double(max(values.count, 1))
    }
    var body: some View {
        NavigationStack {
            Form {
                if let item {
                    Section { LabeledContent("物品", value: item.displayTitle) }
                }
                Section("评分维度") {
                    ForEach(dimensions, id: \.self) { dimension in
                        HStack(spacing: 8) {
                            Text(dimension)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(HomeTheme.ink)
                                .frame(width: 62, alignment: .leading)
                            Picker(dimension, selection: scoreBinding(for: dimension)) {
                                ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(height: 34)
                        }
                        .frame(minHeight: 40)
                    }
                    LabeledContent("本次综合评分", value: overallScore.formatted(.number.precision(.fractionLength(1))))
                }
                DatePicker("评价日期", selection: $date, displayedComponents: .date)
                TextField("产品评价", text: $review, axis: .vertical).font(HomeTypography.body)
            }
            .navigationTitle(reviewID == nil ? "添加产品评价" : "编辑产品评价").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let values = Dictionary(uniqueKeysWithValues: dimensions.map { ($0, scores[$0] ?? 3) })
                        if store.savePetProductReview(id: reviewID, productID: productID, date: LitterPredictionService.format(date), scores: values, text: review) { dismiss() }
                    }
                }
            }
            .task { loadReview() }
        }.presentationDetents([.large])
    }

    private func loadReview() {
        guard !loaded else { return }
        defer { loaded = true }
        if let reviewID,
           let existing = store.data.petProductReviews.first(where: { $0.id == reviewID && $0.productID == productID }) {
            scores = existing.resolvedDimensionScores
            review = existing.reviewText
            date = LitterPredictionService.parse(existing.reviewDate) ?? Date()
        }
        dimensions.forEach { if scores[$0] == nil { scores[$0] = 3 } }
    }

    private func scoreBinding(for dimension: String) -> Binding<Int> {
        Binding(get: { scores[dimension] ?? 3 }, set: { scores[dimension] = $0; NativeHaptics.selection() })
    }
}

struct PetPalatabilityEditorView: View {
    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    let productID: String
    @State private var petID = ""
    @State private var preference = "喜欢"
    @State private var note = ""
    @State private var date = Date()
    var body: some View {
        NavigationStack {
            Form {
                Picker("宠物", selection: $petID) { ForEach(store.activePets) { Text($0.name).tag($0.id) } }
                Picker("评价", selection: $preference) { ForEach(["喜欢", "一般", "不喜欢"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
                DatePicker("评价日期", selection: $date, displayedComponents: .date)
                TextField("备注（可选）", text: $note, axis: .vertical).font(HomeTypography.body)
            }
            .navigationTitle("添加猫咪评价").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { if store.addPetPalatabilityReview(productID: productID, petID: petID, date: LitterPredictionService.format(date), preference: preference, note: note) { dismiss() } }.disabled(petID.isEmpty) }
            }
            .task { if petID.isEmpty { petID = store.activePets.first?.id ?? "" } }
        }.presentationDetents([.medium])
    }
}

struct PetPreferenceSummaryView: View {
    @EnvironmentObject private var store: HomeStore
    var body: some View {
        List {
            if store.data.petPalatabilityReviews.isEmpty {
                EmptyState(icon: "heart.fill", title: "还没有猫咪评价", message: "仅宠物食品可以分别记录每只猫的喜欢程度。")
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
            } else {
                ForEach(summaryPets, id: \.id) { pet in
                    Section(pet.name) {
                        ForEach(latestReviews(for: pet.id)) { review in
                            HStack {
                                Text(store.data.petItems.first { $0.id == review.productID }?.name ?? "已停用产品").font(HomeTypography.body)
                                Spacer(); Text(review.preference).font(HomeTypography.body).foregroundStyle(preferenceColor(review.preference))
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(HomeTheme.background)
        .navigationTitle("猫咪偏好").navigationBarTitleDisplayMode(.inline)
    }
    private var summaryPets: [(id: String, name: String)] {
        Dictionary(store.data.petPalatabilityReviews.map { ($0.petID, $0.petNameSnapshot) }, uniquingKeysWith: { first, _ in first })
            .map { (id: $0.key, name: $0.value) }.sorted { $0.name < $1.name }
    }
    private func latestReviews(for petID: String) -> [PetPalatabilityReview] {
        Dictionary(grouping: store.data.petPalatabilityReviews.filter { $0.petID == petID }, by: \.productID)
            .values.compactMap { $0.max { $0.reviewDate < $1.reviewDate } }.sorted { $0.reviewDate > $1.reviewDate }
    }
}
