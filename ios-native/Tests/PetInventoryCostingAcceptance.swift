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
        try deletingPricedInboundRepricesHistoryAndExpense()
        try deletingOutboundRestoresStockAndRepricesLaterOutbounds()
        try deletingAdjustmentReplaysOrRejectsAtomically()
        try deletingLastTransactionResetsCachedInventory()
        try deletingMigratedReceiptRemovesLegacySourceRecord()
        try deletingEarlyInboundWithInvalidHistoryIsAtomic()
        try linkedLitterTransactionsCannotBeDeleted()
        try updatingTransactionPreservesHiddenFields()
        try transactionEditorAndDetailEntryContracts()
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

    private static func deletingPricedInboundRepricesHistoryAndExpense() throws {
        let inboundA = transaction("a", .inbound, 1, "2026-01-01", 1, total: 10)
        let inboundB = transaction("b", .inbound, 1, "2026-01-02", 2, total: 30)
        let outbound = transaction("out", .outbound, -1, "2026-01-03", 3, total: 20)
        let source = backup(
            transactions: [inboundA, inboundB, outbound],
            activities: [
                activity(inboundA),
                activity(inboundB, deterministic: false),
                activity(outbound),
                ActivityItem(
                    id: "unrelated-activity", text: "other inbound", time: "2026年1月2日", type: "pet",
                    targetId: "product", action: "入库", quantity: 99, unit: "袋", totalPrice: 990, occurredAt: 2.2
                )
            ],
            quantity: 1,
            price: 30
        )

        let result = try PetInventoryHistoryMutation.delete(transactionID: "b", from: source, now: 99)
        let replayedOutbound = result.backup.petInventoryTransactions.first { $0.id == "out" }!
        expectClose(result.backup.petItems.first?.quantity, 0, "stock after deleting the priced inbound")
        expectClose(result.backup.petItems.first?.price, 10, "cached latest inbound unit price")
        expectClose(replayedOutbound.quantityBefore, 1, "outbound stock snapshot before")
        expectClose(replayedOutbound.quantityAfter, 0, "outbound stock snapshot after")
        expectClose(replayedOutbound.totalPrice, 10, "outbound cost after deleting an inbound")
        expectClose(
            PetInventoryCosting.weightedAverageInboundUnitPrice(result.backup.petInventoryTransactions.map(costEvent)),
            10,
            "price history after deleting an inbound"
        )
        let monthlyExpense = result.backup.petInventoryTransactions
            .filter { $0.type == .outbound }
            .compactMap(\.recordedOutboundTotalPrice)
            .reduce(0, +)
        expectClose(monthlyExpense, 10, "monthly expense after deleting an inbound")
        expect(!result.backup.activities.contains { $0.id == "legacy-b" }, "legacy non-deterministic inbound activity is removed")
        expect(result.backup.activities.contains { $0.id == "unrelated-activity" }, "nearby unrelated activity is never removed")
        expectClose(result.backup.activities.first { $0.id == "pet-inventory-out" }?.totalPrice, 10, "outbound activity is synchronized")
    }

    private static func deletingOutboundRestoresStockAndRepricesLaterOutbounds() throws {
        let inbound = transaction("in", .inbound, 2, "2026-01-01", 1, total: 20)
        let deletedOutbound = transaction("out-a", .outbound, -1, "2026-01-02", 2, total: 10)
        let remainingOutbound = transaction("out-b", .outbound, -1, "2026-01-03", 3, total: 10)
        let source = backup(
            transactions: [inbound, deletedOutbound, remainingOutbound],
            activities: [activity(inbound), activity(deletedOutbound), activity(remainingOutbound)],
            quantity: 0,
            price: 10
        )

        let result = try PetInventoryHistoryMutation.delete(transactionID: "out-a", from: source, now: 99)
        let replayedOutbound = result.backup.petInventoryTransactions.first { $0.id == "out-b" }!
        expectClose(result.backup.petItems.first?.quantity, 1, "stock restored by deleting an outbound")
        expectClose(replayedOutbound.quantityBefore, 2, "remaining outbound stock before")
        expectClose(replayedOutbound.quantityAfter, 1, "remaining outbound stock after")
        expectClose(replayedOutbound.totalPrice, 10, "remaining outbound average cost")
        expect(!result.backup.activities.contains { $0.id == "pet-inventory-out-a" }, "deleted outbound activity is removed")
    }

    private static func deletingAdjustmentReplaysOrRejectsAtomically() throws {
        let inbound = transaction("adjust-in", .inbound, 3, "2026-01-01", 1, total: 30)
        var downwardAdjustment = transaction("adjust-down", .adjustment, -1, "2026-01-02", 2)
        downwardAdjustment.quantityBefore = 3
        downwardAdjustment.quantityAfter = 2
        let outbound = transaction("adjust-out", .outbound, -1, "2026-01-03", 3, total: 10)
        let validSource = backup(
            transactions: [inbound, downwardAdjustment, outbound],
            activities: [activity(inbound), activity(downwardAdjustment), activity(outbound)],
            quantity: 1,
            price: 10
        )

        let replayed = try PetInventoryHistoryMutation.delete(transactionID: "adjust-down", from: validSource, now: 99)
        let remainingOutbound = replayed.backup.petInventoryTransactions.first { $0.id == "adjust-out" }!
        expectClose(replayed.backup.petItems.first?.quantity, 2, "deleting a downward adjustment restores stock")
        expectClose(remainingOutbound.quantityBefore, 3, "outbound snapshot replays after adjustment deletion")
        expectClose(remainingOutbound.quantityAfter, 2, "outbound ending stock replays after adjustment deletion")
        expectClose(remainingOutbound.totalPrice, 10, "outbound cost replays after adjustment deletion")

        let oneInbound = transaction("adjust-invalid-in", .inbound, 1, "2026-02-01", 1, total: 10)
        var upwardAdjustment = transaction("adjust-up", .adjustment, 1, "2026-02-02", 2)
        upwardAdjustment.quantityBefore = 1
        upwardAdjustment.quantityAfter = 2
        let dependentOutbound = transaction("adjust-invalid-out", .outbound, -2, "2026-02-03", 3, total: 20)
        let invalidSource = backup(
            transactions: [oneInbound, upwardAdjustment, dependentOutbound],
            activities: [activity(oneInbound), activity(upwardAdjustment), activity(dependentOutbound)],
            quantity: 0,
            price: 10
        )
        var rejected = false
        do {
            _ = try PetInventoryHistoryMutation.delete(transactionID: "adjust-up", from: invalidSource, now: 99)
        } catch let error as PetInventoryCosting.InvalidHistory {
            rejected = true
            expect(error.occurrenceDate == "2026-02-03", "unsafe adjustment deletion reports the dependent outflow date")
        }
        expect(rejected, "adjustment deletion is rejected when it would make a later outbound impossible")
        expect(invalidSource.petInventoryTransactions == [oneInbound, upwardAdjustment, dependentOutbound], "rejected adjustment deletion preserves transactions")
        expect(invalidSource.activities == [activity(oneInbound), activity(upwardAdjustment), activity(dependentOutbound)], "rejected adjustment deletion preserves activities")
    }

    private static func deletingLastTransactionResetsCachedInventory() throws {
        let last = transaction("last", .inbound, 5, "2026-01-01", 1, total: 50)
        let source = backup(transactions: [last], activities: [activity(last)], quantity: 5, price: 10, legacyPrice: 99)

        let result = try PetInventoryHistoryMutation.delete(transactionID: "last", from: source, now: 99)
        expect(result.backup.petInventoryTransactions.isEmpty, "last transaction is removed")
        expectClose(result.backup.petItems.first?.quantity, 0, "empty history resets cached stock")
        expect(result.backup.petItems.first?.price == nil, "empty history resets cached price")
        expect(!result.backup.activities.contains { $0.id == "pet-inventory-last" }, "last transaction activity is removed")
    }

    private static func deletingMigratedReceiptRemovesLegacySourceRecord() throws {
        let purchase = PetPurchaseRecord(
            id: "receipt", date: "2026-01-01", quantity: 1, unit: "袋", price: 10, channel: "legacy"
        )
        let migrated = transaction(
            "legacy-purchase-product-receipt", .inbound, 1, "2026-01-01", 1,
            total: 10, source: .migration
        )
        var source = backup(transactions: [migrated], activities: [activity(migrated)], quantity: 1, price: 10)
        source.petItems[0].purchaseHistory = [purchase]
        source.petItems[0].replenishmentHistory = [purchase]

        let result = try PetInventoryHistoryMutation.delete(transactionID: migrated.id, from: source, now: 99)
        expect(result.backup.petInventoryTransactions.isEmpty, "migrated receipt transaction is removed")
        expect(result.backup.petItems[0].purchaseHistory?.isEmpty == true, "legacy purchase history cannot recreate the deleted receipt")
        expect(result.backup.petItems[0].replenishmentHistory?.isEmpty == true, "mirrored legacy replenishment history cannot recreate the deleted receipt")
        expectClose(result.backup.petItems[0].quantity, 0, "deleting the migrated receipt resets stock")
        expect(result.backup.petItems[0].price == nil, "deleting the migrated receipt clears the price cache")
    }

    private static func deletingEarlyInboundWithInvalidHistoryIsAtomic() throws {
        let inbound = transaction("early", .inbound, 1, "2026-01-01", 1, total: 10)
        let outbound = transaction("later-out", .outbound, -1, "2026-01-02", 2, total: 10)
        let source = backup(
            transactions: [inbound, outbound],
            activities: [activity(inbound), activity(outbound)],
            quantity: 0,
            price: 10
        )
        var rejected = false
        do {
            _ = try PetInventoryHistoryMutation.delete(transactionID: "early", from: source, now: 99)
        } catch let error as PetInventoryCosting.InvalidHistory {
            rejected = true
            expect(error.occurrenceDate == "2026-01-02", "invalid deletion reports the failing historical date")
            expectClose(error.availableQuantity, 0, "invalid deletion stock available")
            expectClose(error.requestedQuantity, 1, "invalid deletion stock required")
        }
        expect(rejected, "early inbound deletion is rejected when a later outflow becomes impossible")
        expect(source.petInventoryTransactions == [inbound, outbound], "rejected deletion preserves the source transactions")
        expect(source.activities == [activity(inbound), activity(outbound)], "rejected deletion preserves the source activities")
        expectClose(source.petItems.first?.quantity, 0, "rejected deletion preserves cached quantity")
        expectClose(source.petItems.first?.price, 10, "rejected deletion preserves cached price")
    }

    private static func linkedLitterTransactionsCannotBeDeleted() throws {
        var source = backup(
            transactions: [transaction("litter", .outbound, -1, "2026-01-01", 1, source: .litterReplace, linkedOperationID: "operation")],
            activities: []
        )
        source.litterOperations = [LitterOperation(
            id: "operation", type: .replace, occurrenceDate: "2026-01-01",
            allocations: [LitterAllocation(id: "allocation", productID: "product", productNameSnapshot: "猫砂", quantity: 1, unit: "袋", baseAmount: 1)],
            totalBaseAmount: 1, amountBeforeOperation: 1, amountAfterOperation: 0,
            linkedEventID: "event", createdAt: 1, updatedAt: 1
        )]
        source.petEvents = [PetEvent(
            id: "event", name: "更换猫砂", categoryID: "care", categoryNameSnapshot: "护理",
            petIDs: [], petNameSnapshots: [], occurrenceDate: "2026-01-01", note: nil,
            imageReferences: [], source: .litterReplace, litterOperationID: "operation", createdAt: 1, updatedAt: 1
        )]
        let original = source
        var rejected = false
        do {
            _ = try PetInventoryHistoryMutation.delete(transactionID: "litter", from: source, now: 99)
        } catch let error as PetInventoryHistoryMutation.Failure {
            if case .litterOperationMustBeChangedAsAGroup = error { rejected = true }
        }
        expect(rejected, "linked litter inventory transactions cannot be deleted individually")
        expect(source == original, "rejected litter deletion leaves the operation, event, and inventory unchanged")
    }

    private static func updatingTransactionPreservesHiddenFields() throws {
        var original = transaction("hidden", .inbound, 2, "2026-01-01", 1, total: 20, source: .migration)
        original.reason = "legacy reason"
        original.purchaseChannel = "legacy channel"
        original.note = "old note"
        let source = backup(transactions: [original], activities: [activity(original)], quantity: 2, price: 10)

        let updated = try PetInventoryHistoryMutation.update(
            transactionID: "hidden", quantity: 2, occurrenceDate: "2026-01-01",
            totalPrice: 40, note: "new note", now: 99, in: source
        )
        let record = updated.petInventoryTransactions.first!
        expect(record.reason == "legacy reason", "hidden reason is preserved")
        expect(record.source == .migration, "hidden source is preserved")
        expect(record.purchaseChannel == "legacy channel", "hidden purchase channel is preserved")
        expect(record.note == "new note", "note changes in the visible row")
        expectClose(record.recordedInboundUnitPrice, 20, "updated inbound unit price")
    }

    private static func transactionEditorAndDetailEntryContracts() throws {
        let inventorySource = try String(contentsOfFile: "HomeOSNative/Views/PetInventoryViews.swift", encoding: .utf8)
        let detailSource = try String(contentsOfFile: "HomeOSNative/Views/PetItemViews.swift", encoding: .utf8)
        guard let rows = sourceSlice(inventorySource, from: "enum PetInventoryTransactionDetailRow", to: "    var id:"),
              let editor = sourceSlice(inventorySource, from: "struct PetInventoryTransactionEditorView", to: "struct PetProductReviewEditorView"),
              let detail = sourceSlice(detailSource, from: "struct PetItemDetailView", to: "private func productHeroCard"),
              let transactionCard = sourceSlice(detailSource, from: "private func transactionCard", to: "private func priceCard") else {
            fatalError("pet inventory presentation source sections are missing")
        }
        let expectedRows = ["case time", "case quantity", "case totalPrice", "case unitPrice", "case note"]
        let declaredRows = rows.components(separatedBy: .newlines).compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("case ") ? trimmed : nil
        }
        expect(declaredRows == expectedRows, "transaction detail has exactly the five requested rows in order")
        let rowPositions = expectedRows.compactMap { rows.range(of: $0)?.lowerBound }
        expect(rowPositions.count == 5 && rowPositions == rowPositions.sorted(), "transaction detail uses the requested row order")
        expect(editor.contains("PetInventoryTransactionDetailRow.allCases"), "all five rows share one card")
        expect(!editor.contains("Form {"), "transaction editor avoids the multi-section form")
        expect(!editor.contains("Section("), "transaction editor has no repeated edit sections")
        expect(editor.contains("DatePicker(\"时间\""), "time edits in place")
        expect(editor.contains("TextField(\"数量\""), "quantity edits in place")
        expect(editor.contains("TextField(\"未记录\""), "optional inbound total price edits in place")
        expect(editor.contains("calculatedUnitPrice"), "unit price is derived live and read-only")
        expect(editor.contains("TextField(\"未填写\", text: $note"), "note edits in place and supports empty display")
        expect(editor.contains("value.isEmpty ? \"未填写\" : value"), "empty note displays the requested placeholder")
        expect(editor.contains("删除这条记录") && editor.contains("confirmationDialog"), "full-record deletion is separately confirmed")
        expect(editor.contains("isLitterReadOnly") && editor.contains("disabled(true)"), "linked litter deletion is disabled with an explanation")
        expect(editor.contains("transaction.type != .adjustment"), "adjustments stay read-only while deletion remains separately available")
        expect(!editor.contains("更多信息") && !editor.contains("购买渠道") && !editor.contains("来源"), "hidden transaction fields are not displayed")
        let ordering = ["productReviewCard", "palatabilityCard", "priceCard(item)", "transactionCard(item)"]
            .compactMap { detail.range(of: $0)?.lowerBound }
        expect(ordering.count == 4 && ordering == ordering.sorted(), "transaction entry follows evaluations and price history")
        expect(transactionCard.contains("共 \\(allRecords.count) 条"), "detail entry displays the transaction count")
        expect(transactionCard.contains("allRecords.first"), "detail entry shows at most one recent record")
        expect(transactionCard.contains("查看全部") && transactionCard.contains("暂无库存流水"), "detail entry offers all records and a clear empty state")
        expect(!transactionCard.contains("prefix(5)"), "detail does not expand five inventory rows")
    }

    private static func sourceSlice(_ source: String, from start: String, to end: String) -> String? {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else { return nil }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    private static func transaction(
        _ id: String,
        _ type: PetInventoryTransactionType,
        _ quantityChange: Double,
        _ occurrenceDate: String,
        _ createdAt: Double,
        totalPrice: Double? = nil,
        source: PetInventorySource = .manual,
        linkedOperationID: String? = nil
    ) -> PetInventoryTransaction {
        PetInventoryTransaction(
            id: id, productID: "product", type: type, quantityChange: quantityChange,
            quantityBefore: 0, quantityAfter: type == .adjustment ? abs(quantityChange) : 0,
            unit: "袋", occurrenceDate: occurrenceDate, reason: "reason \(id)", source: source,
            linkedOperationID: linkedOperationID, totalPrice: totalPrice,
            unitPrice: totalPrice.map { $0 / abs(quantityChange) }, purchaseChannel: "channel \(id)",
            expirationDate: nil, note: nil, createdAt: createdAt, updatedAt: createdAt
        )
    }

    private static func activity(_ transaction: PetInventoryTransaction, deterministic: Bool = true) -> ActivityItem {
        let action: String
        switch transaction.type {
        case .inbound: action = "入库"
        case .outbound: action = "出库"
        case .adjustment: action = "修正"
        }
        return ActivityItem(
            id: deterministic ? "pet-inventory-\(transaction.id)" : "legacy-\(transaction.id)",
            text: "\(action) · item", time: chineseDate(transaction.occurrenceDate), type: "pet",
            targetId: transaction.productID, action: action, quantity: abs(transaction.quantityChange),
            unit: transaction.unit, totalPrice: transaction.totalPrice, occurredAt: transaction.createdAt
        )
    }

    private static func backup(
        transactions: [PetInventoryTransaction],
        activities: [ActivityItem],
        quantity: Double = 0,
        price: Double? = nil,
        legacyPrice: Double = 99
    ) -> HomeBackup {
        var result = HomeBackup.empty
        result.petItems = [PetItem(
            id: "product", type: "宠物用品", name: "猫砂", brand: "", model: "", spec: "",
            quantity: quantity, unit: "袋", days: 0, weeklyUsage: nil, lastReplenishedAt: nil,
            purchaseHistory: [PetPurchaseRecord(id: "legacy", date: "2025-12-01", quantity: 1, unit: "袋", price: legacyPrice, channel: "legacy")],
            replenishmentHistory: nil, feedback: nil, price: price, cat: "", preference: "", image: nil,
            unitConversionToBase: nil
        )]
        result.petInventoryTransactions = transactions
        result.activities = activities
        return result
    }

    private static func chineseDate(_ date: String) -> String {
        let parts = date.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]), let day = Int(parts[2]) else { return date }
        return "\(parts[0])年\(month)月\(day)日"
    }

    private static func costEvent(_ transaction: PetInventoryTransaction) -> PetInventoryCosting.Event {
        let kind: PetInventoryCosting.Kind
        switch transaction.type {
        case .inbound: kind = .inbound
        case .outbound: kind = .outbound
        case .adjustment: kind = .adjustment
        }
        return PetInventoryCosting.Event(
            id: transaction.id, kind: kind, occurrenceDate: transaction.occurrenceDate,
            createdAt: transaction.createdAt, quantityChange: transaction.quantityChange,
            quantityBefore: transaction.quantityBefore, quantityAfter: transaction.quantityAfter,
            totalPrice: transaction.totalPrice, unitPrice: transaction.unitPrice
        )
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
