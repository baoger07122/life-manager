import Foundation

extension HomeBackup {
    var hasUserContent: Bool {
        !foods.isEmpty || !recipes.isEmpty || !plans.isEmpty || !petItems.isEmpty
            || !pets.isEmpty || !petEvents.isEmpty || litterBoxState != nil || !activities.isEmpty
    }
}

enum PreviewFixtures {
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
            petItem(id: "preview-pet-food-1", type: "猫粮", name: "渴望六种鱼", brand: "Orijen", spec: "5.4kg", quantity: 2.4, unit: "kg", primary: "宠物食品", secondary: "猫粮", lowStock: 1),
            petItem(id: "preview-pet-food-2", type: "主食罐", name: "巅峰牛肉罐", brand: "ZIWI", spec: "185g", quantity: 12, unit: "罐", primary: "宠物食品", secondary: "主食罐", lowStock: 5),
            petItem(id: "preview-pet-food-3", type: "冻干", name: "冻干鸡胸肉", brand: "领先", spec: "120g", quantity: 3, unit: "袋", primary: "宠物食品", secondary: "冻干", lowStock: 4),
            petItem(id: "preview-pet-supply-1", type: "猫砂", name: "矿砂", brand: "喵洁客", spec: "8kg", quantity: 8, unit: "kg", primary: "宠物用品", secondary: "猫砂", lowStock: 3, conversion: 1)
        ]

        let transactions = petItems.map { item in
            PetInventoryTransaction(
                id: "preview-stock-\(item.id)", productID: item.id, type: .inbound,
                quantityChange: item.quantity, quantityBefore: 0, quantityAfter: item.quantity,
                unit: item.unit, occurrenceDate: day(-5), reason: "预览初始库存", source: .manual,
                linkedOperationID: nil, totalPrice: nil, unitPrice: nil, purchaseChannel: nil,
                expirationDate: nil, note: nil, createdAt: nowValue - 50, updatedAt: nowValue - 50
            )
        }

        let litterOperations = [
            LitterOperation(id: "preview-litter-op-1", type: .replace, occurrenceDate: day(-28), allocations: [], totalBaseAmount: 6, amountBeforeOperation: 0, amountAfterOperation: 6, linkedEventID: nil, createdAt: nowValue - 280, updatedAt: nowValue - 280),
            LitterOperation(id: "preview-litter-op-2", type: .replace, occurrenceDate: day(-14), allocations: [], totalBaseAmount: 6, amountBeforeOperation: 0, amountAfterOperation: 6, linkedEventID: nil, createdAt: nowValue - 140, updatedAt: nowValue - 140)
        ]
        let litterState = LitterBoxState(id: "preview-litter-state", initializedAt: day(-28), baseAmount: 10, estimatedCurrentAmount: 6.4, baseUnit: "kg", lastOperationDate: day(-3), averageDailyUsage: 0.42, thresholdRatio: 0.4, updatedAt: nowValue)

        let eventCategory = PetEventCategory(id: "preview-event-category", name: "日常护理", createdAt: nowValue - 300, isDeleted: false)
        let events = [
            PetEvent(id: "preview-event-1", name: "剪指甲", categoryID: eventCategory.id, categoryNameSnapshot: eventCategory.name, petIDs: [catA.id], petNameSnapshots: [catA.name], occurrenceDate: day(0), note: "前爪已完成", imageReferences: [], source: .manual, litterOperationID: nil, createdAt: nowValue, updatedAt: nowValue),
            PetEvent(id: "preview-event-2", name: "体重记录", categoryID: eventCategory.id, categoryNameSnapshot: eventCategory.name, petIDs: [catB.id], petNameSnapshots: [catB.name], occurrenceDate: day(-1), note: "4.8kg", imageReferences: [], source: .manual, litterOperationID: nil, createdAt: nowValue - 80, updatedAt: nowValue - 80)
        ]

        let foods = [
            FoodItem(id: "preview-food-1", name: "鸡蛋", quantity: 12, unit: "个", expiry: day(5), productionDate: day(-2), location: "冷藏区", category: "包装食品", tags: ["早餐"], brand: "", spec: "12枚", price: 18, icon: "🥚", thumb: nil, quick: true, quickAddedAt: nowValue, quickReducePresets: [1, 2], purchases: nil, priceHistory: nil),
            FoodItem(id: "preview-food-2", name: "牛奶", quantity: 1, unit: "盒", expiry: day(2), productionDate: day(-3), location: "冷藏区", category: "乳制品", tags: ["早餐"], brand: "", spec: "950ml", price: 16, icon: "🥛", thumb: nil, quick: true, quickAddedAt: nowValue - 20, quickReducePresets: [1], purchases: nil, priceHistory: nil),
            FoodItem(id: "preview-food-3", name: "生菜", quantity: 1, unit: "颗", expiry: day(3), productionDate: nil, location: "冷藏区", category: "蔬菜", tags: [], brand: "", spec: "", price: 5, icon: "🥬", thumb: nil, quick: true, quickAddedAt: nowValue - 40, quickReducePresets: [1], purchases: nil, priceHistory: nil)
        ]
        let recipe = RecipeItem(id: "preview-recipe-1", name: "番茄炒蛋", main: ["番茄", "鸡蛋"], ingredients: ["盐", "食用油"], steps: "鸡蛋炒熟后加入番茄翻炒。", stepImage: nil, favorite: true, collection: "家常菜", link: "", image: "")

        return HomeBackup(
            foods: foods,
            recipes: [recipe],
            plans: [MealPlan(id: "preview-plan-1", date: day(0), meal: "晚餐", recipeId: recipe.id, note: nil)],
            prepChecks: [], petItems: petItems, pets: [catA, catB], petEventCategories: [eventCategory],
            petEvents: events, litterBoxState: litterState, litterOperations: litterOperations,
            petInventoryTransactions: transactions, petProductReviews: [], petPalatabilityReviews: [],
            activities: [ActivityItem(id: "preview-activity-1", text: "牛奶即将到期", time: "今天", type: "food", targetId: "preview-food-2")],
            settings: .standard
        )
    }

    private static func petItem(
        id: String, type: String, name: String, brand: String, spec: String,
        quantity: Double, unit: String, primary: String, secondary: String,
        lowStock: Double, conversion: Double? = nil
    ) -> PetItem {
        PetItem(
            id: id, type: type, name: name, brand: brand, model: "", spec: spec,
            quantity: quantity, unit: unit, days: 0, weeklyUsage: nil,
            lastReplenishedAt: nil, purchaseHistory: nil, replenishmentHistory: nil,
            feedback: nil, price: nil, cat: "", preference: "", image: nil,
            unitConversionToBase: conversion, primaryCategory: primary,
            secondaryCategory: secondary, variant: nil, lowStockThreshold: lowStock,
            notes: "预览测试数据", isArchived: false,
            foodRole: primary == "宠物食品" ? "主食" : nil,
            expirationDate: nil, litterKind: secondary == "猫砂" ? "矿砂" : nil,
            createdAt: Date().timeIntervalSince1970, updatedAt: Date().timeIntervalSince1970
        )
    }
}
