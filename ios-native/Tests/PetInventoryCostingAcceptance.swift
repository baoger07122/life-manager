import Foundation

@main
struct PetInventoryCostingAcceptance {
    static func main() throws {
        try weightedAverageUsesInboundQuantity()
        try futurePurchaseDoesNotRepriceEarlierOutbound()
        try unpricedInboundKeepsCostUnknownUntilEmpty()
        try deletingInboundPriceRepricesLaterOutbounds()
        try positiveStockCorrectionDoesNotInventCost()
        try replayRejectsNegativeHistoricalStock()
        print("Pet inventory moving-average acceptance checks passed.")
    }

    private static func weightedAverageUsesInboundQuantity() throws {
        let replay = try PetInventoryCosting.replay([
            event("one", .inbound, 1, "2026-01-01", 1, total: 10),
            event("nine", .inbound, 9, "2026-01-02", 2, total: 180)
        ])
        expectClose(PetInventoryCosting.weightedAverageInboundUnitPrice(replay.events), 19, "quantity-weighted inbound average")
        expectClose(replay.currentQuantity, 10, "ending stock after two receipts")
    }

    private static func futurePurchaseDoesNotRepriceEarlierOutbound() throws {
        let replay = try PetInventoryCosting.replay([
            event("first", .inbound, 1, "2026-01-01", 1, total: 10),
            event("out", .outbound, -1, "2026-01-02", 2),
            event("future", .inbound, 1, "2026-01-03", 3, total: 100)
        ])
        let out = replay.events.first { $0.id == "out" }!
        expectClose(out.unitPrice, 10, "earlier outbound unit cost")
        expectClose(out.totalPrice, 10, "earlier outbound total cost")
    }

    private static func unpricedInboundKeepsCostUnknownUntilEmpty() throws {
        let replay = try PetInventoryCosting.replay([
            event("priced", .inbound, 1, "2026-01-01", 1, total: 10),
            event("unknown", .inbound, 1, "2026-01-02", 2),
            event("unknown-out", .outbound, -1, "2026-01-03", 3),
            event("empty", .outbound, -1, "2026-01-04", 4),
            event("known-again", .inbound, 1, "2026-01-05", 5, total: 30),
            event("known-out", .outbound, -1, "2026-01-06", 6)
        ])
        expect(replay.events.first { $0.id == "unknown-out" }?.totalPrice == nil, "unpriced receipt must not become free stock")
        expect(replay.events.first { $0.id == "empty" }?.totalPrice == nil, "unknown pool stays unknown until fully depleted")
        expectClose(replay.events.first { $0.id == "known-out" }?.totalPrice, 30, "priced pool restarts after inventory reaches zero")
    }

    private static func deletingInboundPriceRepricesLaterOutbounds() throws {
        let original = [
            event("a", .inbound, 1, "2026-01-01", 1, total: 10),
            event("b", .inbound, 1, "2026-01-02", 2, total: 30),
            event("out", .outbound, -1, "2026-01-03", 3)
        ]
        let before = try PetInventoryCosting.replay(original)
        expectClose(before.events.first { $0.id == "out" }?.totalPrice, 20, "outbound before price removal")
        let expenseBefore = before.events.compactMap {
            PetInventoryCosting.recordedOutboundTotal(quantityChange: $0.quantityChange, totalPrice: $0.totalPrice, unitPrice: $0.unitPrice)
        }.reduce(0, +)
        expectClose(expenseBefore, 20, "monthly expense before price removal")

        var afterRemoval = original
        afterRemoval[1].totalPrice = nil
        afterRemoval[1].unitPrice = nil
        let after = try PetInventoryCosting.replay(afterRemoval)
        expectClose(
            PetInventoryCosting.weightedAverageInboundUnitPrice(after.events),
            10,
            "price history keeps the remaining priced receipt"
        )
        expect(after.events.first { $0.id == "out" }?.totalPrice == nil, "later outbound becomes unpriced after removal")
        let monthlyExpense = after.events.compactMap {
            PetInventoryCosting.recordedOutboundTotal(quantityChange: $0.quantityChange, totalPrice: $0.totalPrice, unitPrice: $0.unitPrice)
        }.reduce(0, +)
        expectClose(monthlyExpense, 0, "unpriced outbound is excluded from expense total")
    }

    private static func positiveStockCorrectionDoesNotInventCost() throws {
        let replay = try PetInventoryCosting.replay([
            event("purchase", .inbound, 1, "2026-01-01", 1, total: 10),
            event("increase", .adjustment, 1, "2026-01-02", 2, target: 2),
            event("out", .outbound, -1, "2026-01-03", 3)
        ])
        expect(replay.events.first { $0.id == "out" }?.totalPrice == nil, "positive adjustment creates unknown-cost inventory")
    }

    private static func replayRejectsNegativeHistoricalStock() throws {
        do {
            _ = try PetInventoryCosting.replay([
                event("out", .outbound, -1, "2026-01-01", 1),
                event("later-in", .inbound, 1, "2026-01-02", 2, total: 10)
            ])
            fatalError("negative historical stock must be rejected")
        } catch is PetInventoryCosting.InvalidHistory {
            // Expected: do not backfill a future receipt into an earlier outbound.
        }
    }

    private static func event(
        _ id: String,
        _ kind: PetInventoryCosting.Kind,
        _ quantityChange: Double,
        _ date: String,
        _ createdAt: Double,
        total: Double? = nil,
        target: Double = 0
    ) -> PetInventoryCosting.Event {
        PetInventoryCosting.Event(
            id: id,
            kind: kind,
            occurrenceDate: date,
            createdAt: createdAt,
            quantityChange: quantityChange,
            quantityBefore: 0,
            quantityAfter: kind == .adjustment ? target : 0,
            totalPrice: total,
            unitPrice: total.map { $0 / abs(quantityChange) }
        )
    }

    private static func expectClose(_ actual: Double?, _ expected: Double, _ label: String) {
        guard let actual, abs(actual - expected) < 0.000_001 else {
            fatalError("\(label): expected \(expected), got \(String(describing: actual))")
        }
    }

    private static func expectClose(_ actual: Double, _ expected: Double, _ label: String) {
        expectClose(Optional(actual), expected, label)
    }

    private static func expect(_ condition: Bool, _ message: String) {
        if !condition { fatalError(message) }
    }
}
