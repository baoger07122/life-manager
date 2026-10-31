#if DEBUG || PLAYGROUND_PREVIEW
import Foundation

extension HomeBackup {
    var hasUserContent: Bool {
        !foods.isEmpty || !recipes.isEmpty || !plans.isEmpty || !petItems.isEmpty
            || !pets.isEmpty || !petEvents.isEmpty || litterBoxState != nil || !activities.isEmpty
    }
}

enum PreviewFixtures {
    static var expiryBalanceUITest: HomeBackup {
        var backup = homeOS
        let productID = "preview-pet-food-2"
        let sourceBatchID = "preview-stock-\(productID)"
        let now = Date().timeIntervalSince1970
        let effectiveDate = LitterPredictionService.format(Date())
        backup.petInventoryBalanceAllocations = [
            PetInventoryBalanceAllocation(
                id: "preview-expiry-earlier",
                productID: productID,
                sourceBatchID: sourceBatchID,
                sourceAvailableBefore: 12,
                expirationDate: "2027-03-01",
                quantity: 5,
                effectiveDate: effectiveDate,
                createdAt: now + 1
            ),
            PetInventoryBalanceAllocation(
                id: "preview-expiry-later",
                productID: productID,
                sourceBatchID: sourceBatchID,
                sourceAvailableBefore: 7,
                expirationDate: "2027-08-08",
                quantity: 7,
                effectiveDate: effectiveDate,
                createdAt: now + 2
            )
        ]
        return backup
    }

    static var petListUITest: HomeBackup {
        var backup = expiryBalanceUITest
        var longFlavorItem = backup.petItems.first { $0.id == "preview-pet-food-2" }!
        let productID = "preview-pet-food-long-flavor"
        let now = Date().timeIntervalSince1970
        longFlavorItem.id = productID
        longFlavorItem.name = "主食罐"
        longFlavorItem.variant = "鸡肉三文鱼蔓越莓"
        longFlavorItem.quantity = 2
        longFlavorItem.createdAt = now
        longFlavorItem.updatedAt = now
        longFlavorItem.image = nil
        backup.petItems.append(longFlavorItem)
        backup.petInventoryTransactions.append(PetInventoryTransaction(
            id: "preview-long-flavor-inbound",
            productID: productID,
            type: .inbound,
            quantityChange: 2,
            quantityBefore: 0,
            quantityAfter: 2,
            unit: longFlavorItem.unit,
            occurrenceDate: LitterPredictionService.format(Date()),
            reason: "Simulator 行布局预览",
            source: .manual,
            linkedOperationID: nil,
            totalPrice: nil,
            unitPrice: nil,
            purchaseChannel: nil,
            expirationDate: nil,
            note: nil,
            createdAt: now,
            updatedAt: now
        ))
        var largeQuantityItem = backup.petItems.first { $0.id == "preview-pet-food-2" }!
        let largeQuantityProductID = "preview-pet-food-large-quantity"
        largeQuantityItem.id = largeQuantityProductID
        largeQuantityItem.name = "大数量商品"
        largeQuantityItem.variant = nil
        largeQuantityItem.quantity = 123_456
        largeQuantityItem.createdAt = now + 1
        largeQuantityItem.updatedAt = now + 1
        largeQuantityItem.image = nil
        backup.petItems.append(largeQuantityItem)
        backup.petInventoryTransactions.append(PetInventoryTransaction(
            id: "preview-large-quantity-inbound",
            productID: largeQuantityProductID,
            type: .inbound,
            quantityChange: 123_456,
            quantityBefore: 0,
            quantityAfter: 123_456,
            unit: largeQuantityItem.unit,
            occurrenceDate: LitterPredictionService.format(Date()),
            reason: "Simulator 大数量行预览",
            source: .manual,
            linkedOperationID: nil,
            totalPrice: nil,
            unitPrice: nil,
            purchaseChannel: nil,
            expirationDate: nil,
            note: nil,
            createdAt: now + 1,
            updatedAt: now + 1
        ))
        var ratedPricedItem = backup.petItems.first { $0.id == "preview-pet-food-2" }!
        let ratedPricedProductID = "preview-pet-food-rated-priced"
        ratedPricedItem.id = ratedPricedProductID
        ratedPricedItem.name = "加权价试算"
        ratedPricedItem.variant = "原味"
        ratedPricedItem.spec = "85g"
        ratedPricedItem.unit = "盒"
        ratedPricedItem.packageType = "盒"
        ratedPricedItem.quantity = 5
        ratedPricedItem.createdAt = now + 2
        ratedPricedItem.updatedAt = now + 2
        ratedPricedItem.image = nil
        backup.petItems.append(ratedPricedItem)
        backup.petInventoryTransactions.append(contentsOf: [
            PetInventoryTransaction(
                id: "preview-rated-priced-inbound-early", productID: ratedPricedProductID, type: .inbound,
                quantityChange: 2, quantityBefore: 0, quantityAfter: 2, unit: "盒",
                occurrenceDate: LitterPredictionService.format(Date()), reason: "Simulator 有价行预览", source: .manual,
                linkedOperationID: nil, totalPrice: 128, unitPrice: 64,
                purchaseChannel: nil, expirationDate: nil, note: nil, createdAt: now - 20, updatedAt: now - 20
            ),
            PetInventoryTransaction(
                id: "preview-rated-priced-inbound-late", productID: ratedPricedProductID, type: .inbound,
                quantityChange: 3, quantityBefore: 2, quantityAfter: 5, unit: "盒",
                occurrenceDate: LitterPredictionService.format(Date()), reason: "Simulator 有价行预览", source: .manual,
                linkedOperationID: nil, totalPrice: 268, unitPrice: 268 / 3,
                purchaseChannel: nil, expirationDate: nil, note: nil, createdAt: now - 10, updatedAt: now - 10
            )
        ])
        backup.petProductReviews.append(PetProductReview(
            id: "preview-rated-priced-review", productID: ratedPricedProductID,
            reviewDate: LitterPredictionService.format(Date()), repurchaseLevel: 5,
            reviewText: "Simulator 有评分行预览。", createdAt: now + 2, updatedAt: now + 2,
            dimensionScores: ["适口性": 5, "品质": 5, "性价比": 4, "回购意愿": 5]
        ))
        return backup
    }

    static var petCategoryValuationUITest: HomeBackup {
        var backup = homeOS
        let now = Date().timeIntervalSince1970
        let occurrenceDate = LitterPredictionService.format(Date())
        let items = [
            petItem(id: "preview-valuation-bag", type: "猫粮", name: "试算小袋", brand: "验收", spec: "85g", quantity: 1, unit: "袋", primary: "宠物食品", secondary: "猫粮", packageType: "袋"),
            petItem(id: "preview-valuation-can", type: "猫粮", name: "试算小罐", brand: "验收", spec: "200g", quantity: 2, unit: "罐", primary: "宠物食品", secondary: "猫粮", packageType: "罐"),
            petItem(id: "preview-valuation-bottle", type: "猫粮", name: "试算大瓶", brand: "验收", spec: "1kg", quantity: 10, unit: "瓶", primary: "宠物食品", secondary: "猫粮", packageType: "瓶"),
            petItem(id: "preview-valuation-unpriced", type: "主食罐", name: "未计价罐头", brand: "验收", spec: "185g", quantity: 3, unit: "罐", primary: "宠物食品", secondary: "主食罐", packageType: "罐")
        ]
        backup.petItems = items
        backup.petInventoryTransactions = [
            PetInventoryTransaction(id: "preview-valuation-stock-bag", productID: "preview-valuation-bag", type: .inbound, quantityChange: 1, quantityBefore: 0, quantityAfter: 1, unit: "袋", occurrenceDate: occurrenceDate, reason: "估值 UI 夹具", source: .manual, linkedOperationID: nil, totalPrice: 0.49, unitPrice: 0.49, purchaseChannel: nil, expirationDate: nil, note: nil, createdAt: now - 3, updatedAt: now - 3),
            PetInventoryTransaction(id: "preview-valuation-stock-can", productID: "preview-valuation-can", type: .inbound, quantityChange: 2, quantityBefore: 0, quantityAfter: 2, unit: "罐", occurrenceDate: occurrenceDate, reason: "估值 UI 夹具", source: .manual, linkedOperationID: nil, totalPrice: 0.98, unitPrice: 0.49, purchaseChannel: nil, expirationDate: nil, note: nil, createdAt: now - 2, updatedAt: now - 2),
            PetInventoryTransaction(id: "preview-valuation-stock-bottle", productID: "preview-valuation-bottle", type: .inbound, quantityChange: 10, quantityBefore: 0, quantityAfter: 10, unit: "瓶", occurrenceDate: occurrenceDate, reason: "估值 UI 夹具", source: .manual, linkedOperationID: nil, totalPrice: 15.20, unitPrice: 1.52, purchaseChannel: nil, expirationDate: nil, note: nil, createdAt: now - 1, updatedAt: now - 1),
            PetInventoryTransaction(id: "preview-valuation-stock-unpriced", productID: "preview-valuation-unpriced", type: .inbound, quantityChange: 3, quantityBefore: 0, quantityAfter: 3, unit: "罐", occurrenceDate: occurrenceDate, reason: "估值 UI 夹具", source: .manual, linkedOperationID: nil, totalPrice: nil, unitPrice: nil, purchaseChannel: nil, expirationDate: nil, note: nil, createdAt: now, updatedAt: now)
        ]
        backup.petInventoryBalanceAllocations = []
        backup.petProductReviews = []
        backup.petPalatabilityReviews = []
        return backup
    }

    static var homeOS: HomeBackup {
        let calendar = Calendar.current
        let now = Date()
        let nowValue = now.timeIntervalSince1970
        func day(_ offset: Int) -> String {
            LitterPredictionService.format(calendar.date(byAdding: .day, value: offset, to: now) ?? now)
        }

        let catA = PetProfile(id: "preview-pet-1", name: "糯米", image: nil, breed: "布偶猫", birthDate: "2022-05-18", isDeleted: false, createdAt: nowValue - 200, updatedAt: nowValue)
        let catB = PetProfile(id: "preview-pet-2", name: "汤圆", image: nil, breed: "英国短毛猫", birthDate: "2023-02-06", isDeleted: false, createdAt: nowValue - 100, updatedAt: nowValue)

        let petItems = [
            petItem(id: "preview-pet-food-1", type: "猫粮", name: "六种鱼猫粮", brand: "Orijen", flavor: "六种鱼味", spec: "80g", quantity: 4, unit: "袋", primary: "宠物食品", secondary: "猫粮", packageType: "袋"),
            petItem(id: "preview-pet-food-2", type: "主食罐", name: "牛肉主食罐", brand: "巅峰", flavor: "牛肉味", spec: "185g", quantity: 12, unit: "罐", primary: "宠物食品", secondary: "主食罐", packageType: "罐"),
            petItem(id: "preview-pet-food-3", type: "冻干", name: "冻干鸡胸肉", brand: "领先", flavor: "原味", spec: "120g", quantity: 3, unit: "袋", primary: "宠物食品", secondary: "冻干", packageType: "袋"),
            petItem(id: "preview-pet-supply-1", type: "猫砂", name: "矿砂", brand: "喵洁客", spec: "8kg", quantity: 1, unit: "袋", primary: "宠物用品", secondary: "猫砂", conversion: 8, packageType: "袋")
        ]

        var transactions = petItems.filter { $0.id != "preview-pet-food-1" }.map { item in
            PetInventoryTransaction(
                id: "preview-stock-\(item.id)", productID: item.id, type: .inbound,
                quantityChange: item.quantity, quantityBefore: 0, quantityAfter: item.quantity,
                unit: item.unit, occurrenceDate: day(-5), reason: "预览初始库存", source: .manual,
                linkedOperationID: nil,
                totalPrice: item.id == "preview-pet-food-1" ? 268 : nil,
                unitPrice: item.id == "preview-pet-food-1" ? 268 / item.quantity : nil,
                purchaseChannel: nil,
                expirationDate: nil, note: nil, createdAt: nowValue - 50, updatedAt: nowValue - 50
            )
        }
        transactions.append(contentsOf: [
            PetInventoryTransaction(
                id: "preview-stock-food-1-current", productID: "preview-pet-food-1", type: .inbound,
                quantityChange: 3, quantityBefore: 2, quantityAfter: 5, unit: "袋",
                occurrenceDate: day(-5), reason: "购买入库", source: .manual,
                linkedOperationID: nil, totalPrice: 268, unitPrice: 268 / 3,
                purchaseChannel: "官方旗舰店", expirationDate: nil, note: nil,
                createdAt: nowValue - 50, updatedAt: nowValue - 50
            ),
            PetInventoryTransaction(
                id: "preview-stock-food-1-earlier", productID: "preview-pet-food-1", type: .inbound,
                quantityChange: 2, quantityBefore: 0, quantityAfter: 2, unit: "袋",
                occurrenceDate: day(-42), reason: "补充库存", source: .manual,
                linkedOperationID: nil, totalPrice: 128, unitPrice: 64,
                purchaseChannel: "官方旗舰店", expirationDate: nil, note: nil,
                createdAt: nowValue - 420, updatedAt: nowValue - 420
            ),
            PetInventoryTransaction(
                id: "preview-stock-food-1-out", productID: "preview-pet-food-1", type: .outbound,
                quantityChange: -1, quantityBefore: 5, quantityAfter: 4, unit: "袋",
                occurrenceDate: day(-1), reason: "日常使用", source: .manual,
                linkedOperationID: nil, totalPrice: nil, unitPrice: nil,
                purchaseChannel: nil, expirationDate: nil, note: nil,
                createdAt: nowValue - 8, updatedAt: nowValue - 8
            )
        ])

        let productReviews = [
            PetProductReview(
                id: "preview-review-1", productID: "preview-pet-food-1", reviewDate: day(-4),
                repurchaseLevel: 5, reviewText: "适口性稳定，会继续回购。",
                createdAt: nowValue - 40, updatedAt: nowValue - 40,
                dimensionScores: ["适口性": 5, "品质": 5, "性价比": 4, "回购意愿": 5]
            ),
            PetProductReview(
                id: "preview-review-2", productID: "preview-pet-food-1", reviewDate: day(-1),
                repurchaseLevel: 5, reviewText: "颗粒和气味都比较稳定。",
                createdAt: nowValue - 10, updatedAt: nowValue - 10,
                dimensionScores: ["适口性": 5, "品质": 4, "性价比": 4, "回购意愿": 5]
            ),
            PetProductReview(
                id: "preview-review-3", productID: "preview-pet-food-2", reviewDate: day(-2),
                repurchaseLevel: 4, reviewText: "开罐方便，接受度不错。",
                createdAt: nowValue - 20, updatedAt: nowValue - 20,
                dimensionScores: ["适口性": 5, "品质": 4, "性价比": 4, "回购意愿": 4]
            )
        ]

        let litterOperations = [
            LitterOperation(id: "preview-litter-op-1", type: .replace, occurrenceDate: day(-28), allocations: [], totalBaseAmount: 6, amountBeforeOperation: 0, amountAfterOperation: 6, linkedEventID: nil, createdAt: nowValue - 280, updatedAt: nowValue - 280),
            LitterOperation(id: "preview-litter-op-2", type: .replace, occurrenceDate: day(-14), allocations: [], totalBaseAmount: 6, amountBeforeOperation: 0, amountAfterOperation: 6, linkedEventID: nil, createdAt: nowValue - 140, updatedAt: nowValue - 140)
        ]
        let litterState = LitterBoxState(id: "preview-litter-state", initializedAt: day(-28), baseAmount: 10, estimatedCurrentAmount: 6.4, baseUnit: "kg", lastOperationDate: day(-3), averageDailyUsage: 0.42, thresholdRatio: 0.4, updatedAt: nowValue)

        let eventCategory = PetEventCategory(id: "preview-event-category", name: "日常护理", createdAt: nowValue - 300, isDeleted: false)
        let events = [
            PetEvent(id: "preview-event-1", name: "剪指甲", categoryID: eventCategory.id, categoryNameSnapshot: eventCategory.name, petIDs: [], petNameSnapshots: [], occurrenceDate: day(0), note: "前爪已完成", imageReferences: [], source: .manual, litterOperationID: nil, createdAt: nowValue, updatedAt: nowValue),
            PetEvent(id: "preview-event-2", name: "清洁饮水机", categoryID: eventCategory.id, categoryNameSnapshot: eventCategory.name, petIDs: [], petNameSnapshots: [], occurrenceDate: day(-1), note: "滤芯和水箱已清洁", imageReferences: [], source: .manual, litterOperationID: nil, createdAt: nowValue - 80, updatedAt: nowValue - 80)
        ]

        let foods = [
            FoodItem(id: "preview-food-1", name: "鲜鸡蛋", quantity: 12, unit: "个", expiry: day(5), productionDate: day(-2), location: "冷藏区", category: "包装食品", tags: ["早餐"], brand: "正大", spec: "12枚", price: 18, icon: "🥚", thumb: nil, quick: true, quickAddedAt: nowValue, quickReducePresets: [1, 2], purchases: nil, priceHistory: nil),
            FoodItem(id: "preview-food-2", name: "鲜牛奶", quantity: 1, unit: "盒", expiry: day(2), productionDate: day(-3), location: "冷藏区", category: "乳制品", tags: ["早餐"], brand: "光明", spec: "950ml", price: 16, icon: "🥛", thumb: nil, quick: true, quickAddedAt: nowValue - 20, quickReducePresets: [1], purchases: nil, priceHistory: nil),
            FoodItem(id: "preview-food-3", name: "生菜", quantity: 1, unit: "颗", expiry: day(3), productionDate: nil, location: "冷藏区", category: "蔬菜", tags: [], brand: "", spec: "", price: 5, icon: "🥬", thumb: nil, quick: true, quickAddedAt: nowValue - 40, quickReducePresets: [1], purchases: nil, priceHistory: nil)
        ]
        let recipe = RecipeItem(id: "preview-recipe-1", name: "番茄炒蛋", main: ["番茄", "鸡蛋"], ingredients: ["盐", "食用油"], steps: "鸡蛋炒熟后加入番茄翻炒。", stepImage: nil, favorite: true, collection: "家常菜", link: "", image: "")

        return HomeBackup(
            foods: foods,
            recipes: [recipe],
            plans: [MealPlan(id: "preview-plan-1", date: day(0), meal: "晚餐", recipeId: recipe.id, note: nil)],
            prepChecks: [], petItems: petItems, pets: [catA, catB], petEventCategories: [eventCategory],
            petEvents: events, litterBoxState: litterState, litterOperations: litterOperations,
            petInventoryTransactions: transactions, petProductReviews: productReviews, petPalatabilityReviews: [],
            activities: [ActivityItem(id: "preview-activity-1", text: "牛奶即将到期", time: "今天", type: "food", targetId: "preview-food-2")],
            settings: .standard
        )
    }

    private static func petItem(
        id: String, type: String, name: String, brand: String, flavor: String? = nil, spec: String,
        quantity: Double, unit: String, primary: String, secondary: String,
        conversion: Double? = nil, packageType: String? = nil
    ) -> PetItem {
        PetItem(
            id: id, type: type, name: name, brand: brand, model: "", spec: spec,
            quantity: quantity, unit: unit, days: 0, weeklyUsage: nil,
            lastReplenishedAt: nil, purchaseHistory: nil, replenishmentHistory: nil,
            feedback: nil, price: nil, cat: "", preference: "", image: nil,
            unitConversionToBase: conversion, primaryCategory: primary,
            secondaryCategory: secondary, variant: flavor, lowStockThreshold: nil,
            notes: "预览测试数据", packageType: packageType, isArchived: false,
            foodRole: nil,
            expirationDate: nil, litterKind: secondary == "猫砂" ? "矿砂" : nil,
            createdAt: Date().timeIntervalSince1970, updatedAt: Date().timeIntervalSince1970
        )
    }
}
#endif
