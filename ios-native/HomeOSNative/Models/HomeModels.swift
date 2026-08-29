import Foundation

struct PurchaseRecord: Codable, Identifiable, Hashable {
    var id: String
    var date: String
    var quantity: Double
    var unit: String
    var price: Double
    var expiry: String?
}

struct FoodItem: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var quantity: Double
    var unit: String
    var expiry: String
    var productionDate: String?
    var location: String
    var category: String
    var tags: [String]?
    var brand: String
    var spec: String
    var price: Double
    var icon: String
    var thumb: String?
    var quick: Bool
    var quickAddedAt: Double?
    var quickReducePresets: [Int]?
    var purchases: [PurchaseRecord]?
    var priceHistory: [PurchaseRecord]?
}

struct RecipeItem: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var main: [String]
    var ingredients: [String]
    var steps: String
    var stepImage: String?
    var favorite: Bool
    var collection: String?
    var link: String
    var image: String
}

struct MealPlan: Codable, Identifiable, Hashable {
    var id: String
    var date: String
    var meal: String
    var recipeId: String
    var note: String?
}

struct PrepItem: Codable, Hashable {
    var name: String
    var status: String
}

struct PrepCheck: Codable, Identifiable, Hashable {
    var id: String
    var planId: String
    var items: [PrepItem]
}

struct PetPurchaseRecord: Codable, Identifiable, Hashable {
    var id: String
    var date: String
    var quantity: Double
    var unit: String
    var price: Double
    var channel: String?
}

struct PetFeedback: Codable, Identifiable, Hashable {
    var id: String
    var date: String
    var cat: String
    var preference: String
    var note: String?
}

struct PetItem: Codable, Identifiable, Hashable {
    var id: String
    var type: String
    var name: String
    var brand: String
    var model: String
    var spec: String
    var quantity: Double
    var unit: String
    var days: Int
    var weeklyUsage: Double?
    var lastReplenishedAt: String?
    var purchaseHistory: [PetPurchaseRecord]?
    var replenishmentHistory: [PetPurchaseRecord]?
    var feedback: [PetFeedback]?
    var price: Double?
    var cat: String
    var preference: String
    var image: String?
    var unitConversionToBase: Double?
    var primaryCategory: String? = nil
    var secondaryCategory: String? = nil
    var variant: String? = nil
    var lowStockThreshold: Double? = nil
    var notes: String? = nil
    var isArchived: Bool = false
    var foodRole: String? = nil
    var expirationDate: String? = nil
    var litterKind: String? = nil
    var createdAt: Double? = nil
    var updatedAt: Double? = nil
}

extension PetItem {
    enum CodingKeys: String, CodingKey {
        case id, type, name, brand, model, spec, quantity, unit, days, weeklyUsage
        case lastReplenishedAt, purchaseHistory, replenishmentHistory, feedback, price
        case cat, preference, image, unitConversionToBase
        case primaryCategory, secondaryCategory, variant, lowStockThreshold, notes, isArchived
        case foodRole, expirationDate, litterKind, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        type = try values.decodeIfPresent(String.self, forKey: .type) ?? "其他用品"
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "未命名用品"
        brand = try values.decodeIfPresent(String.self, forKey: .brand) ?? ""
        model = try values.decodeIfPresent(String.self, forKey: .model) ?? ""
        spec = try values.decodeIfPresent(String.self, forKey: .spec) ?? ""
        quantity = try values.decodeIfPresent(Double.self, forKey: .quantity) ?? 0
        unit = try values.decodeIfPresent(String.self, forKey: .unit) ?? "件"
        days = try values.decodeIfPresent(Int.self, forKey: .days) ?? 0
        weeklyUsage = try values.decodeIfPresent(Double.self, forKey: .weeklyUsage)
        lastReplenishedAt = try values.decodeIfPresent(String.self, forKey: .lastReplenishedAt)
        purchaseHistory = try values.decodeIfPresent([PetPurchaseRecord].self, forKey: .purchaseHistory)
        replenishmentHistory = try values.decodeIfPresent([PetPurchaseRecord].self, forKey: .replenishmentHistory)
        feedback = try values.decodeIfPresent([PetFeedback].self, forKey: .feedback)
        price = try values.decodeIfPresent(Double.self, forKey: .price)
        cat = try values.decodeIfPresent(String.self, forKey: .cat) ?? ""
        preference = try values.decodeIfPresent(String.self, forKey: .preference) ?? ""
        image = try values.decodeIfPresent(String.self, forKey: .image)
        unitConversionToBase = try values.decodeIfPresent(Double.self, forKey: .unitConversionToBase)
        primaryCategory = try values.decodeIfPresent(String.self, forKey: .primaryCategory)
        secondaryCategory = try values.decodeIfPresent(String.self, forKey: .secondaryCategory)
        variant = try values.decodeIfPresent(String.self, forKey: .variant)
        lowStockThreshold = try values.decodeIfPresent(Double.self, forKey: .lowStockThreshold)
        notes = try values.decodeIfPresent(String.self, forKey: .notes)
        isArchived = try values.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        foodRole = try values.decodeIfPresent(String.self, forKey: .foodRole)
        expirationDate = try values.decodeIfPresent(String.self, forKey: .expirationDate)
        litterKind = try values.decodeIfPresent(String.self, forKey: .litterKind)
        createdAt = try values.decodeIfPresent(Double.self, forKey: .createdAt)
        updatedAt = try values.decodeIfPresent(Double.self, forKey: .updatedAt)
    }
}

enum PetInventoryTransactionType: String, Codable, Hashable {
    case inbound
    case outbound
    case adjustment
}

enum PetInventorySource: String, Codable, Hashable {
    case manual
    case migration
    case litterRefill
    case litterReplace
}

struct PetInventoryTransaction: Codable, Identifiable, Hashable {
    var id: String
    var productID: String
    var type: PetInventoryTransactionType
    var quantityChange: Double
    var quantityBefore: Double
    var quantityAfter: Double
    var unit: String
    var occurrenceDate: String
    var reason: String
    var source: PetInventorySource
    var linkedOperationID: String?
    var totalPrice: Double?
    var unitPrice: Double?
    var purchaseChannel: String?
    var expirationDate: String?
    var note: String?
    var createdAt: Double
    var updatedAt: Double
}

struct PetProductReview: Codable, Identifiable, Hashable {
    var id: String
    var productID: String
    var reviewDate: String
    var repurchaseLevel: Int
    var reviewText: String
    var createdAt: Double
    var updatedAt: Double
    var dimensionScores: [String: Int]? = nil
}

extension PetProductReview {
    var resolvedDimensionScores: [String: Int] {
        guard let dimensionScores, !dimensionScores.isEmpty else { return ["回购意愿": repurchaseLevel] }
        return dimensionScores
    }

    var overallScore: Double {
        let values = resolvedDimensionScores.values
        guard !values.isEmpty else { return Double(repurchaseLevel) }
        return Double(values.reduce(0, +)) / Double(values.count)
    }
}

struct PetRatingSummary: Hashable {
    var overall: Double
    var count: Int
    var dimensionAverages: [String: Double]
}

struct PetPalatabilityReview: Codable, Identifiable, Hashable {
    var id: String
    var productID: String
    var petID: String
    var petNameSnapshot: String
    var reviewDate: String
    var preference: String
    var note: String?
    var createdAt: Double
    var updatedAt: Double
}

struct PetProfile: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var image: String?
    var breed: String
    var birthDate: String
    var isDeleted: Bool
    var createdAt: Double
    var updatedAt: Double
}

struct PetEventCategory: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var createdAt: Double
    var isDeleted: Bool
}

enum PetEventSource: String, Codable, Hashable {
    case manual
    case litterRefill
    case litterReplace
}

struct PetEvent: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var categoryID: String
    var categoryNameSnapshot: String
    var petIDs: [String]
    var petNameSnapshots: [String]
    var occurrenceDate: String
    var note: String?
    var imageReferences: [String]
    var source: PetEventSource
    var litterOperationID: String?
    var createdAt: Double
    var updatedAt: Double
}

struct LitterAllocation: Codable, Identifiable, Hashable {
    var id: String
    var productID: String
    var productNameSnapshot: String
    var quantity: Double
    var unit: String
    var baseAmount: Double
}

enum LitterOperationType: String, Codable, Hashable {
    case initialize
    case refill
    case replace
}

struct LitterOperation: Codable, Identifiable, Hashable {
    var id: String
    var type: LitterOperationType
    var occurrenceDate: String
    var allocations: [LitterAllocation]
    var totalBaseAmount: Double
    var amountBeforeOperation: Double
    var amountAfterOperation: Double
    var linkedEventID: String?
    var createdAt: Double
    var updatedAt: Double
}

struct LitterBoxState: Codable, Identifiable, Hashable {
    var id: String
    var initializedAt: String
    var baseAmount: Double
    var estimatedCurrentAmount: Double
    var baseUnit: String
    var lastOperationDate: String
    var averageDailyUsage: Double?
    var thresholdRatio: Double
    var updatedAt: Double
}

struct ActivityItem: Codable, Identifiable, Hashable {
    var id: String
    var text: String
    var time: String
    var type: String?
    var targetId: String?
}

struct CategoryDefinition: Codable, Hashable {
    var name: String
    var icon: String
}

enum ManagedCategoryModule: String, Codable, CaseIterable, Identifiable {
    case pet
    case food
    case recipe

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pet: "宠物"
        case .food: "食品"
        case .recipe: "菜谱"
        }
    }
}

struct ManagedCategory: Codable, Identifiable, Hashable {
    var id: String
    var module: ManagedCategoryModule
    var parentID: String?
    var name: String
    var icon: String
    var sortOrder: Int
    var isSystem: Bool
    var capabilityKey: String?
    var isArchived: Bool
}

struct ManagedBrand: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var modules: [ManagedCategoryModule]
    var isArchived: Bool
    var createdAt: Double
    var updatedAt: Double
}

struct ExpiryThresholds: Codable, Hashable {
    var milk: Int
    var eggs: Int
    var frozenMeat: Int
    var `default`: Int

    static let standard = ExpiryThresholds(milk: 7, eggs: 14, frozenMeat: 30, default: 15)
}

enum HomePlanLimit: Codable, Hashable {
    case all
    case count(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .count(value)
        } else {
            self = .all
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .all: try container.encode("all")
        case .count(let value): try container.encode(value)
        }
    }
}

struct HomeSettings: Codable, Hashable {
    var threshold: Int
    var locations: [String]
    var view: String
    var quickFoodOrder: [String]?
    var quickAmountPresets: [Int]?
    var homePlanLimit: HomePlanLimit?
    var topCategories: [String]?
    var topCategoryOrder: [String]?
    var foodCategories: [CategoryDefinition]?
    var foodCategoryOrder: [String]?
    var foodTags: [String]?
    var foodTagOrder: [String]?
    var recipeCollections: [String]?
    var expiryReminderEnabled: Bool?
    var expiryThresholds: ExpiryThresholds?
    var petEventCollapsedDateGroups: [String: Bool]?
    var managedCategories: [ManagedCategory]?
    var managedBrands: [ManagedBrand]?

    static let standard = HomeSettings(
        threshold: 15,
        locations: ["冷藏区", "冷冻区", "常温区"],
        view: "list",
        quickFoodOrder: [],
        quickAmountPresets: [1, 2],
        homePlanLimit: .all,
        topCategories: [],
        topCategoryOrder: [],
        foodCategories: ["蔬菜", "水果", "肉类", "乳制品", "包装食品", "其他"].map { CategoryDefinition(name: $0, icon: "•") },
        foodCategoryOrder: ["蔬菜", "水果", "肉类", "乳制品", "包装食品", "其他"],
        foodTags: [],
        foodTagOrder: [],
        recipeCollections: ["收藏", "家常菜", "减脂餐", "想尝试"],
        expiryReminderEnabled: true,
        expiryThresholds: .standard,
        petEventCollapsedDateGroups: [:],
        managedCategories: nil,
        managedBrands: nil
    )
}

struct HomeBackup: Codable, Hashable {
    var foods: [FoodItem]
    var recipes: [RecipeItem]
    var plans: [MealPlan]
    var prepChecks: [PrepCheck]
    var petItems: [PetItem]
    var pets: [PetProfile]
    var petEventCategories: [PetEventCategory]
    var petEvents: [PetEvent]
    var litterBoxState: LitterBoxState?
    var litterOperations: [LitterOperation]
    var petInventoryTransactions: [PetInventoryTransaction]
    var petProductReviews: [PetProductReview]
    var petPalatabilityReviews: [PetPalatabilityReview]
    var activities: [ActivityItem]
    var settings: HomeSettings

    static let empty = HomeBackup(
        foods: [], recipes: [], plans: [], prepChecks: [], petItems: [], pets: [], petEventCategories: [], petEvents: [], litterBoxState: nil, litterOperations: [], petInventoryTransactions: [], petProductReviews: [], petPalatabilityReviews: [], activities: [], settings: .standard
    )

    enum CodingKeys: String, CodingKey {
        case foods, recipes, plans, prepChecks, petItems, pets, petEventCategories, petEvents, litterBoxState, litterOperations, petInventoryTransactions, petProductReviews, petPalatabilityReviews, activities, settings
    }

    init(foods: [FoodItem], recipes: [RecipeItem], plans: [MealPlan], prepChecks: [PrepCheck], petItems: [PetItem], pets: [PetProfile] = [], petEventCategories: [PetEventCategory] = [], petEvents: [PetEvent] = [], litterBoxState: LitterBoxState? = nil, litterOperations: [LitterOperation] = [], petInventoryTransactions: [PetInventoryTransaction] = [], petProductReviews: [PetProductReview] = [], petPalatabilityReviews: [PetPalatabilityReview] = [], activities: [ActivityItem], settings: HomeSettings) {
        self.foods = foods
        self.recipes = recipes
        self.plans = plans
        self.prepChecks = prepChecks
        self.petItems = petItems
        self.pets = pets
        self.petEventCategories = petEventCategories
        self.petEvents = petEvents
        self.litterBoxState = litterBoxState
        self.litterOperations = litterOperations
        self.petInventoryTransactions = petInventoryTransactions
        self.petProductReviews = petProductReviews
        self.petPalatabilityReviews = petPalatabilityReviews
        self.activities = activities
        self.settings = settings
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        foods = try values.decodeIfPresent([FoodItem].self, forKey: .foods) ?? []
        recipes = try values.decodeIfPresent([RecipeItem].self, forKey: .recipes) ?? []
        plans = try values.decodeIfPresent([MealPlan].self, forKey: .plans) ?? []
        prepChecks = try values.decodeIfPresent([PrepCheck].self, forKey: .prepChecks) ?? []
        petItems = try values.decodeIfPresent([PetItem].self, forKey: .petItems) ?? []
        pets = try values.decodeIfPresent([PetProfile].self, forKey: .pets) ?? []
        petEventCategories = try values.decodeIfPresent([PetEventCategory].self, forKey: .petEventCategories) ?? []
        petEvents = try values.decodeIfPresent([PetEvent].self, forKey: .petEvents) ?? []
        litterBoxState = try values.decodeIfPresent(LitterBoxState.self, forKey: .litterBoxState)
        litterOperations = try values.decodeIfPresent([LitterOperation].self, forKey: .litterOperations) ?? []
        petInventoryTransactions = try values.decodeIfPresent([PetInventoryTransaction].self, forKey: .petInventoryTransactions) ?? []
        petProductReviews = try values.decodeIfPresent([PetProductReview].self, forKey: .petProductReviews) ?? []
        petPalatabilityReviews = try values.decodeIfPresent([PetPalatabilityReview].self, forKey: .petPalatabilityReviews) ?? []
        activities = try values.decodeIfPresent([ActivityItem].self, forKey: .activities) ?? []
        settings = try values.decodeIfPresent(HomeSettings.self, forKey: .settings) ?? .standard
    }
}
