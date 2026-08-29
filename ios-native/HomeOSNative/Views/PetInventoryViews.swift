import SwiftUI
import PhotosUI

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
    @State private var unit = "袋"
    @State private var initialStock = 0.0
    @State private var lowStock = 0.0
    @State private var notes = ""
    @State private var foodRole = "主食"
    @State private var litterKind = ""
    @State private var conversion = 0.0
    @State private var imageReference: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var loaded = false

    init(itemID: String? = nil) { self.itemID = itemID }
    private var primaryCategories: [ManagedCategory] { store.categories(for: .pet) }
    private var selectedPrimary: ManagedCategory? { primaryCategories.first { $0.id == primaryID } ?? primaryCategories.first }
    private var secondaryCategories: [ManagedCategory] { selectedPrimary.map { store.categories(for: .pet, parentID: $0.id) } ?? [] }
    private var selectedSecondary: ManagedCategory? { secondaryCategories.first { $0.id == secondaryID } ?? secondaryCategories.first }
    private var isPetFood: Bool { selectedPrimary?.capabilityKey == "petFood" }

    var body: some View {
        Form {
            Section("分类") {
                Picker("一级分类", selection: $primaryID) { ForEach(primaryCategories) { Text($0.name).tag($0.id) } }
                Picker("二级分类", selection: $secondaryID) { ForEach(secondaryCategories) { Text($0.name).tag($0.id) } }
                NavigationLink("管理分类") { CategoryManagementView(initialModule: .pet) }
            }
            Section("产品档案") {
                TextField("产品名称", text: $name).font(HomeTypography.body)
                TextField("品牌（可选）", text: $brand).font(HomeTypography.body)
                TextField("口味、配方或型号（可选）", text: $variant).font(HomeTypography.body)
                TextField("规格（可选）", text: $spec).font(HomeTypography.body)
                TextField("库存单位", text: $unit).font(HomeTypography.body)
                TextField("低库存提醒值（可选）", value: $lowStock, format: .number).keyboardType(.decimalPad)
                if itemID == nil { TextField("初始库存", value: $initialStock, format: .number).keyboardType(.decimalPad) }
                TextField("备注（可选）", text: $notes, axis: .vertical).font(HomeTypography.body)
            }
            if isPetFood {
                Section("食品信息") { Picker("属性", selection: $foodRole) { Text("主食").tag("主食"); Text("零食").tag("零食") } }
            }
            if selectedSecondary?.name == "猫砂" {
                Section("猫砂信息") {
                    TextField("猫砂种类，例如矿砂", text: $litterKind).font(HomeTypography.body)
                    TextField("每个库存单位折合 kg", value: $conversion, format: .number.precision(.fractionLength(0...4))).keyboardType(.decimalPad)
                }
            }
            Section("图片") {
                PhotosPicker(selection: $selectedPhoto, matching: .images) { Label(imageReference == nil ? "选择图片" : "更换图片", systemImage: "photo") }
                if let imageReference {
                    PetStoredImage(reference: imageReference).frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Button("删除图片", role: .destructive) { self.imageReference = nil }
                }
            }
        }
        .navigationTitle(itemID == nil ? "新增宠物物品" : "编辑宠物物品").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
        .task { loadExisting() }
        .onChange(of: primaryID) { _, _ in secondaryID = secondaryCategories.first?.id ?? "" }
        .onChange(of: selectedPhoto) { _, photo in Task { if let data = try? await photo?.loadTransferable(type: Data.self) { imageReference = "data:image/jpeg;base64," + data.base64EncodedString() } } }
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
        variant = item.variant ?? item.model; spec = item.spec; unit = item.unit; lowStock = item.lowStockThreshold ?? 0
        notes = item.notes ?? ""; foodRole = item.foodRole ?? "主食"; litterKind = item.litterKind ?? ""
        conversion = item.unitConversionToBase ?? 0; imageReference = item.image
    }

    private func save() {
        let existing = itemID.flatMap { id in store.data.petItems.first { $0.id == id } }
        let now = Date().timeIntervalSince1970
        guard let selectedPrimary, let selectedSecondary else { return }
        var item = existing ?? PetItem(id: UUID().uuidString, type: selectedSecondary.name, name: name, brand: brand, model: variant, spec: spec, quantity: max(initialStock, 0), unit: unit, days: 0, weeklyUsage: nil, lastReplenishedAt: nil, purchaseHistory: nil, replenishmentHistory: nil, feedback: nil, price: nil, cat: "", preference: "", image: imageReference, unitConversionToBase: nil)
        let savedSecondary = selectedSecondary.name
        item.type = savedSecondary; item.name = name.trimmingCharacters(in: .whitespacesAndNewlines); item.brand = brand; item.model = variant; item.spec = spec
        item.unit = unit.trimmingCharacters(in: .whitespacesAndNewlines); item.primaryCategory = selectedPrimary.name; item.secondaryCategory = savedSecondary
        item.variant = variant.isEmpty ? nil : variant; item.lowStockThreshold = lowStock > 0 ? lowStock : nil; item.notes = notes.isEmpty ? nil : notes
        item.foodRole = isPetFood ? foodRole : nil; item.litterKind = savedSecondary == "猫砂" ? (litterKind.isEmpty ? nil : litterKind) : nil
        item.unitConversionToBase = conversion > 0 ? conversion : nil; item.image = imageReference; item.isArchived = false
        item.createdAt = item.createdAt ?? now; item.updatedAt = now
        store.upsertPetItem(item); NativeHaptics.success(); dismiss()
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
    @State private var target = 0.0
    @State private var date = Date()
    @State private var reason = ""
    @State private var totalPrice = 0.0
    @State private var channel = ""
    @State private var note = ""
    @State private var hasExpiration = false
    @State private var expirationDate = Date()

    private var item: PetItem? { store.data.petItems.first { $0.id == productID } }
    private var title: String { mode == .inbound ? "入库" : mode == .outbound ? (quick ? "快速出库" : "出库") : "修正库存" }

    var body: some View {
        NavigationStack {
            Form {
                if let item { Section { LabeledContent("产品", value: item.name); LabeledContent("当前库存", value: "\(store.petInventory(for: productID).formatted())\(item.unit)") } }
                Section(title) {
                    if mode == .adjustment { TextField("调整后数量", value: $target, format: .number).keyboardType(.decimalPad) }
                    else { TextField("数量", value: $quantity, format: .number).keyboardType(.decimalPad) }
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    TextField(mode == .outbound ? "出库原因" : "原因（可选）", text: $reason).font(HomeTypography.body)
                }
                if mode == .inbound {
                    Section("购买信息") {
                        TextField("购买总价（可选）", value: $totalPrice, format: .currency(code: "CNY")).keyboardType(.decimalPad)
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
                ToolbarItem(placement: .confirmationAction) { Button("完成", action: save).disabled(mode == .adjustment ? target < 0 : quantity <= 0) }
            }
        }
        .presentationDetents(quick ? [.medium] : [.medium, .large])
        .task { if mode == .adjustment { target = store.petInventory(for: productID) } }
    }

    private func save() {
        let dateString = LitterPredictionService.format(date)
        let success: Bool
        if mode == .adjustment {
            success = store.adjustPetInventory(productID: productID, target: target, occurrenceDate: dateString, reason: reason)
        } else {
            success = store.recordPetInventory(productID: productID, type: mode == .inbound ? .inbound : .outbound, quantity: quantity, occurrenceDate: dateString, reason: reason.isEmpty ? (mode == .inbound ? "购买入库" : "日常使用") : reason, totalPrice: totalPrice > 0 ? totalPrice : nil, purchaseChannel: channel, expirationDate: hasExpiration ? LitterPredictionService.format(expirationDate) : nil, note: note)
        }
        if success { dismiss() }
    }
}

struct PetProductReviewEditorView: View {
    @EnvironmentObject private var store: HomeStore
    @Environment(\.dismiss) private var dismiss
    let productID: String
    @State private var level = 3
    @State private var review = ""
    @State private var date = Date()
    var body: some View {
        NavigationStack {
            Form {
                Picker("回购指数", selection: $level) { ForEach(1...5, id: \.self) { Text(repurchaseText($0)).tag($0) } }
                DatePicker("评价日期", selection: $date, displayedComponents: .date)
                TextField("产品评价", text: $review, axis: .vertical).font(HomeTypography.body)
            }
            .navigationTitle("添加产品评价").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { if store.addPetProductReview(productID: productID, date: LitterPredictionService.format(date), level: level, text: review) { dismiss() } } }
            }
        }.presentationDetents([.medium])
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
