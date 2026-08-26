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
        expiryThresholds: .standard
    )
}

struct HomeBackup: Codable, Hashable {
    var foods: [FoodItem]
    var recipes: [RecipeItem]
    var plans: [MealPlan]
    var prepChecks: [PrepCheck]
    var petItems: [PetItem]
    var activities: [ActivityItem]
    var settings: HomeSettings

    static let empty = HomeBackup(
        foods: [], recipes: [], plans: [], prepChecks: [], petItems: [], activities: [], settings: .standard
    )

    enum CodingKeys: String, CodingKey {
        case foods, recipes, plans, prepChecks, petItems, activities, settings
    }

    init(foods: [FoodItem], recipes: [RecipeItem], plans: [MealPlan], prepChecks: [PrepCheck], petItems: [PetItem], activities: [ActivityItem], settings: HomeSettings) {
        self.foods = foods
        self.recipes = recipes
        self.plans = plans
        self.prepChecks = prepChecks
        self.petItems = petItems
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
        activities = try values.decodeIfPresent([ActivityItem].self, forKey: .activities) ?? []
        settings = try values.decodeIfPresent(HomeSettings.self, forKey: .settings) ?? .standard
    }
}
