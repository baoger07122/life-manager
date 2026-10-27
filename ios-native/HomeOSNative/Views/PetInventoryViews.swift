import SwiftUI
import PhotosUI
import UIKit

struct PetItemEditorView: View {
    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    let itemID: String?
    let copySourceID: String?
    let initialPrimaryID: String?
    let initialSecondaryID: String?
    @State private var primaryID: String
    @State private var secondaryID: String
    @State private var name = ""
    @State private var brand = ""
    @State private var variant = ""
    @State private var specValueText = ""
    @State private var specUnit = "g"
    @State private var legacySpec = ""
    @State private var packageType = ""
    @State private var draftPackageType = ""
    @State private var showAddPackageType = false
    @State private var unit = "件"
    @State private var initialStockText = ""
    @State private var purchaseTotalText = ""
    @State private var initialHasExpiration = false
    @State private var initialExpirationDate = Date()
    @State private var notes = ""
    @State private var litterKind = ""
    @State private var conversion = 0.0
    @State private var imageReference: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var loaded = false
    @State private var sheet: PetItemEditorSheet?
    @State private var showDuplicateAlert = false
    @FocusState private var focusedField: PetItemEditorField?

    init(itemID: String? = nil, copyingItemID: String? = nil, initialPrimaryID: String? = nil, initialSecondaryID: String? = nil) {
        self.itemID = itemID
        self.copySourceID = copyingItemID
        self.initialPrimaryID = initialPrimaryID
        self.initialSecondaryID = initialSecondaryID
        _primaryID = State(initialValue: initialPrimaryID ?? "")
        _secondaryID = State(initialValue: initialSecondaryID ?? "")
    }
    private var primaryCategories: [ManagedCategory] { store.categories(for: .pet) }
    private var selectedPrimary: ManagedCategory? { primaryCategories.first { $0.id == primaryID } }
    private var secondaryCategories: [ManagedCategory] { selectedPrimary.map { store.categories(for: .pet, parentID: $0.id) } ?? [] }
    private var selectedSecondary: ManagedCategory? { secondaryCategories.first { $0.id == secondaryID } }
    private var purchaseTotal: Double? {
        let normalized = purchaseTotalText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }
    private var initialStock: Double {
        let normalized = initialStockText.replacingOccurrences(of: ",", with: ".")
        return max(Double(normalized) ?? 0, 0)
    }
    private var resolvedUnit: String {
        let packaged = packageType.trimmingCharacters(in: .whitespacesAndNewlines)
        if !packaged.isEmpty { return packaged }
        let stored = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        return stored.isEmpty ? "件" : stored
    }
    private var calculatedUnitPrice: Double? {
        guard let purchaseTotal, initialStock > 0 else { return nil }
        return purchaseTotal / initialStock
    }

    var body: some View {
        ScrollView {
            VStack(spacing: HomeMetrics.sectionSpacing) {
                imageCard

                Button { NativeHaptics.tap(); sheet = .category } label: {
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
                        editorButtonRow(title: "品牌", value: brand.isEmpty ? "无品牌" : brand) {
                            NativeHaptics.tap()
                            sheet = .brand
                        }
                        divider
                        editorTextRow(title: "名称", placeholder: "请输入名称", text: $name)
                        divider
                        editorTextRow(
                            title: selectedPrimary?.capabilityKey == "petFood" ? "口味" : "型号 / 款式",
                            placeholder: "选填",
                            text: $variant,
                            focusTarget: .variant
                        )
                        divider
                        packageTypeRow
                        divider
                        specificationRow
                        if itemID == nil {
                            divider
                            editorTextRow(title: "初始库存", placeholder: "0", text: $initialStockText, keyboard: .decimalPad)
                            divider
                            editorTextRow(title: "本次购入总额（选填）", placeholder: "¥0.00", text: $purchaseTotalText, keyboard: .decimalPad)
                            divider
                            HStack {
                                Text("折算单价").font(HomeTypography.body)
                                Spacer()
                                Text(calculatedUnitPrice.map { "¥\($0.formatted(.number.precision(.fractionLength(2))))/\(resolvedUnit)" } ?? "自动计算")
                                    .font(HomeTypography.body)
                                    .foregroundStyle(HomeTheme.muted)
                            }
                            .frame(minHeight: HomeMetrics.controlHeight)
                            Toggle("记录初始库存到期日期", isOn: $initialHasExpiration)
                                .disabled(initialStock <= 0)
                            if initialHasExpiration && initialStock > 0 {
                                DatePicker("到期日期", selection: $initialExpirationDate, displayedComponents: .date)
                            }
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
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedSecondary == nil)
                    .padding(.horizontal, 42)
            }
            .padding(.horizontal, HomeMetrics.pageInset)
            .padding(.vertical, 16)
        }
        .background(HomeTheme.background)
        .navigationTitle(editorTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadExisting()
            if copySourceID != nil {
                await Task.yield()
                focusedField = .variant
            }
        }
        .onChange(of: selectedPhoto) { _, photo in
            Task {
                if let data = try? await photo?.loadTransferable(type: Data.self) {
                    imageReference = "data:image/jpeg;base64," + data.base64EncodedString()
                    NativeHaptics.selection()
                }
            }
        }
        .onChange(of: primaryID) { _, _ in
            if specValueText.isEmpty && legacySpec.isEmpty {
                specUnit = selectedPrimary?.capabilityKey == "petSupply" ? "kg" : "g"
            }
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
        .alert("新增包装形式", isPresented: $showAddPackageType) {
            TextField("例如：盒", text: $draftPackageType)
            Button("取消", role: .cancel) { draftPackageType = "" }
            Button("添加") {
                let value = draftPackageType.trimmingCharacters(in: .whitespacesAndNewlines)
                if store.addPetPackageType(value) {
                    packageType = value
                    unit = value
                    draftPackageType = ""
                }
            }
            .disabled(draftPackageType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("添加后会保留在包装形式下拉菜单中。")
        }
    }

    private var categorySummary: String {
        [selectedPrimary?.name, selectedSecondary?.name].compactMap { $0 }.joined(separator: " · ")
    }

    private var editorTitle: String {
        if itemID != nil { return "编辑宠物物品" }
        if copySourceID != nil { return "复制宠物物品" }
        return "新增宠物物品"
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
            .simultaneousGesture(TapGesture().onEnded { NativeHaptics.tap() })
        }
    }

    private var divider: some View { Divider().overlay(HomeTheme.line) }

    private var packageTypeRow: some View {
        HStack {
            Text("包装形式").font(HomeTypography.body)
            Spacer()
            Menu {
                Button {
                    packageType = ""
                    NativeHaptics.selection()
                } label: {
                    if packageType.isEmpty { Label("未设置", systemImage: "checkmark") } else { Text("未设置") }
                }
                ForEach(store.petPackageTypes, id: \.self) { value in
                    Button {
                        packageType = value
                        unit = value
                        NativeHaptics.selection()
                    } label: {
                        if packageType == value { Label(value, systemImage: "checkmark") } else { Text(value) }
                    }
                }
                Divider()
                Button {
                    draftPackageType = ""
                    showAddPackageType = true
                    NativeHaptics.tap()
                } label: {
                    Label("新增包装形式", systemImage: "plus")
                }
            } label: {
                HStack(spacing: 5) {
                    Text(packageType.isEmpty ? "未设置" : packageType)
                        .font(HomeTypography.body)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(HomeTheme.blue)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
        }
        .frame(minHeight: HomeMetrics.controlHeight)
    }

    private var specificationRow: some View {
        HStack(spacing: 10) {
            Text("单件规格").font(HomeTypography.body)
            Spacer(minLength: 10)
            TextField(legacySpec.isEmpty ? "例如80" : legacySpec, text: $specValueText)
                .font(HomeTypography.body)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 96)
            Menu {
                ForEach(PetSpecificationResolver.selectableUnits, id: \.self) { value in
                    Button {
                        specUnit = value
                        NativeHaptics.selection()
                    } label: {
                        if specUnit == value { Label(value, systemImage: "checkmark") } else { Text(value) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(specUnit).font(HomeTypography.body)
                    Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                }
                .foregroundStyle(HomeTheme.blue)
                .frame(minWidth: 50, minHeight: 44)
                .contentShape(Rectangle())
            }
        }
        .frame(minHeight: HomeMetrics.controlHeight)
    }

    private var enteredSpecValue: Double? {
        let normalized = specValueText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }

    private var savedSpecText: String {
        if let enteredSpecValue {
            return PetSpecificationResolver.canonicalText(value: enteredSpecValue, unit: specUnit)
        }
        return legacySpec.trimmingCharacters(in: .whitespacesAndNewlines)
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func editorTextRow(
        title: String,
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default,
        focusTarget: PetItemEditorField? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Text(title).font(HomeTypography.body)
            Spacer()
            if let focusTarget {
                TextField(placeholder, text: text)
                    .font(HomeTypography.body)
                    .keyboardType(keyboard)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: focusTarget)
            } else {
                TextField(placeholder, text: text)
                    .font(HomeTypography.body)
                    .keyboardType(keyboard)
                    .multilineTextAlignment(.trailing)
            }
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
        guard let sourceID = itemID ?? copySourceID,
              let item = store.data.petItems.first(where: { $0.id == sourceID }) else {
            let rememberedPrimary = UserDefaults.standard.string(forKey: "HomeOS.lastPetPrimaryCategoryID")
            let preferredPrimary = initialPrimaryID ?? rememberedPrimary
            primaryID = primaryCategories.contains(where: { $0.id == preferredPrimary })
                ? (preferredPrimary ?? "")
                : (primaryCategories.first?.id ?? "")
            specUnit = selectedPrimary?.capabilityKey == "petSupply" ? "kg" : "g"

            let rememberedSecondary = UserDefaults.standard.string(forKey: "HomeOS.lastPetSecondaryCategoryID")
            let preferredSecondary = initialSecondaryID ?? rememberedSecondary
            let availableSecondary = store.categories(for: .pet, parentID: primaryID)
            secondaryID = availableSecondary.contains(where: { $0.id == preferredSecondary })
                ? (preferredSecondary ?? "")
                : ""
            return
        }
        primaryID = primaryCategories.first(where: { $0.name == item.resolvedPrimaryCategory })?.id
            ?? (item.resolvedPrimaryCategory.contains("食品") ? store.petRootCategory(capabilityKey: "petFood")?.id : store.petRootCategory(capabilityKey: "petSupply")?.id)
            ?? primaryCategories.first?.id ?? ""
        secondaryID = store.categories(for: .pet, parentID: primaryID).first(where: { $0.name == item.resolvedSecondaryCategory })?.id
            ?? store.categories(for: .pet, parentID: primaryID).first?.id ?? ""
        name = item.name; brand = item.brand
        let storedVariant = item.variant ?? item.model
        variant = copySourceID == nil && storedVariant.caseInsensitiveCompare(item.spec) != .orderedSame ? storedVariant : ""
        if let resolvedSpec = PetSpecificationResolver.resolve(item: item) {
            specValueText = PetSpecificationResolver.number(resolvedSpec.value)
            specUnit = resolvedSpec.unit
            legacySpec = ""
        } else {
            specValueText = ""
            legacySpec = item.spec
        }
        unit = item.unit
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
        let cleanSpec = savedSpecText
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
        var item = existing ?? PetItem(id: UUID().uuidString, type: selectedSecondary.name, name: name, brand: brand, model: variant, spec: cleanSpec, quantity: initialStock, unit: resolvedUnit, days: 0, weeklyUsage: nil, lastReplenishedAt: nil, purchaseHistory: nil, replenishmentHistory: nil, feedback: nil, price: nil, cat: "", preference: "", image: imageReference, unitConversionToBase: nil)
        let savedSecondary = selectedSecondary.name
        item.type = savedSecondary; item.name = cleanName; item.brand = cleanBrand; item.model = cleanVariant; item.spec = cleanSpec
        item.specValue = enteredSpecValue
        item.specUnit = enteredSpecValue == nil ? nil : specUnit
        item.unit = resolvedUnit
        item.primaryCategory = selectedPrimary.name; item.secondaryCategory = savedSecondary
        item.variant = cleanVariant.isEmpty ? nil : cleanVariant; item.lowStockThreshold = nil; item.notes = notes.isEmpty ? nil : notes
        item.packageType = cleanPackageType.isEmpty ? nil : cleanPackageType
        item.foodRole = nil; item.litterKind = savedSecondary == "猫砂" ? (litterKind.isEmpty ? nil : litterKind) : nil
        item.unitConversionToBase = conversion > 0 ? conversion : nil; item.image = imageReference; item.isArchived = false
        if itemID == nil {
            item.expirationDate = initialStock > 0 && initialHasExpiration
                ? LitterPredictionService.format(initialExpirationDate)
                : nil
        }
        if itemID == nil, let calculatedUnitPrice { item.price = calculatedUnitPrice }
        item.createdAt = item.createdAt ?? now; item.updatedAt = now
        UserDefaults.standard.set(primaryID, forKey: "HomeOS.lastPetPrimaryCategoryID")
        UserDefaults.standard.set(secondaryID, forKey: "HomeOS.lastPetSecondaryCategoryID")
        store.upsertPetItem(item, openingTotalPrice: itemID == nil ? purchaseTotal : nil)
        NativeHaptics.success()
        dismiss()
    }
}

private enum PetItemEditorField: Hashable {
    case variant
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
    @State private var selectedDetent: PresentationDetent = .medium
    @FocusState private var searchFocused: Bool

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
                    TextField("搜索品牌", text: $query)
                        .font(HomeTypography.body)
                        .focused($searchFocused)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: HomeMetrics.controlHeight)
                .background(HomeTheme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded {
                    selectedDetent = .large
                    searchFocused = true
                })

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if query.isEmpty, !recentBrands.isEmpty {
                            brandSection(title: "最近使用", values: recentBrands)
                        }
                        brandSection(title: query.isEmpty ? "全部品牌" : "搜索结果", values: filteredBrands)

                        if canAddQuery {
                            Button {
                                if store.addManagedBrand(name: cleanQuery, modules: [.pet]) {
                                    draftBrand = cleanQuery
                                    query = ""
                                    NativeHaptics.success()
                                }
                            } label: {
                                Label("新增品牌“\(cleanQuery)”", systemImage: "plus.circle.fill")
                                    .font(HomeTypography.body)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)

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
        .presentationDetents([.medium, .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .onChange(of: searchFocused) { _, focused in
            if focused { selectedDetent = .large }
        }
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
    @State private var batchAllocationRequest: PetInventoryBatchAllocationRequest?
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
        .sheet(item: $batchAllocationRequest) { request in
            PetInventoryBatchAllocationSheet(requests: [request]) { quantities in
                save(batchGroupQuantities: quantities[productID])
            }
        }
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
        if mode == .outbound {
            let groups = store.petInventoryBatchGroups(for: productID)
            if quantity <= currentInventory, groups.count > 1, let item {
                batchAllocationRequest = PetInventoryBatchAllocationRequest(
                    productID: productID,
                    productName: item.displayTitle,
                    quantity: quantity,
                    unit: item.unit,
                    groups: groups
                )
                return
            }
        } else if mode == .adjustment,
                  let targetValue, targetValue < currentInventory,
                  let item {
            let groups = store.petInventoryBatchGroups(for: productID)
            let reduction = currentInventory - targetValue
            if groups.count > 1 {
                batchAllocationRequest = PetInventoryBatchAllocationRequest(
                    productID: productID,
                    productName: item.displayTitle,
                    quantity: reduction,
                    unit: item.unit,
                    groups: groups
                )
                return
            }
        }
        save(batchGroupQuantities: nil)
    }

    private func save(batchGroupQuantities: [String: Double]?) {
        let dateString = LitterPredictionService.format(date)
        let success: Bool
        if mode == .adjustment {
            guard let targetValue else { localError = "请输入有效的修正后库存"; NativeHaptics.error(); return }
            success = store.adjustPetInventory(
                productID: productID,
                target: targetValue,
                occurrenceDate: dateString,
                reason: reason,
                batchGroupQuantities: batchGroupQuantities
            )
        } else {
            success = store.recordPetInventory(
                productID: productID,
                type: mode == .inbound ? .inbound : .outbound,
                quantity: quantity,
                occurrenceDate: dateString,
                reason: reason.isEmpty ? (mode == .inbound ? "购买入库" : "日常使用") : reason,
                totalPrice: totalPrice,
                purchaseChannel: channel,
                expirationDate: mode == .inbound && hasExpiration ? LitterPredictionService.format(expirationDate) : nil,
                note: note,
                batchGroupQuantities: batchGroupQuantities
            )
        }
        if success { dismiss() }
        else { localError = store.lastError ?? "库存修正没有保存，请重试。" }
    }
}

struct PetInventoryBatchAllocationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let requests: [PetInventoryBatchAllocationRequest]
    let onConfirm: ([String: [String: Double]]) -> Void
    @State private var quantityTexts: [String: String] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(requests) { request in
                        HomeCard(padding: 12) {
                            VStack(alignment: .leading, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(request.productName)
                                        .font(HomeTypography.cardTitle)
                                        .foregroundStyle(HomeTheme.ink)
                                    Text("分配本次出库 \(request.quantity.formatted())\(request.unit)")
                                        .font(HomeTypography.supporting)
                                        .foregroundStyle(HomeTheme.muted)
                                }
                                ForEach(request.groups) { group in
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(group.expirationDate.map(petExpirationDisplayDate) ?? "未设日期")
                                                .font(HomeTypography.body.weight(.medium))
                                                .foregroundStyle(HomeTheme.ink)
                                            Text("剩余 \(group.remainingQuantity.formatted())\(request.unit)")
                                                .font(HomeTypography.supporting)
                                                .foregroundStyle(HomeTheme.muted)
                                        }
                                        Spacer(minLength: 8)
                                        TextField("0", text: binding(for: request, group: group))
                                            .keyboardType(.decimalPad)
                                            .multilineTextAlignment(.trailing)
                                            .font(HomeTypography.body)
                                            .frame(width: 90)
                                            .accessibilityLabel("\(group.expirationDate.map(petExpirationDisplayDate) ?? "未设日期")分配数量")
                                        Text(request.unit)
                                            .font(HomeTypography.supporting)
                                            .foregroundStyle(HomeTheme.muted)
                                    }
                                    .frame(minHeight: 44)
                                }
                                HStack {
                                    Text("已分配")
                                    Spacer()
                                    Text("\(assigned(for: request).formatted()) / \(request.quantity.formatted())\(request.unit)")
                                        .monospacedDigit()
                                }
                                .font(HomeTypography.supporting)
                                .foregroundStyle(isValid(request) ? HomeTheme.success : HomeTheme.orange)
                            }
                        }
                    }
                    Text("同一到期日期的多次入库会按入库先后扣减。")
                        .font(HomeTypography.supporting)
                        .foregroundStyle(HomeTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(HomeMetrics.pageInset)
            }
            .background(HomeTheme.background)
            .navigationTitle("分配出库批次")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认出库") {
                        var result: [String: [String: Double]] = [:]
                        for request in requests {
                            result[request.productID] = Dictionary(uniqueKeysWithValues: request.groups.map { group in
                                (group.id, parsedQuantity(for: request, group: group))
                            })
                        }
                        onConfirm(result)
                        dismiss()
                    }
                    .disabled(requests.isEmpty || !requests.allSatisfy({ isValid($0) }))
                }
            }
        }
        .presentationDetents(requests.count > 1 ? [.medium, .large] : [.medium])
        .onAppear(perform: initializeQuantities)
    }

    private func binding(for request: PetInventoryBatchAllocationRequest, group: PetInventoryExpiryGroup) -> Binding<String> {
        let key = quantityKey(request.productID, group.id)
        return Binding(
            get: { quantityTexts[key] ?? "0" },
            set: { quantityTexts[key] = $0 }
        )
    }

    private func quantityKey(_ productID: String, _ groupID: String) -> String {
        "\(productID)::\(groupID)"
    }

    private func parsedQuantity(for request: PetInventoryBatchAllocationRequest, group: PetInventoryExpiryGroup) -> Double {
        let text = (quantityTexts[quantityKey(request.productID, group.id)] ?? "0").replacingOccurrences(of: ",", with: ".")
        guard let value = Double(text), value.isFinite, value >= 0 else { return .nan }
        return value
    }

    private func assigned(for request: PetInventoryBatchAllocationRequest) -> Double {
        request.groups.reduce(0) { total, group in
            let value = parsedQuantity(for: request, group: group)
            return total + (value.isFinite ? value : 0)
        }
    }

    private func isValid(_ request: PetInventoryBatchAllocationRequest) -> Bool {
        let values = request.groups.map { parsedQuantity(for: request, group: $0) }
        guard values.allSatisfy({ $0.isFinite }),
              zip(values, request.groups).allSatisfy({ value, group in value <= group.remainingQuantity + 0.000_001 }) else { return false }
        return abs(values.reduce(0, +) - request.quantity) < 0.000_001
    }

    private func initializeQuantities() {
        for request in requests {
            let defaults = PetInventoryBatchLedger.defaultGroupQuantities(quantity: request.quantity, groups: request.groups)
            for group in request.groups {
                quantityTexts[quantityKey(request.productID, group.id)] = (defaults[group.id] ?? 0)
                    .formatted(.number.grouping(.never).precision(.fractionLength(0...4)))
            }
        }
    }
}

struct PetInventoryTransactionHistoryView: View {
    @EnvironmentObject private var store: HomeStore
    let productID: String
    let priceHistoryOnly: Bool
    let onSelectTransaction: (String) -> Void

    private var records: [PetInventoryTransaction] {
        let allRecords = store.petTransactions(for: productID)
        guard priceHistoryOnly else { return allRecords }
        return allRecords.filter { $0.recordedInboundTotalPrice != nil }
    }

    var body: some View {
        List {
            if records.isEmpty {
                Text(priceHistoryOnly ? "暂无已记录金额的入库记录" : "暂无库存流水")
                    .font(HomeTypography.body)
                    .foregroundStyle(HomeTheme.muted)
                    .listRowBackground(Color.clear)
            }
            ForEach(records) { transaction in
                Button {
                    NativeHaptics.tap()
                    onSelectTransaction(transaction.id)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: transaction.quantityChange >= 0 ? "arrow.down.circle" : "arrow.up.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(transaction.quantityChange >= 0 ? HomeTheme.blue : HomeTheme.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(transaction.reason.isEmpty ? transactionTypeTitle(transaction.type) : transaction.reason)
                                .font(HomeTypography.body.weight(.medium))
                                .foregroundStyle(HomeTheme.ink)
                            Text("\(HomeDateText.display(transaction.occurrenceDate)) · \(sourceText(transaction.source))")
                                .font(HomeTypography.supporting)
                                .foregroundStyle(HomeTheme.muted)
                            Text(petTransactionAmountSummary(transaction))
                                .font(HomeTypography.supporting)
                                .foregroundStyle(HomeTheme.muted)
                            if let note = transaction.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                                Text("备注 · \(note)")
                                    .font(HomeTypography.supporting)
                                    .foregroundStyle(HomeTheme.muted)
                            }
                        }
                        Spacer(minLength: 8)
                        Text("\(transaction.quantityChange > 0 ? "+" : "")\(transaction.quantityChange.formatted())\(transaction.unit)")
                            .font(HomeTypography.body.weight(.semibold))
                            .foregroundStyle(transaction.quantityChange >= 0 ? HomeTheme.success : HomeTheme.orange)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 3)
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, minHeight: HomeMetrics.minimumTapTarget, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(HomeTheme.background)
        .navigationTitle(priceHistoryOnly ? "全部价格历史" : "全部库存记录")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func transactionTypeTitle(_ type: PetInventoryTransactionType) -> String {
        switch type {
        case .inbound: "入库"
        case .outbound: "出库"
        case .adjustment: "库存修正"
        }
    }
}

enum PetInventoryTransactionDetailRow: String, CaseIterable, Identifiable, Equatable {
    case quantity
    case totalPrice
    case unitPrice
    case note
    case time

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quantity: "数量"
        case .totalPrice: "本次总价"
        case .unitPrice: "折算单价"
        case .note: "备注"
        case .time: "时间"
        }
    }
}

struct PetInventoryTransactionEditorView: View {
    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    let transactionID: String
    @State private var quantityText = ""
    @State private var totalPriceText = ""
    @State private var date = Date()
    @State private var hasExpiration = false
    @State private var expirationDate = Date()
    @State private var note = ""
    @State private var loaded = false
    @State private var isEditing = false
    @State private var confirmDelete = false
    @State private var batchAllocationRequest: PetInventoryBatchAllocationRequest?
    @State private var localError: String?

    private var transaction: PetInventoryTransaction? {
        store.data.petInventoryTransactions.first { $0.id == transactionID }
    }
    private var item: PetItem? {
        guard let transaction else { return nil }
        return store.data.petItems.first { $0.id == transaction.productID }
    }
    private var quantity: Double? {
        Double(quantityText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }
    private var cleanedPriceText: String {
        totalPriceText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
    }
    private var totalPrice: Double? {
        guard !cleanedPriceText.isEmpty, let value = Double(cleanedPriceText), value.isFinite, value >= 0 else { return nil }
        return value
    }
    private var canEditRecord: Bool {
        guard let transaction else { return false }
        return transaction.type != .adjustment && !isLitterLinked(transaction)
    }
    private var canEditTotalPrice: Bool {
        canEditRecord && transaction?.type == .inbound
    }
    private var canDeleteTransaction: Bool {
        guard let transaction else { return false }
        return !isLitterLinked(transaction)
    }
    private var canEnterEditMode: Bool { canDeleteTransaction }
    private var isLitterReadOnly: Bool {
        guard let transaction else { return false }
        return isLitterLinked(transaction)
    }
    private var canSave: Bool {
        isEditing && canEditRecord
            && (quantity ?? 0) > 0
            && (!canEditTotalPrice || cleanedPriceText.isEmpty || totalPrice != nil)
    }
    private var calculatedUnitPrice: Double? {
        guard let quantity, quantity > 0, let totalPrice, totalPrice > 0 else { return nil }
        let unitPrice = totalPrice / quantity
        return unitPrice.isFinite && unitPrice > 0 ? unitPrice : nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let transaction, let item {
                        HomeCard {
                            VStack(spacing: 0) {
                                ForEach(PetInventoryTransactionDetailRow.allCases) { row in
                                    if row != .quantity {
                                        Divider().overlay(HomeTheme.line)
                                    }
                                    detailRow(row, transaction: transaction, item: item)
                                }
                            }
                        }

                        if transaction.type == .inbound {
                            HomeCard {
                                if isEditing {
                                    if transaction.tracksExpirationBatch == true {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Toggle("记录到期日期", isOn: $hasExpiration)
                                            if hasExpiration {
                                                DatePicker("到期日期", selection: $expirationDate, displayedComponents: .date)
                                                    .datePickerStyle(.compact)
                                            }
                                        }
                                        .font(HomeTypography.body)
                                    } else {
                                        Text("这条旧入库包含未分配批次的历史出库，剩余库存仍按“未设日期”保留，无法单独修改到期日期。")
                                            .font(HomeTypography.supporting)
                                            .foregroundStyle(HomeTheme.muted)
                                    }
                                } else {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("到期日期").font(HomeTypography.body).foregroundStyle(HomeTheme.ink)
                                            Spacer()
                                            Text(transaction.expirationDate.map(petExpirationDisplayDate) ?? "未设日期")
                                                .font(HomeTypography.body)
                                                .foregroundStyle(transaction.expirationDate == nil ? HomeTheme.muted : HomeTheme.ink)
                                        }
                                        if transaction.tracksExpirationBatch != true, transaction.expirationDate != nil {
                                            Text("该旧批次的剩余库存无法可靠对应到期日期，已按“未设日期”计入库存。")
                                                .font(HomeTypography.supporting)
                                                .foregroundStyle(HomeTheme.muted)
                                        }
                                    }
                                    .frame(minHeight: HomeMetrics.controlHeight, alignment: .center)
                                }
                            }
                        }

                        if isLitterReadOnly {
                            Text("猫砂联动流水只读，请通过补充或换洗操作管理。")
                                .font(HomeTypography.supporting)
                                .foregroundStyle(HomeTheme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if isEditing && canDeleteTransaction {
                            Button("删除这条记录", role: .destructive) {
                                confirmDelete = true
                                NativeHaptics.warning()
                            }
                            .font(HomeTypography.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(HomeTheme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    } else {
                        EmptyState(icon: "exclamationmark.triangle.fill", title: "记录不存在", message: "该记录可能已被删除。")
                    }
                }
                .padding(HomeMetrics.pageInset)
            }
            .background(HomeTheme.background)
            .navigationTitle(isEditing ? (canEditRecord ? "编辑记录" : "记录管理") : "查看记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEditing ? "取消" : "完成") {
                        if isEditing { cancelEditing() } else { dismiss() }
                    }
                }
                if isEditing {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存", action: save).disabled(!canSave)
                    }
                } else if canEnterEditMode {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("编辑", action: beginEditing)
                    }
                }
            }
        }
        .task { load() }
        .sheet(item: $batchAllocationRequest) { request in
            PetInventoryBatchAllocationSheet(requests: [request]) { quantities in
                save(batchGroupQuantities: quantities[request.productID])
            }
        }
        .confirmationDialog("删除这条记录？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除这条记录", role: .destructive, action: deleteRecord)
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除整条库存流水（含数量、金额和备注），并按发生日期重算当前库存、后续库存快照和出库成本。若后续流水会造成历史库存不足，系统将拒绝删除并保留原数据。")
        }
        .alert("记录操作失败", isPresented: Binding(
            get: { localError != nil },
            set: { if !$0 { localError = nil } }
        )) {
            Button("知道了") { localError = nil }
        } message: {
            Text(localError ?? "请检查后重试。")
        }
    }

    private func detailRow(
        _ row: PetInventoryTransactionDetailRow,
        transaction: PetInventoryTransaction,
        item: PetItem
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(detailRowTitle(row, transaction: transaction))
                .font(HomeTypography.body)
                .foregroundStyle(HomeTheme.ink)
            Spacer(minLength: 8)
            rowValue(row, transaction: transaction, item: item)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minHeight: HomeMetrics.controlHeight)
    }

    private func detailRowTitle(
        _ row: PetInventoryTransactionDetailRow,
        transaction: PetInventoryTransaction
    ) -> String {
        guard row == .quantity else { return row.title }
        if isEditing && canEditRecord { return row.title }
        switch transaction.type {
        case .inbound: return "入库数量"
        case .outbound: return "出库数量"
        case .adjustment: return "修正变化"
        }
    }

    @ViewBuilder
    private func rowValue(
        _ row: PetInventoryTransactionDetailRow,
        transaction: PetInventoryTransaction,
        item: PetItem
    ) -> some View {
        switch row {
        case .quantity:
            if isEditing && canEditRecord {
                HStack(spacing: 5) {
                    TextField("数量", text: $quantityText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(HomeTypography.body)
                        .accessibilityLabel("数量")
                    Text(transaction.unit).font(HomeTypography.body).foregroundStyle(HomeTheme.muted)
                }
            } else {
                displayedQuantity(transaction)
            }
        case .totalPrice:
            if isEditing && canEditTotalPrice {
                HStack(spacing: 4) {
                    TextField("未记录", text: $totalPriceText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(HomeTypography.body)
                        .accessibilityLabel("本次总价，可留空")
                    Text("元").font(HomeTypography.body).foregroundStyle(HomeTheme.muted)
                }
            } else {
                Text(displayedTotalPrice(transaction).map(currency2) ?? "未记录")
                    .font(HomeTypography.body)
                    .foregroundStyle(displayedTotalPrice(transaction) == nil ? HomeTheme.muted : HomeTheme.ink)
            }
        case .unitPrice:
            let value = isEditing && canEditTotalPrice ? calculatedUnitPrice : displayedUnitPrice(transaction)
            if let value {
                HStack(spacing: 4) {
                    Text(currency2(value))
                        .font(HomeTypography.body)
                        .foregroundStyle(HomeTheme.ink)
                    Text("/\(item.unit)")
                        .font(HomeTypography.supporting)
                        .foregroundStyle(HomeTheme.muted)
                }
            } else {
                Text("未记录")
                    .font(HomeTypography.body)
                    .foregroundStyle(HomeTheme.muted)
            }
        case .note:
            if isEditing && canEditRecord {
                TextField("未填写", text: $note, axis: .vertical)
                    .lineLimit(1...)
                    .multilineTextAlignment(.trailing)
                    .font(HomeTypography.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("备注")
            } else {
                let value = transaction.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                Text(value.isEmpty ? "未填写" : value)
                    .font(HomeTypography.body)
                    .foregroundStyle(value.isEmpty ? HomeTheme.muted : HomeTheme.ink)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .time:
            if isEditing && canEditRecord {
                DatePicker("时间", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .font(HomeTypography.body)
                    .tint(HomeTheme.blue)
                    .accessibilityLabel("时间")
            } else {
                Text(fullChineseDate(transaction.occurrenceDate))
                    .font(HomeTypography.body)
                    .foregroundStyle(HomeTheme.ink)
            }
        }
    }

    @ViewBuilder
    private func displayedQuantity(_ transaction: PetInventoryTransaction) -> some View {
        switch transaction.type {
        case .inbound, .outbound:
            HStack(spacing: 4) {
                Text(abs(transaction.quantityChange).formatted())
                    .font(HomeTypography.body)
                    .foregroundStyle(HomeTheme.ink)
                Text(transaction.unit)
                    .font(HomeTypography.supporting)
                    .foregroundStyle(HomeTheme.muted)
            }
        case .adjustment:
            HStack(spacing: 4) {
                Text(transaction.quantityChange >= 0 ? "增加" : "减少")
                    .font(HomeTypography.supporting)
                    .foregroundStyle(HomeTheme.muted)
                Text(abs(transaction.quantityChange).formatted())
                    .font(HomeTypography.body)
                    .foregroundStyle(HomeTheme.ink)
                Text(transaction.unit)
                    .font(HomeTypography.supporting)
                    .foregroundStyle(HomeTheme.muted)
            }
        }
    }

    private func load() {
        guard !loaded, let transaction else { return }
        loaded = true
        loadFields(from: transaction)
    }

    private func loadFields(from transaction: PetInventoryTransaction) {
        quantityText = abs(transaction.quantityChange).formatted(.number.precision(.fractionLength(0...4)))
        totalPriceText = canEditTotalPrice
            ? (transaction.recordedInboundTotalPrice.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "")
            : ""
        date = LitterPredictionService.parse(transaction.occurrenceDate) ?? Date()
        hasExpiration = PetInventoryBatchLedger.validExpirationDate(transaction.expirationDate) != nil
        expirationDate = transaction.expirationDate.flatMap { LitterPredictionService.parse($0) } ?? Date()
        note = transaction.note ?? ""
    }

    private func beginEditing() {
        guard canEnterEditMode, let transaction else { return }
        loadFields(from: transaction)
        isEditing = true
        NativeHaptics.tap()
    }

    private func cancelEditing() {
        if let transaction { loadFields(from: transaction) }
        isEditing = false
    }

    private func save() {
        guard let transaction, let item, let quantity, quantity > 0 else {
            localError = "请输入大于 0 的数量"
            NativeHaptics.error()
            return
        }
        if transaction.type == .outbound {
            let groups = store.petInventoryBatchGroups(for: transaction.productID, excludingTransactionID: transaction.id)
            let availableWithoutThisRecord = groups.reduce(0) { $0 + $1.remainingQuantity }
            if groups.count > 1, quantity <= availableWithoutThisRecord {
                batchAllocationRequest = PetInventoryBatchAllocationRequest(
                    productID: transaction.productID,
                    productName: item.displayTitle,
                    quantity: quantity,
                    unit: transaction.unit,
                    groups: groups
                )
                return
            }
        }
        save(batchGroupQuantities: nil)
    }

    private func save(batchGroupQuantities: [String: Double]?) {
        guard let quantity, quantity > 0 else {
            localError = "请输入大于 0 的数量"
            NativeHaptics.error()
            return
        }
        guard !canEditTotalPrice || cleanedPriceText.isEmpty || totalPrice != nil else {
            localError = "请输入有效金额，或留空表示未记录"
            NativeHaptics.error()
            return
        }
        let success = store.updatePetInventoryTransaction(
            id: transactionID,
            quantity: quantity,
            occurrenceDate: LitterPredictionService.format(date),
            totalPrice: canEditTotalPrice ? totalPrice : nil,
            note: note,
            expirationDate: hasExpiration ? LitterPredictionService.format(expirationDate) : nil,
            updateExpirationDate: transaction?.type == .inbound && transaction?.tracksExpirationBatch == true,
            batchGroupQuantities: batchGroupQuantities
        )
        if success {
            isEditing = false
            if let updated = transaction { loadFields(from: updated) }
        } else {
            localError = store.lastError ?? "记录没有保存，请重试。"
        }
    }

    private func deleteRecord() {
        if store.deletePetInventoryTransaction(id: transactionID) {
            dismiss()
        } else {
            localError = store.lastError ?? "记录没有删除，原数据已保留。"
        }
    }

    private func displayedTotalPrice(_ transaction: PetInventoryTransaction) -> Double? {
        switch transaction.type {
        case .inbound: transaction.recordedInboundTotalPrice
        case .outbound: transaction.recordedOutboundTotalPrice
        case .adjustment: nil
        }
    }

    private func displayedUnitPrice(_ transaction: PetInventoryTransaction) -> Double? {
        switch transaction.type {
        case .inbound: return transaction.recordedInboundUnitPrice
        case .outbound:
            if let unitPrice = transaction.unitPrice, unitPrice.isFinite, unitPrice > 0 { return unitPrice }
            guard let total = transaction.recordedOutboundTotalPrice, transaction.quantityChange != 0 else { return nil }
            let unitPrice = total / abs(transaction.quantityChange)
            return unitPrice.isFinite && unitPrice > 0 ? unitPrice : nil
        case .adjustment: return nil
        }
    }

    private func fullChineseDate(_ storedDate: String) -> String {
        guard let value = LitterPredictionService.parse(storedDate) else { return storedDate }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: value)
    }

    private func isLitterLinked(_ transaction: PetInventoryTransaction) -> Bool {
        transaction.linkedOperationID != nil
            || transaction.source == .litterRefill
            || transaction.source == .litterReplace
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
    private var existingReview: PetProductReview? {
        guard let reviewID else { return nil }
        return store.data.petProductReviews.first { $0.id == reviewID && $0.productID == productID }
    }
    private var dimensions: [String] {
        if let existingReview {
            return orderedPetReviewDimensions(existingReview.resolvedDimensionScores, item: item)
        }
        return item.map(petRatingDimensions) ?? ["使用体验", "品质", "性价比", "回购意愿"]
    }
    private var overallScore: Double {
        if scores.isEmpty, let existingReview { return existingReview.overallScore }
        let values = dimensions.compactMap { scores[$0] }
        guard !values.isEmpty else { return 0 }
        return Double(values.reduce(0, +)) / Double(values.count)
    }
    var body: some View {
        NavigationStack {
            Form {
                if let item {
                    Section { LabeledContent("物品", value: item.displayTitle) }
                }
                if isLegacyLitterReview {
                    Section {
                        Text("这条历史评价保留原评分维度。保存时不会把旧维度转换成猫砂新维度，也不会补造分数。")
                            .font(HomeTypography.supporting)
                            .foregroundStyle(HomeTheme.muted)
                    }
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
                TextField("产品评价", text: $review, axis: .vertical).font(HomeTypography.body)
                DatePicker("评价日期", selection: $date, displayedComponents: .date)
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
        if let existingReview {
            scores = existingReview.resolvedDimensionScores
            review = existingReview.reviewText
            date = LitterPredictionService.parse(existingReview.reviewDate) ?? Date()
        } else {
            dimensions.forEach { if scores[$0] == nil { scores[$0] = 3 } }
        }
    }

    private var isLegacyLitterReview: Bool {
        guard item?.isLitterProduct == true, let existingReview else { return false }
        let currentLitterDimensions: Set<String> = ["除臭性", "结团性", "耐用性", "性价比"]
        return Set(existingReview.resolvedDimensionScores.keys) != currentLitterDimensions
    }

    private func scoreBinding(for dimension: String) -> Binding<Int> {
        Binding(get: { scores[dimension] ?? 3 }, set: { scores[dimension] = $0; NativeHaptics.selection() })
    }
}

struct PetPalatabilityEditorView: View {
    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    let productID: String
    var reviewID: String? = nil
    @State private var petID = ""
    @State private var score = 3
    @State private var note = ""
    @State private var date = Date()
    @State private var loaded = false
    var body: some View {
        NavigationStack {
            Form {
                petSelector
                Picker("评价", selection: $score) { ForEach(1...5, id: \.self) { Text("\($0)分").tag($0) } }.pickerStyle(.segmented)
                TextField("备注（可选）", text: $note, axis: .vertical).font(HomeTypography.body)
                DatePicker("评价日期", selection: $date, displayedComponents: .date)
            }
            .navigationTitle(reviewID == nil ? "添加猫咪评价" : "编辑猫咪评价").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { if store.savePetPalatabilityReview(id: reviewID, productID: productID, petID: petID, date: LitterPredictionService.format(date), score: score, note: note) { dismiss() } }.disabled(petID.isEmpty) }
            }
            .task { loadReview() }
        }.presentationDetents([.medium])
    }

    private var petSelector: some View {
        HStack(spacing: 14) {
            Text("宠物")
            Spacer(minLength: 8)
            ScrollView(.horizontal) {
                HStack(spacing: 18) {
                    ForEach(store.activePets) { pet in
                        Button {
                            guard petID != pet.id else { return }
                            petID = pet.id
                            NativeHaptics.selection()
                        } label: {
                            VStack(spacing: 4) {
                                Text(pet.name)
                                    .font(HomeTypography.body.weight(petID == pet.id ? .semibold : .regular))
                                    .foregroundStyle(petID == pet.id ? HomeTheme.blue : HomeTheme.muted)
                                    .lineLimit(1)
                                Capsule()
                                    .fill(petID == pet.id ? HomeTheme.blue : Color.clear)
                                    .frame(height: 2)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func loadReview() {
        guard !loaded else { return }
        defer { loaded = true }
        if let reviewID,
           let existing = store.data.petPalatabilityReviews.first(where: { $0.id == reviewID && $0.productID == productID }) {
            petID = existing.petID
            score = existing.resolvedScore
            note = existing.note ?? ""
            date = LitterPredictionService.parse(existing.reviewDate) ?? Date()
        } else if petID.isEmpty {
            petID = store.activePets.first?.id ?? ""
        }
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
                                Spacer(); Text("\(review.resolvedScore)分").font(HomeTypography.body).foregroundStyle(palatabilityScoreColor(review.resolvedScore))
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
