import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class HomeStore: ObservableObject {
    @Published private(set) var data: HomeBackup = .empty
    @Published var lastError: String?

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder = JSONDecoder()
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HomeOSNative", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("home-os-v1.json")
        load()
    }

    func load() {
        guard let stored = try? Data(contentsOf: fileURL) else {
            data = .empty
            return
        }
        do {
            let decoded = try decoder.decode(HomeBackup.self, from: stored)
            let migrated = normalizedCategories(in: migratedPetInventory(decoded))
            data = migrated
            if migrated != decoded { _ = commit(migrated) }
        } catch {
            lastError = "本机数据读取失败：\(error.localizedDescription)"
            data = .empty
        }
    }

    func replace(with backup: HomeBackup) {
        commit(normalizedCategories(in: backup))
    }

    func clearAll() {
        if commit(.empty) { NativeHaptics.success() }
    }

    func importBackup(from url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let imported = try decoder.decode(HomeBackup.self, from: Data(contentsOf: url))
            replace(with: normalizedCategories(in: migratedPetInventory(imported)))
            NativeHaptics.success()
        } catch {
            lastError = "备份导入失败：\(error.localizedDescription)"
            NativeHaptics.error()
        }
    }

    func encodedBackup() -> Data {
        (try? encoder.encode(data)) ?? Data("{}".utf8)
    }

    var dueFoods: [FoodItem] {
        guard data.settings.expiryReminderEnabled != false else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return data.foods.filter { item in
            guard let date = formatter.date(from: item.expiry),
                  let days = calendar.dateComponents([.day], from: start, to: date).day else { return false }
            return days <= data.settings.threshold
        }.sorted { $0.expiry < $1.expiry }
    }

    var activePets: [PetProfile] {
        data.pets.filter { !$0.isDeleted }.sorted { $0.createdAt < $1.createdAt }
    }

    var activePetEventCategories: [PetEventCategory] {
        data.petEventCategories.filter { !$0.isDeleted }.sorted { $0.createdAt < $1.createdAt }
    }

    var litterProducts: [PetItem] {
        data.petItems.filter { item in
            !item.isArchived && (item.secondaryCategory == "猫砂"
                || item.type.localizedCaseInsensitiveContains("猫砂")
                || item.name.localizedCaseInsensitiveContains("猫砂"))
        }
    }

    var activePetItems: [PetItem] {
        data.petItems.filter { !$0.isArchived }
    }

    func brands(for module: ManagedCategoryModule) -> [ManagedBrand] {
        let source = data.settings.managedBrands ?? defaultManagedBrands(for: data)
        return source
            .filter { !$0.isArchived && $0.modules.contains(module) }
            .sorted {
                let leftCount = brandUsageCount(named: $0.name, module: module)
                let rightCount = brandUsageCount(named: $1.name, module: module)
                return leftCount == rightCount
                    ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    : leftCount > rightCount
            }
    }

    func addManagedBrand(name: String, modules: [ManagedCategoryModule]) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return fail("品牌名称不能为空") }
        guard !modules.isEmpty else { return fail("请至少选择一个适用范围") }
        var next = data
        var brands = next.settings.managedBrands ?? defaultManagedBrands(for: next)
        guard !brands.contains(where: { !$0.isArchived && $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }) else {
            return fail("品牌名称不能重复")
        }
        let now = Date().timeIntervalSince1970
        brands.append(ManagedBrand(id: UUID().uuidString, name: cleanName, modules: modules, isArchived: false, createdAt: now, updatedAt: now))
        next.settings.managedBrands = brands
        return commit(next)
    }

    func renameManagedBrand(id: String, name: String) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return fail("品牌名称不能为空") }
        var next = data
        var brands = next.settings.managedBrands ?? defaultManagedBrands(for: next)
        guard let index = brands.firstIndex(where: { $0.id == id }) else { return fail("找不到品牌") }
        guard !brands.contains(where: { $0.id != id && !$0.isArchived && $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }) else {
            return fail("品牌名称不能重复")
        }
        let oldName = brands[index].name
        brands[index].name = cleanName
        brands[index].updatedAt = Date().timeIntervalSince1970
        next.petItems.indices.filter { next.petItems[$0].brand.caseInsensitiveCompare(oldName) == .orderedSame }.forEach { next.petItems[$0].brand = cleanName }
        next.foods.indices.filter { next.foods[$0].brand.caseInsensitiveCompare(oldName) == .orderedSame }.forEach { next.foods[$0].brand = cleanName }
        next.settings.managedBrands = brands
        return commit(next)
    }

    func setManagedBrandModules(id: String, modules: [ManagedCategoryModule]) -> Bool {
        guard !modules.isEmpty else { return fail("请至少选择一个适用范围") }
        var next = data
        var brands = next.settings.managedBrands ?? defaultManagedBrands(for: next)
        guard let index = brands.firstIndex(where: { $0.id == id }) else { return fail("找不到品牌") }
        brands[index].modules = modules
        brands[index].updatedAt = Date().timeIntervalSince1970
        next.settings.managedBrands = brands
        return commit(next)
    }

    func archiveManagedBrand(id: String) -> Bool {
        var next = data
        var brands = next.settings.managedBrands ?? defaultManagedBrands(for: next)
        guard let index = brands.firstIndex(where: { $0.id == id }) else { return fail("找不到品牌") }
        brands[index].isArchived = true
        brands[index].updatedAt = Date().timeIntervalSince1970
        next.settings.managedBrands = brands
        return commit(next)
    }

    func mergeManagedBrand(sourceID: String, destinationID: String) -> Bool {
        guard sourceID != destinationID else { return fail("请选择不同的目标品牌") }
        var next = data
        var brands = next.settings.managedBrands ?? defaultManagedBrands(for: next)
        guard let sourceIndex = brands.firstIndex(where: { $0.id == sourceID }),
              let destination = brands.first(where: { $0.id == destinationID && !$0.isArchived }) else { return fail("找不到品牌") }
        let sourceName = brands[sourceIndex].name
        next.petItems.indices.filter { next.petItems[$0].brand.caseInsensitiveCompare(sourceName) == .orderedSame }.forEach { next.petItems[$0].brand = destination.name }
        next.foods.indices.filter { next.foods[$0].brand.caseInsensitiveCompare(sourceName) == .orderedSame }.forEach { next.foods[$0].brand = destination.name }
        brands[sourceIndex].isArchived = true
        brands[sourceIndex].updatedAt = Date().timeIntervalSince1970
        next.settings.managedBrands = brands
        return commit(next)
    }

    func brandUsageCount(named name: String, module: ManagedCategoryModule) -> Int {
        switch module {
        case .pet:
            activePetItems.filter { $0.brand.caseInsensitiveCompare(name) == .orderedSame }.count
        case .food:
            data.foods.filter { $0.brand.caseInsensitiveCompare(name) == .orderedSame }.count
        case .recipe:
            0
        }
    }

    func categories(for module: ManagedCategoryModule, parentID: String? = nil) -> [ManagedCategory] {
        let source = data.settings.managedCategories ?? defaultManagedCategories(for: data)
        return source
            .filter { $0.module == module && $0.parentID == parentID && !$0.isArchived }
            .sorted { $0.sortOrder == $1.sortOrder ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.sortOrder < $1.sortOrder }
    }

    func petRootCategory(capabilityKey: String) -> ManagedCategory? {
        categories(for: .pet).first { $0.capabilityKey == capabilityKey }
    }

    func addManagedCategory(module: ManagedCategoryModule, parentID: String?, name: String, icon: String? = nil) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return fail("分类名称不能为空") }
        var next = normalizedCategories(in: data)
        let siblings = (next.settings.managedCategories ?? []).filter {
            $0.module == module && $0.parentID == parentID && !$0.isArchived
        }
        guard !siblings.contains(where: { $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }) else {
            return fail("同一级分类名称不能重复")
        }
        if let parentID {
            guard (next.settings.managedCategories ?? []).contains(where: { $0.id == parentID && $0.module == module && !$0.isArchived }) else {
                return fail("找不到一级分类")
            }
        }
        next.settings.managedCategories?.append(ManagedCategory(
            id: UUID().uuidString, module: module, parentID: parentID, name: cleanName,
            icon: icon ?? defaultCategoryIcon(module), sortOrder: siblings.count, isSystem: false,
            capabilityKey: nil, isArchived: false
        ))
        guard commit(next) else { return false }
        NativeHaptics.success()
        return true
    }

    func renameManagedCategory(id: String, name: String) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return fail("分类名称不能为空") }
        var next = normalizedCategories(in: data)
        guard let index = next.settings.managedCategories?.firstIndex(where: { $0.id == id }) else { return fail("找不到分类") }
        let category = next.settings.managedCategories![index]
        guard !(next.settings.managedCategories ?? []).contains(where: {
            $0.id != id && $0.module == category.module && $0.parentID == category.parentID && !$0.isArchived
                && $0.name.caseInsensitiveCompare(cleanName) == .orderedSame
        }) else { return fail("同一级分类名称不能重复") }
        let oldName = category.name
        next.settings.managedCategories![index].name = cleanName

        switch category.module {
        case .pet:
            if category.parentID == nil {
                for itemIndex in next.petItems.indices where next.petItems[itemIndex].resolvedPrimaryCategory == oldName {
                    next.petItems[itemIndex].primaryCategory = cleanName
                }
            } else {
                for itemIndex in next.petItems.indices where next.petItems[itemIndex].resolvedSecondaryCategory == oldName {
                    next.petItems[itemIndex].secondaryCategory = cleanName
                    next.petItems[itemIndex].type = cleanName
                }
            }
        case .food:
            for itemIndex in next.foods.indices where next.foods[itemIndex].category == oldName { next.foods[itemIndex].category = cleanName }
            next.settings.foodCategoryOrder = next.settings.foodCategoryOrder?.map { $0 == oldName ? cleanName : $0 }
            next.settings.foodCategories = next.settings.foodCategories?.map { definition in
                definition.name == oldName ? CategoryDefinition(name: cleanName, icon: definition.icon) : definition
            }
        case .recipe:
            for itemIndex in next.recipes.indices where next.recipes[itemIndex].collection == oldName { next.recipes[itemIndex].collection = cleanName }
            next.settings.recipeCollections = next.settings.recipeCollections?.map { $0 == oldName ? cleanName : $0 }
        }
        guard commit(next) else { return false }
        NativeHaptics.success()
        return true
    }

    func setManagedCategoryIcon(id: String, icon: String) -> Bool {
        var next = normalizedCategories(in: data)
        guard let index = next.settings.managedCategories?.firstIndex(where: { $0.id == id }) else { return fail("找不到分类") }
        next.settings.managedCategories![index].icon = icon
        return commit(next)
    }

    func deleteManagedCategory(id: String) -> Bool {
        var next = normalizedCategories(in: data)
        guard let index = next.settings.managedCategories?.firstIndex(where: { $0.id == id }) else { return fail("找不到分类") }
        let category = next.settings.managedCategories![index]
        guard !category.isSystem else { return fail("系统一级分类可改名和排序，但不能删除") }
        guard !(next.settings.managedCategories ?? []).contains(where: { $0.parentID == id && !$0.isArchived }) else {
            return fail("请先处理该分类下的二级分类")
        }
        guard managedCategoryUsageCount(category) == 0 else {
            return fail("该分类仍有关联内容，请先修改关联内容的分类")
        }
        next.settings.managedCategories![index].isArchived = true
        guard commit(next) else { return false }
        NativeHaptics.success()
        return true
    }

    func reorderManagedCategories(module: ManagedCategoryModule, parentID: String?, orderedIDs: [String]) {
        var next = normalizedCategories(in: data)
        for (order, id) in orderedIDs.enumerated() {
            guard let index = next.settings.managedCategories?.firstIndex(where: {
                $0.id == id && $0.module == module && $0.parentID == parentID
            }) else { continue }
            next.settings.managedCategories![index].sortOrder = order
        }
        if commit(next) { NativeHaptics.selection() }
    }

    func petInventory(for productID: String, in backup: HomeBackup? = nil) -> Double {
        let source = backup ?? data
        return max(0, source.petInventoryTransactions
            .filter { $0.productID == productID }
            .reduce(0) { $0 + $1.quantityChange })
    }

    func petTransactions(for productID: String) -> [PetInventoryTransaction] {
        data.petInventoryTransactions.filter { $0.productID == productID }
            .sorted { $0.occurrenceDate == $1.occurrenceDate ? $0.createdAt > $1.createdAt : $0.occurrenceDate > $1.occurrenceDate }
    }

    func latestProductReview(for productID: String) -> PetProductReview? {
        data.petProductReviews.filter { $0.productID == productID }
            .max { $0.reviewDate == $1.reviewDate ? $0.createdAt < $1.createdAt : $0.reviewDate < $1.reviewDate }
    }

    func latestPalatabilityReviews(for productID: String) -> [PetPalatabilityReview] {
        Dictionary(grouping: data.petPalatabilityReviews.filter { $0.productID == productID }, by: \.petID)
            .values.compactMap { reviews in
                reviews.max { $0.reviewDate == $1.reviewDate ? $0.createdAt < $1.createdAt : $0.reviewDate < $1.reviewDate }
            }
            .sorted { $0.petNameSnapshot < $1.petNameSnapshot }
    }

    var litterPrediction: LitterPrediction? {
        guard let state = data.litterBoxState else { return nil }
        return LitterPredictionService.evaluate(state: state, operations: data.litterOperations)
    }

    func upsertPet(_ pet: PetProfile) {
        var next = data
        if let index = next.pets.firstIndex(where: { $0.id == pet.id }) {
            next.pets[index] = pet
        } else {
            next.pets.append(pet)
        }
        commit(next)
    }

    func deletePet(id: String) {
        var next = data
        guard let index = next.pets.firstIndex(where: { $0.id == id }) else { return }
        next.pets[index].isDeleted = true
        next.pets[index].updatedAt = Date().timeIntervalSince1970
        commit(next)
    }

    func addPetEventCategory(name: String) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return fail("分类名称不能为空") }
        guard !activePetEventCategories.contains(where: { $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }) else {
            return fail("分类名称不能重复")
        }
        var next = data
        next.petEventCategories.append(PetEventCategory(
            id: UUID().uuidString,
            name: cleanName,
            createdAt: Date().timeIntervalSince1970,
            isDeleted: false
        ))
        return commit(next)
    }

    func renamePetEventCategory(id: String, name: String) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return fail("分类名称不能为空") }
        guard !activePetEventCategories.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }) else {
            return fail("分类名称不能重复")
        }
        var next = data
        guard let index = next.petEventCategories.firstIndex(where: { $0.id == id }) else { return false }
        next.petEventCategories[index].name = cleanName
        return commit(next)
    }

    func deletePetEventCategory(id: String) {
        var next = data
        guard let index = next.petEventCategories.firstIndex(where: { $0.id == id }) else { return }
        next.petEventCategories[index].isDeleted = true
        commit(next)
    }

    func saveManualPetEvent(
        id: String? = nil,
        name: String,
        categoryID: String,
        petIDs: [String],
        occurrenceDate: String,
        note: String?,
        imageReferences: [String] = []
    ) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return fail("事项名称不能为空") }
        guard LitterPredictionService.parse(occurrenceDate) != nil else { return fail("发生日期无效") }
        guard let category = activePetEventCategories.first(where: { $0.id == categoryID }) else {
            return fail("请选择有效的事项分类")
        }
        let selectedPets = activePets.filter { petIDs.contains($0.id) }
        let now = Date().timeIntervalSince1970
        var next = data

        if let id, let index = next.petEvents.firstIndex(where: { $0.id == id }) {
            guard next.petEvents[index].litterOperationID == nil else {
                return fail("猫砂操作事项必须通过关联操作统一修改")
            }
            next.petEvents[index].name = cleanName
            next.petEvents[index].categoryID = category.id
            next.petEvents[index].categoryNameSnapshot = category.name
            next.petEvents[index].petIDs = selectedPets.map(\.id)
            next.petEvents[index].petNameSnapshots = selectedPets.map(\.name)
            next.petEvents[index].occurrenceDate = occurrenceDate
            next.petEvents[index].note = note?.trimmingCharacters(in: .whitespacesAndNewlines)
            next.petEvents[index].imageReferences = imageReferences
            next.petEvents[index].updatedAt = now
        } else {
            next.petEvents.append(PetEvent(
                id: UUID().uuidString,
                name: cleanName,
                categoryID: category.id,
                categoryNameSnapshot: category.name,
                petIDs: selectedPets.map(\.id),
                petNameSnapshots: selectedPets.map(\.name),
                occurrenceDate: occurrenceDate,
                note: note?.trimmingCharacters(in: .whitespacesAndNewlines),
                imageReferences: imageReferences,
                source: .manual,
                litterOperationID: nil,
                createdAt: now,
                updatedAt: now
            ))
        }
        guard commit(next) else { return false }
        NativeHaptics.success()
        return true
    }

    func deletePetEvent(id: String) -> Bool {
        guard let event = data.petEvents.first(where: { $0.id == id }) else { return false }
        guard event.litterOperationID == nil else {
            return fail("该事项关联猫砂库存操作，不能单独删除")
        }
        var next = data
        next.petEvents.removeAll { $0.id == id }
        return commit(next)
    }

    func setPetDateGroup(_ date: String, collapsed: Bool) {
        var next = data
        var groups = next.settings.petEventCollapsedDateGroups ?? [:]
        groups[date] = collapsed
        next.settings.petEventCollapsedDateGroups = groups
        commit(next)
    }

    func upsertPetItem(_ item: PetItem, openingTotalPrice: Double? = nil) {
        var next = data
        if let index = next.petItems.firstIndex(where: { $0.id == item.id }) {
            var saved = item
            saved.quantity = petInventory(for: item.id, in: next)
            saved.updatedAt = Date().timeIntervalSince1970
            next.petItems[index] = saved
        } else {
            var saved = item
            let openingQuantity = max(item.quantity, 0)
            let now = Date().timeIntervalSince1970
            saved.quantity = openingQuantity
            saved.createdAt = saved.createdAt ?? now
            saved.updatedAt = now
            next.petItems.append(saved)
            if openingQuantity > 0 {
                next.petInventoryTransactions.append(PetInventoryTransaction(
                    id: UUID().uuidString, productID: item.id, type: .inbound,
                    quantityChange: openingQuantity, quantityBefore: 0, quantityAfter: openingQuantity,
                    unit: item.unit, occurrenceDate: LitterPredictionService.format(Date()), reason: "初始库存",
                    source: .manual, linkedOperationID: nil, totalPrice: openingTotalPrice,
                    unitPrice: openingTotalPrice.map { $0 / openingQuantity },
                    purchaseChannel: nil, expirationDate: item.expirationDate, note: nil,
                    createdAt: now, updatedAt: now
                ))
            }
        }
        commit(next)
    }

    func deletePetItem(id: String) {
        var next = data
        guard let index = next.petItems.firstIndex(where: { $0.id == id }) else { return }
        next.petItems[index].isArchived = true
        next.petItems[index].updatedAt = Date().timeIntervalSince1970
        commit(next)
    }

    func recordPetInventory(
        productID: String,
        type: PetInventoryTransactionType,
        quantity: Double,
        occurrenceDate: String,
        reason: String,
        totalPrice: Double? = nil,
        purchaseChannel: String? = nil,
        expirationDate: String? = nil,
        note: String? = nil
    ) -> Bool {
        guard quantity > 0 else { return fail("数量必须大于 0") }
        guard LitterPredictionService.parse(occurrenceDate) != nil else { return fail("日期无效") }
        var next = data
        guard let index = next.petItems.firstIndex(where: { $0.id == productID && !$0.isArchived }) else { return fail("找不到该宠物物品") }
        let before = petInventory(for: productID, in: next)
        let change = type == .outbound ? -quantity : quantity
        let after = before + change
        guard after >= 0 else { return fail("出库数量不能超过当前库存") }
        let now = Date().timeIntervalSince1970
        next.petInventoryTransactions.append(PetInventoryTransaction(
            id: UUID().uuidString, productID: productID, type: type, quantityChange: change,
            quantityBefore: before, quantityAfter: after, unit: next.petItems[index].unit,
            occurrenceDate: occurrenceDate, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines),
            source: .manual, linkedOperationID: nil, totalPrice: totalPrice,
            unitPrice: totalPrice.map { $0 / quantity }, purchaseChannel: purchaseChannel?.nilIfBlank,
            expirationDate: expirationDate, note: note?.nilIfBlank, createdAt: now, updatedAt: now
        ))
        next.petItems[index].quantity = after
        next.petItems[index].updatedAt = now
        guard commit(next) else { return false }
        NativeHaptics.success()
        return true
    }

    func adjustPetInventory(productID: String, target: Double, occurrenceDate: String, reason: String?) -> Bool {
        guard target >= 0 else { return fail("库存不能小于 0") }
        var next = data
        guard let index = next.petItems.firstIndex(where: { $0.id == productID && !$0.isArchived }) else { return fail("找不到该宠物物品") }
        let before = petInventory(for: productID, in: next)
        let change = target - before
        guard change != 0 else { return fail("调整后的库存没有变化") }
        let now = Date().timeIntervalSince1970
        next.petInventoryTransactions.append(PetInventoryTransaction(
            id: UUID().uuidString, productID: productID, type: .adjustment, quantityChange: change,
            quantityBefore: before, quantityAfter: target, unit: next.petItems[index].unit,
            occurrenceDate: occurrenceDate, reason: reason?.nilIfBlank ?? "手动修正",
            source: .manual, linkedOperationID: nil, totalPrice: nil, unitPrice: nil,
            purchaseChannel: nil, expirationDate: nil, note: nil, createdAt: now, updatedAt: now
        ))
        next.petItems[index].quantity = target
        next.petItems[index].updatedAt = now
        guard commit(next) else { return false }
        NativeHaptics.success()
        return true
    }

    func addPetProductReview(productID: String, date: String, scores: [String: Int], text: String) -> Bool {
        guard !scores.isEmpty, scores.values.allSatisfy({ (1...5).contains($0) }) else { return fail("评分必须为 1 到 5 的整数") }
        let now = Date().timeIntervalSince1970
        var next = data
        let repurchase = scores["回购意愿"] ?? Int((Double(scores.values.reduce(0, +)) / Double(scores.count)).rounded())
        next.petProductReviews.append(PetProductReview(id: UUID().uuidString, productID: productID, reviewDate: date, repurchaseLevel: repurchase, reviewText: text.trimmingCharacters(in: .whitespacesAndNewlines), createdAt: now, updatedAt: now, dimensionScores: scores))
        guard commit(next) else { return false }
        NativeHaptics.success()
        return true
    }

    func petProductRating(productID: String) -> PetRatingSummary? {
        let reviews = data.petProductReviews.filter { $0.productID == productID }
        guard !reviews.isEmpty else { return nil }
        var valuesByDimension: [String: [Int]] = [:]
        reviews.forEach { review in
            review.resolvedDimensionScores.forEach { key, value in valuesByDimension[key, default: []].append(value) }
        }
        let averages = valuesByDimension.mapValues { values in
            Double(values.reduce(0, +)) / Double(values.count)
        }
        return PetRatingSummary(
            overall: reviews.map(\.overallScore).reduce(0, +) / Double(reviews.count),
            count: reviews.count,
            dimensionAverages: averages
        )
    }

    func addPetPalatabilityReview(productID: String, petID: String, date: String, preference: String, note: String?) -> Bool {
        guard let pet = data.pets.first(where: { $0.id == petID }) else { return fail("请选择宠物") }
        let now = Date().timeIntervalSince1970
        var next = data
        next.petPalatabilityReviews.append(PetPalatabilityReview(id: UUID().uuidString, productID: productID, petID: pet.id, petNameSnapshot: pet.name, reviewDate: date, preference: preference, note: note?.nilIfBlank, createdAt: now, updatedAt: now))
        guard commit(next) else { return false }
        NativeHaptics.success()
        return true
    }

    func initializeLitter(amount: Double, occurrenceDate: String) -> Bool {
        guard data.litterBoxState == nil else { return fail("猫砂余量已经初始化") }
        guard amount > 0 else { return fail("请输入大于 0 的猫砂余量") }
        guard LitterPredictionService.parse(occurrenceDate) != nil else { return fail("发生日期无效") }
        let now = Date().timeIntervalSince1970
        let operation = LitterOperation(
            id: UUID().uuidString,
            type: .initialize,
            occurrenceDate: occurrenceDate,
            allocations: [],
            totalBaseAmount: amount,
            amountBeforeOperation: 0,
            amountAfterOperation: amount,
            linkedEventID: nil,
            createdAt: now,
            updatedAt: now
        )
        var next = data
        next.litterBoxState = LitterBoxState(
            id: UUID().uuidString,
            initializedAt: occurrenceDate,
            baseAmount: amount,
            estimatedCurrentAmount: amount,
            baseUnit: "kg",
            lastOperationDate: occurrenceDate,
            averageDailyUsage: nil,
            thresholdRatio: 0.4,
            updatedAt: now
        )
        next.litterOperations.append(operation)
        guard commit(next) else { return false }
        NativeHaptics.success()
        return true
    }

    func performLitterOperation(
        type: LitterOperationType,
        quantities: [String: Double],
        occurrenceDate: String
    ) -> Bool {
        guard type == .refill || type == .replace else { return fail("猫砂操作类型无效") }
        guard let currentState = data.litterBoxState else { return fail("请先初始化猫砂余量") }
        guard LitterPredictionService.parse(occurrenceDate) != nil else { return fail("发生日期无效") }

        var next = data
        var allocations: [LitterAllocation] = []
        for (productID, requestedQuantity) in quantities where requestedQuantity > 0 {
            guard let index = next.petItems.firstIndex(where: { $0.id == productID }) else {
                return fail("找不到选择的猫砂产品")
            }
            let item = next.petItems[index]
            let available = petInventory(for: item.id, in: next)
            guard requestedQuantity <= available else {
                return fail("\(item.name) 的加入量超过当前库存")
            }
            guard let conversion = baseConversion(for: item) else {
                return fail("\(item.name) 的单位无法换算为 kg，请先完善换算信息")
            }
            let baseAmount = requestedQuantity * conversion
            guard baseAmount.isFinite, baseAmount > 0 else { return fail("猫砂加入数量无效") }
            allocations.append(LitterAllocation(
                id: UUID().uuidString,
                productID: item.id,
                productNameSnapshot: item.name,
                quantity: requestedQuantity,
                unit: item.unit,
                baseAmount: baseAmount
            ))
            next.petItems[index].quantity = available - requestedQuantity
        }
        guard !allocations.isEmpty else { return fail("请至少选择一种猫砂并填写数量") }

        let total = allocations.reduce(0) { $0 + $1.baseAmount }
        let currentPrediction = LitterPredictionService.evaluate(
            state: currentState,
            operations: data.litterOperations,
            on: LitterPredictionService.parse(occurrenceDate) ?? Date()
        )
        let amountBefore = max(currentPrediction.currentAmount, 0)
        let amountAfter = type == .replace ? total : amountBefore + total
        let now = Date().timeIntervalSince1970
        let operationID = UUID().uuidString
        let eventID = UUID().uuidString
        let operation = LitterOperation(
            id: operationID,
            type: type,
            occurrenceDate: occurrenceDate,
            allocations: allocations,
            totalBaseAmount: total,
            amountBeforeOperation: amountBefore,
            amountAfterOperation: amountAfter,
            linkedEventID: eventID,
            createdAt: now,
            updatedAt: now
        )
        let event = PetEvent(
            id: eventID,
            name: type == .replace ? "换猫砂" : "补猫砂",
            categoryID: activePetEventCategories.first(where: { $0.name == "猫砂护理" })?.id ?? "",
            categoryNameSnapshot: "猫砂护理",
            petIDs: activePets.map(\.id),
            petNameSnapshots: activePets.map(\.name),
            occurrenceDate: occurrenceDate,
            note: allocations.map { "\($0.productNameSnapshot) \($0.quantity.formatted())\($0.unit)" }.joined(separator: "、"),
            imageReferences: [],
            source: type == .replace ? .litterReplace : .litterRefill,
            litterOperationID: operationID,
            createdAt: now,
            updatedAt: now
        )
        next.litterOperations.append(operation)
        next.petEvents.append(event)
        for allocation in allocations {
            let before = petInventory(for: allocation.productID, in: next)
            let after = before - allocation.quantity
            next.petInventoryTransactions.append(PetInventoryTransaction(
                id: UUID().uuidString,
                productID: allocation.productID,
                type: .outbound,
                quantityChange: -allocation.quantity,
                quantityBefore: before,
                quantityAfter: after,
                unit: allocation.unit,
                occurrenceDate: occurrenceDate,
                reason: type == .replace ? "换猫砂" : "补猫砂",
                source: type == .replace ? .litterReplace : .litterRefill,
                linkedOperationID: operationID,
                totalPrice: nil,
                unitPrice: nil,
                purchaseChannel: nil,
                expirationDate: nil,
                note: nil,
                createdAt: now,
                updatedAt: now
            ))
        }
        if occurrenceDate >= currentState.lastOperationDate {
            next.litterBoxState = LitterBoxState(
                id: currentState.id,
                initializedAt: currentState.initializedAt,
                baseAmount: amountAfter,
                estimatedCurrentAmount: amountAfter,
                baseUnit: "kg",
                lastOperationDate: occurrenceDate,
                averageDailyUsage: nil,
                thresholdRatio: 0.4,
                updatedAt: now
            )
        } else {
            next.litterBoxState = currentState
        }

        if var state = next.litterBoxState {
            let refreshed = LitterPredictionService.evaluate(state: state, operations: next.litterOperations)
            state.estimatedCurrentAmount = refreshed.currentAmount
            state.averageDailyUsage = refreshed.averageDailyUsage
            next.litterBoxState = state
        }
        guard commit(next) else { return false }
        NativeHaptics.success()
        return true
    }

    private func baseConversion(for item: PetItem) -> Double? {
        if let conversion = item.unitConversionToBase, conversion > 0 { return conversion }
        switch item.unit.lowercased() {
        case "kg", "公斤", "千克": return 1
        case "g", "克": return 0.001
        default: return nil
        }
    }

    private func migratedPetInventory(_ backup: HomeBackup) -> HomeBackup {
        var next = backup
        let now = Date().timeIntervalSince1970
        for index in next.petItems.indices {
            let item = next.petItems[index]
            if next.petInventoryTransactions.contains(where: { $0.productID == item.id }) {
                next.petItems[index].quantity = petInventory(for: item.id, in: next)
                continue
            }

            var running = 0.0
            for purchase in item.purchaseHistory ?? [] where purchase.quantity > 0 {
                let unitPrice = purchase.quantity > 0 ? purchase.price / purchase.quantity : nil
                next.petInventoryTransactions.append(PetInventoryTransaction(
                    id: "legacy-purchase-\(item.id)-\(purchase.id)", productID: item.id, type: .inbound,
                    quantityChange: purchase.quantity, quantityBefore: running, quantityAfter: running + purchase.quantity,
                    unit: item.unit, occurrenceDate: purchase.date, reason: "旧版购买记录迁移", source: .migration,
                    linkedOperationID: nil, totalPrice: purchase.price, unitPrice: unitPrice,
                    purchaseChannel: purchase.channel, expirationDate: nil, note: nil,
                    createdAt: now, updatedAt: now
                ))
                running += purchase.quantity
            }
            let difference = max(item.quantity, 0) - running
            if difference != 0 {
                next.petInventoryTransactions.append(PetInventoryTransaction(
                    id: "legacy-balance-\(item.id)", productID: item.id, type: .adjustment,
                    quantityChange: difference, quantityBefore: running, quantityAfter: max(item.quantity, 0),
                    unit: item.unit, occurrenceDate: LitterPredictionService.format(Date()), reason: "旧版期初库存迁移",
                    source: .migration, linkedOperationID: nil, totalPrice: nil, unitPrice: nil,
                    purchaseChannel: nil, expirationDate: nil, note: "用于保持迁移前库存不变",
                    createdAt: now, updatedAt: now
                ))
            }
            next.petItems[index].primaryCategory = item.primaryCategory ?? (item.type.contains("食品") ? "宠物食品" : "宠物用品")
            next.petItems[index].secondaryCategory = item.secondaryCategory ?? inferredSecondaryCategory(for: item)
            next.petItems[index].createdAt = item.createdAt ?? now
            next.petItems[index].updatedAt = item.updatedAt ?? now
        }

        if next.petPalatabilityReviews.isEmpty {
            for item in next.petItems {
                for feedback in item.feedback ?? [] {
                    let pet = next.pets.first { $0.name == feedback.cat }
                    next.petPalatabilityReviews.append(PetPalatabilityReview(
                        id: "legacy-feedback-\(item.id)-\(feedback.id)", productID: item.id,
                        petID: pet?.id ?? "legacy-\(feedback.cat)", petNameSnapshot: feedback.cat,
                        reviewDate: feedback.date, preference: feedback.preference, note: feedback.note,
                        createdAt: now, updatedAt: now
                    ))
                }
            }
        }
        return next
    }

    private func inferredSecondaryCategory(for item: PetItem) -> String {
        let value = "\(item.type) \(item.name)".lowercased()
        if value.contains("猫砂") { return "猫砂" }
        if value.contains("猫粮") { return "猫粮" }
        if value.contains("主食罐") { return "主食罐" }
        if value.contains("零食罐") { return "零食罐" }
        if value.contains("冻干") { return "冻干" }
        if value.contains("汤罐") { return "汤罐" }
        return item.type.contains("食品") ? "其他食品" : "其他用品"
    }

    private func normalizedCategories(in backup: HomeBackup) -> HomeBackup {
        var next = backup
        var categories = next.settings.managedCategories ?? defaultManagedCategories(for: next)

        let petRoots = categories.filter { $0.module == .pet && $0.parentID == nil }
        let foodRoot = petRoots.first { $0.capabilityKey == "petFood" }
        let supplyRoot = petRoots.first { $0.capabilityKey == "petSupply" }
        for item in next.petItems where !item.isArchived {
            let primaryName = item.resolvedPrimaryCategory
            let capability = primaryName.contains("食品") ? "petFood" : "petSupply"
            guard let root = capability == "petFood" ? foodRoot : supplyRoot else { continue }
            let secondaryName = item.resolvedSecondaryCategory
            if !categories.contains(where: {
                $0.module == .pet && $0.parentID == root.id && !$0.isArchived
                    && $0.name.caseInsensitiveCompare(secondaryName) == .orderedSame
            }) {
                let order = categories.filter { $0.module == .pet && $0.parentID == root.id }.count
                categories.append(ManagedCategory(
                    id: "pet-imported-\(UUID().uuidString)", module: .pet, parentID: root.id,
                    name: secondaryName, icon: "tag.fill", sortOrder: order,
                    isSystem: false, capabilityKey: nil, isArchived: false
                ))
            }
        }
        next.settings.managedCategories = categories
        return next
    }

    private func defaultManagedCategories(for backup: HomeBackup) -> [ManagedCategory] {
        func unique(_ names: [String]) -> [String] {
            var seen = Set<String>()
            return names.filter { !$0.isEmpty && seen.insert($0).inserted }
        }
        let petFoodID = "pet-root-food"
        let petSupplyID = "pet-root-supply"
        var values: [ManagedCategory] = [
            ManagedCategory(id: petFoodID, module: .pet, parentID: nil, name: "宠物食品", icon: "takeoutbag.and.cup.and.straw.fill", sortOrder: 0, isSystem: true, capabilityKey: "petFood", isArchived: false),
            ManagedCategory(id: petSupplyID, module: .pet, parentID: nil, name: "宠物用品", icon: "shippingbox.fill", sortOrder: 1, isSystem: true, capabilityKey: "petSupply", isArchived: false)
        ]
        for (index, name) in ["猫粮", "主食罐", "冻干", "零食罐", "汤罐", "其他食品"].enumerated() {
            values.append(ManagedCategory(id: "pet-food-\(index)", module: .pet, parentID: petFoodID, name: name, icon: "takeoutbag.and.cup.and.straw.fill", sortOrder: index, isSystem: false, capabilityKey: nil, isArchived: false))
        }
        for (index, name) in ["猫砂", "除臭用品", "清洁用品", "其他用品"].enumerated() {
            values.append(ManagedCategory(id: "pet-supply-\(index)", module: .pet, parentID: petSupplyID, name: name, icon: "shippingbox.fill", sortOrder: index, isSystem: false, capabilityKey: nil, isArchived: false))
        }

        let foodNames = unique((backup.settings.foodCategoryOrder ?? []) + (backup.settings.foodCategories ?? []).map(\.name) + backup.foods.map(\.category))
        for (index, name) in (foodNames.isEmpty ? ["蔬菜", "水果", "肉类", "乳制品", "包装食品", "其他"] : foodNames).enumerated() {
            values.append(ManagedCategory(id: "food-\(index)", module: .food, parentID: nil, name: name, icon: "refrigerator.fill", sortOrder: index, isSystem: false, capabilityKey: nil, isArchived: false))
        }
        let recipeNames = unique((backup.settings.recipeCollections ?? []) + backup.recipes.compactMap(\.collection))
        for (index, name) in (recipeNames.isEmpty ? ["收藏", "家常菜", "减脂餐", "想尝试"] : recipeNames).enumerated() {
            values.append(ManagedCategory(id: "recipe-\(index)", module: .recipe, parentID: nil, name: name, icon: "list.bullet.clipboard.fill", sortOrder: index, isSystem: false, capabilityKey: nil, isArchived: false))
        }
        return values
    }

    private func defaultManagedBrands(for backup: HomeBackup) -> [ManagedBrand] {
        let now = Date().timeIntervalSince1970
        let defaults = ["Orijen", "皇家", "渴望", "爱肯拿", "巅峰", "K9 Natural", "Instinct", "Nulo", "Wellness"]
        let existingPet = backup.petItems.map(\.brand)
        let existingFood = backup.foods.map(\.brand)
        var names: [String] = []
        for name in defaults + existingPet + existingFood {
            let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanName.isEmpty, !names.contains(where: { $0.caseInsensitiveCompare(cleanName) == .orderedSame }) else { continue }
            names.append(cleanName)
        }
        return names.enumerated().map { index, name in
            var modules: [ManagedCategoryModule] = []
            if defaults.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame })
                || existingPet.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { modules.append(.pet) }
            if existingFood.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { modules.append(.food) }
            return ManagedBrand(id: "brand-default-\(index)", name: name, modules: modules.isEmpty ? [.pet] : modules, isArchived: false, createdAt: now, updatedAt: now)
        }
    }

    private func defaultCategoryIcon(_ module: ManagedCategoryModule) -> String {
        switch module {
        case .pet: "tag.fill"
        case .food: "refrigerator.fill"
        case .recipe: "list.bullet.clipboard.fill"
        }
    }

    private func managedCategoryUsageCount(_ category: ManagedCategory) -> Int {
        switch category.module {
        case .pet:
            if category.parentID == nil {
                return activePetItems.filter { $0.resolvedPrimaryCategory == category.name }.count
            }
            return activePetItems.filter { $0.resolvedSecondaryCategory == category.name }.count
        case .food:
            return data.foods.filter { $0.category == category.name }.count
        case .recipe:
            return data.recipes.filter { $0.collection == category.name }.count
        }
    }

    @discardableResult
    private func fail(_ message: String) -> Bool {
        lastError = message
        NativeHaptics.error()
        return false
    }

    @discardableResult
    private func commit(_ next: HomeBackup) -> Bool {
        do {
            try encoder.encode(next).write(to: fileURL, options: .atomic)
            data = next
            return true
        } catch {
            lastError = "本机数据保存失败：\(error.localizedDescription)"
            NativeHaptics.error()
            return false
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
