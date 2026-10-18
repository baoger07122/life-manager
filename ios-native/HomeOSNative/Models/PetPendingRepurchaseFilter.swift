import Foundation

enum PetPendingRepurchaseFilter {
    static func items(
        from source: [PetItem],
        primaryCategory: String,
        secondaryCategory: String,
        inventoryForItem: (String) -> Double
    ) -> [PetItem] {
        source.filter { item in
            let itemPrimaryCategory = item.primaryCategory
                ?? (item.type.contains("食品") ? "宠物食品" : "宠物用品")
            let itemSecondaryCategory = item.secondaryCategory ?? item.type
            let willRepurchase = item.willRepurchase ?? !item.isArchived
            return !item.isArchived
                && willRepurchase
                && inventoryForItem(item.id) <= 0
                && itemPrimaryCategory == primaryCategory
                && itemSecondaryCategory == secondaryCategory
        }
    }
}
