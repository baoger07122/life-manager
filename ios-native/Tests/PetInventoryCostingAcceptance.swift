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
        try pendingRepurchaseFiltering()
        try pendingRepurchaseCategoryContracts()
        try pendingRepurchaseNavigationContracts()
        try palatabilityReviewGrouping()
        try heroAveragePricePresentation()
        try petItemDetailPresentationContracts()
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
              let transactionCard = sourceSlice(detailSource, from: "private func transactionCard", to: "private func priceCard"),
              let selector = sourceSlice(detailSource, from: "private var secondaryAndSortRow", to: "private func selectDefaultSecondary") else {
            fatalError("pet inventory presentation source sections are missing")
        }
        let expectedRows = ["case quantity", "case totalPrice", "case unitPrice", "case note", "case time"]
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
        expect(editor.contains("HomeMetrics.controlHeight"), "transaction rows use the standard control height")
        expect(editor.contains("HomeTypography.body") && !editor.contains(".font(.body)") && !editor.contains(".font(.footnote)"), "transaction fields share the new-item body typography")
        expect(editor.contains("HStack(alignment: .center") && !editor.contains(".padding(.vertical"), "note stays centered without extra vertical row padding")
        expect(editor.contains("case .inbound: return \"入库数量\"") && editor.contains("case .outbound: return \"出库数量\"") && editor.contains("case .adjustment: return \"修正变化\""), "view labels identify stock direction without changing adjustment meaning")
        expect(editor.contains("abs(transaction.quantityChange).formatted()") && editor.contains("transaction.quantityChange >= 0 ? \"增加\" : \"减少\"") && !editor.contains("quantityChange > 0 ? \"+\" : \"\""), "view quantity uses absolute receipt/issue amounts and clear adjustment direction")
        expect(editor.contains("Text(currency2(value))") && editor.contains("Text(\"/\\(item.unit)\")") && editor.contains("HStack(spacing: 4)"), "unit-price amount and unit are separate right-aligned labels")
        expect(editor.contains("DatePicker(\"时间\""), "time edits in place")
        expect(editor.contains("TextField(\"数量\""), "quantity edits in place")
        expect(editor.contains("TextField(\"未记录\""), "optional inbound total price edits in place")
        expect(editor.contains("calculatedUnitPrice"), "unit price is derived live and read-only")
        expect(editor.contains("TextField(\"未填写\", text: $note") && editor.contains(".lineLimit(1...)"), "note has a matching-size placeholder and grows for long text")
        expect(editor.contains(".multilineTextAlignment(.trailing)"), "note aligns with the right-side value column")
        expect(editor.contains("value.isEmpty ? \"未填写\" : value"), "empty note displays the requested placeholder")
        expect(editor.contains("if isEditing && canDeleteTransaction") && editor.contains("删除这条记录") && editor.contains("confirmationDialog"), "full-record deletion is confirmed and appears only in edit mode")
        if let litterNotice = sourceSlice(editor, from: "if isLitterReadOnly {", to: "if isEditing && canDeleteTransaction {") {
            expect(litterNotice.contains("猫砂联动流水只读"), "linked litter records show a short read-only explanation")
            expect(!litterNotice.contains("Button(\"删除这条记录\""), "linked litter records have no disabled delete button")
        } else {
            fatalError("linked litter read-only notice is missing")
        }
        expect(editor.contains("canEnterEditMode") && editor.contains("transaction.type != .adjustment"), "read-only adjustments retain the edit-mode deletion path")
        expect(!editor.contains("更多信息") && !editor.contains("购买渠道") && !editor.contains("来源"), "hidden transaction fields are not displayed")
        expect(selector.contains("HStack(spacing: 8)") && selector.contains(".padding(.horizontal, 2)") && selector.contains(".fixedSize(horizontal: true, vertical: false)"), "secondary categories use the tuned intrinsic spacing")
        expect(!selector.contains(".frame(minWidth: HomeMetrics.minimumTapTarget") && !selector.contains(".padding(.horizontal, 4)"), "secondary selector avoids wide tab insets")
        expect(selector.contains(".frame(width: 44, height: HomeMetrics.minimumTapTarget") && selector.contains("ScrollView(.horizontal"), "sorting stays fixed beside the horizontal selector")
        let ordering = ["productReviewCard", "palatabilityCard", "priceCard(item)", "transactionCard(item)"]
            .compactMap { detail.range(of: $0)?.lowerBound }
        expect(ordering.count == 4 && ordering == ordering.sorted(), "transaction entry follows evaluations and price history")
        expect(transactionCard.contains("共 \\(allRecords.count) 条"), "detail entry displays the transaction count")
        expect(transactionCard.contains("allRecords.first"), "detail entry shows at most one recent record")
        expect(transactionCard.contains("查看全部") && transactionCard.contains("暂无库存流水"), "detail entry offers all records and a clear empty state")
        expect(!transactionCard.contains("prefix(5)"), "detail does not expand five inventory rows")
    }

    private static func pendingRepurchaseCategoryContracts() throws {
        let petItemsSource = try String(contentsOfFile: "HomeOSNative/Views/PetItemViews.swift", encoding: .utf8)
        let storeSource = try String(contentsOfFile: "HomeOSNative/Data/HomeStore.swift", encoding: .utf8)
        let filterSource = try String(contentsOfFile: "HomeOSNative/Models/PetPendingRepurchaseFilter.swift", encoding: .utf8)
        guard let pending = sourceSlice(
            petItemsSource,
            from: "struct PetPendingRepurchaseView: View",
            to: "struct PetNoRepurchaseLibraryView: View"
        ), let categoryRename = sourceSlice(
            storeSource,
            from: "    func renameManagedCategory(id: String, name: String) -> Bool {",
            to: "    func setManagedCategoryIcon(id: String, icon: String) -> Bool {"
        ) else {
            fatalError("pending repurchase presentation or category rename source is missing")
        }

        expect(pending.contains("store.categories(for: .pet)") && pending.contains("store.categories(for: .pet, parentID: $0.id)"), "pending library reuses live managed pet categories")
        expect(pending.contains("ForEach(primaryCategories)") && pending.contains("ForEach(secondaryCategories)") && pending.contains("HomeUnderlineTab"), "pending library presents both category levels with the home selector style")
        expect(pending.contains("capabilityKey == \"petFood\"") && pending.contains("[\"主食罐\"]") && pending.contains("[\"矿砂\"]"), "food and supplies use their requested default subcategories")
        expect(pending.contains("PetPendingRepurchaseFilter.items(") && pending.contains("primaryCategory: selectedPrimary.name") && pending.contains("secondaryCategory: selectedSecondary.name"), "selected primary and secondary categories isolate the pending items")
        expect(filterSource.contains("willRepurchase") && filterSource.contains("inventoryForItem(item.id) <= 0") && filterSource.contains("itemPrimaryCategory == primaryCategory") && filterSource.contains("itemSecondaryCategory == secondaryCategory"), "pending items require zero stock, repurchase intent and both selected categories")
        expect(pending.contains("secondaryID = preferredSecondary?.id ?? \"\"") && pending.contains("onChange(of: primaryID)"), "changing the primary category selects its preferred secondary category")
        expect(pending.contains("onChange(of: secondaryCategories.map(\\.id))") && pending.contains("onChange(of: primaryCategories.map(\\.id))"), "category additions, removal and reordering update the visible selectors")
        expect(pending.contains("selectedSecondary?.name") && pending.contains("category.name"), "empty state and selector labels follow the current managed category names")
        expect(pending.contains("store.setPetItemRepurchase(id: item.id, willRepurchase: false)"), "marking a pending item as not for repurchase removes it from the filtered list")
        expect(pending.contains("NavigationLink") && pending.contains("PetItemDetailView(itemID: item.id)"), "pending items retain their detail navigation")
        expect(pending.contains("PetProductThumbnail(item: item)") && pending.contains("panelDivider") && pending.contains("panelBottomCap") && pending.contains(".listStyle(.plain)"), "pending list reuses the home thumbnail and unified divided card layout")
        expect(!pending.contains("quickManagerRow") && !pending.contains("openEditor") && !pending.contains("新增"), "pending list has no stock quick actions or add-item control")
        expect(categoryRename.contains("primaryCategory = cleanName") && categoryRename.contains("secondaryCategory = cleanName"), "renaming a managed category updates the product category names")
    }

    private static func pendingRepurchaseFiltering() throws {
        let template = backup(transactions: [], activities: []).petItems[0]
        var food = template
        food.id = "food"
        food.type = "主食罐"
        food.primaryCategory = "宠物食品"
        food.secondaryCategory = "主食罐"
        food.willRepurchase = true

        var supplies = template
        supplies.id = "supplies"
        supplies.type = "矿砂"
        supplies.primaryCategory = "宠物用品"
        supplies.secondaryCategory = "矿砂"
        supplies.willRepurchase = true

        var treats = supplies
        treats.id = "treats"
        treats.type = "零食"
        treats.secondaryCategory = "零食"

        let candidates = [food, supplies, treats]
        let stock: [String: Double] = ["food": 0, "supplies": 0, "treats": 0]
        let foodSelection = PetPendingRepurchaseFilter.items(
            from: candidates,
            primaryCategory: "宠物食品",
            secondaryCategory: "主食罐",
            inventoryForItem: { stock[$0, default: 0] }
        )
        expect(foodSelection.map(\.id) == ["food"], "food remains separate from supplies")

        let secondarySelection = PetPendingRepurchaseFilter.items(
            from: candidates,
            primaryCategory: "宠物用品",
            secondaryCategory: "零食",
            inventoryForItem: { stock[$0, default: 0] }
        )
        expect(secondarySelection.map(\.id) == ["treats"], "switching the secondary category selects only its products")

        let emptySelection = PetPendingRepurchaseFilter.items(
            from: candidates,
            primaryCategory: "宠物用品",
            secondaryCategory: "未有商品的分类",
            inventoryForItem: { stock[$0, default: 0] }
        )
        expect(emptySelection.isEmpty, "a category without products remains empty")

        var cancelledRepurchase = food
        cancelledRepurchase.willRepurchase = false
        let noLongerPending = PetPendingRepurchaseFilter.items(
            from: [cancelledRepurchase],
            primaryCategory: "宠物食品",
            secondaryCategory: "主食罐",
            inventoryForItem: { _ in 0 }
        )
        expect(noLongerPending.isEmpty, "turning off repurchase intent removes the product from pending")

        let restocked = PetPendingRepurchaseFilter.items(
            from: [food],
            primaryCategory: "宠物食品",
            secondaryCategory: "主食罐",
            inventoryForItem: { _ in 1 }
        )
        expect(restocked.isEmpty, "restocking removes the product from pending")

        var renamed = food
        renamed.primaryCategory = "宠物主粮"
        renamed.secondaryCategory = "干粮"
        let renamedSelection = PetPendingRepurchaseFilter.items(
            from: [renamed],
            primaryCategory: "宠物主粮",
            secondaryCategory: "干粮",
            inventoryForItem: { _ in 0 }
        )
        expect(renamedSelection.map(\.id) == ["food"], "renamed category names match the updated product category")
    }

    private static func pendingRepurchaseNavigationContracts() throws {
        let source = try String(contentsOfFile: "HomeOSNative/Views/PetItemViews.swift", encoding: .utf8)
        guard let pending = sourceSlice(
            source,
            from: "struct PetPendingRepurchaseView: View",
            to: "struct PetNoRepurchaseLibraryView: View"
        ), let row = sourceSlice(
            pending,
            from: "    private func pendingItemRow(_ item: PetItem) -> some View {",
            to: "    private func specificationAndStock(_ item: PetItem) -> String {"
        ) else {
            fatalError("pending repurchase navigation source is missing")
        }

        expect(pending.contains("@State private var primaryID") && pending.contains("@State private var secondaryID"), "pending category selections are stateful across detail navigation")
        expect(pending.contains(".navigationDestination(item: $detailItemID)") && pending.contains("PetItemDetailView(itemID: itemID)"), "pending rows push product details through a local destination")
        expect(!row.contains("NavigationLink") && !row.contains("simultaneousGesture"), "pending rows avoid link chevrons and competing tap gestures")
        expect(row.contains("Button {") && row.contains("detailItemID = item.id"), "the pending row button opens the tapped product")
        expect(row.components(separatedBy: "NativeHaptics.tap()").count - 1 == 1, "pending row taps emit exactly one haptic")
        expect(row.contains("PetProductThumbnail(item: item)") && row.contains(".padding(.horizontal, 14)") && row.contains(".padding(.vertical, 8)") && row.contains(".frame(maxWidth: .infinity, alignment: .leading)") && row.contains(".contentShape(Rectangle())"), "the full thumbnail, text and padded row area is tappable")
        expect(row.contains(".swipeActions(edge: .trailing, allowsFullSwipe: false)") && row.contains("store.setPetItemRepurchase(id: item.id, willRepurchase: false)"), "the no-repurchase swipe action remains attached to the row")
        expect(pending.contains(".onAppear(perform: synchronizeSelections)") && pending.contains("if !primaryCategories.contains(where: { $0.id == primaryID })"), "returning from detail keeps valid category selections")
    }

    private static func palatabilityReviewGrouping() throws {
        let bling = petProfile("bling", name: "BLING", createdAt: 1)
        let secondPet = petProfile("second", name: "小猫", createdAt: 2)
        let deletedPetReviews = [palatabilityReview(
            "deleted", petID: "deleted-pet", petName: "历史猫", date: "2026-01-04", createdAt: 4,
            preference: "不喜欢"
        )]
        let reviews = [
            palatabilityReview("second-legacy", petID: secondPet.id, petName: secondPet.name, date: "2026-01-02", createdAt: 2, preference: "一般"),
            palatabilityReview("bling-old", petID: bling.id, petName: bling.name, date: "2026-01-01", createdAt: 1, preference: "喜欢"),
            palatabilityReview("bling-new", petID: bling.id, petName: bling.name, date: "2026-01-03", createdAt: 3, score: 3),
            deletedPetReviews[0],
            palatabilityReview("other-product", productID: "other", petID: bling.id, petName: bling.name, date: "2026-01-05", createdAt: 5, score: 1)
        ]

        let groups = PetPalatabilityReviewGrouping.groups(
            productID: "product",
            reviews: reviews,
            activePets: [bling, secondPet]
        )
        expect(groups.map(\.petID) == ["bling", "second", "deleted-pet"], "palatability summaries follow active-pet order, then include deleted-pet history")
        expect(groups[0].petName == "BLING" && groups[0].count == 2, "multiple reviews collapse into one current-pet summary")
        expectClose(groups[0].averageScore, 4, "legacy preference score participates in the per-pet average")
        expect(groups[0].records.map(\.id) == ["bling-new", "bling-old"], "expanded history is ordered newest first")
        expect(groups[1].count == 1, "a single review remains one editable pet entry")
        expectClose(groups[1].averageScore, 3, "legacy neutral preference maps to its resolved score")
        expect(groups[2].petName == "历史猫", "deleted pets retain their recorded name")
        expectClose(groups[2].averageScore, 1, "legacy dislike preference maps to its resolved score")

        var editedReview = reviews.first { $0.id == "bling-new" }!
        editedReview.score = 1
        editedReview.preference = "不喜欢"
        let afterEdit = PetPalatabilityReviewGrouping.groups(
            productID: "product",
            reviews: reviews.map { $0.id == editedReview.id ? editedReview : $0 },
            activePets: [bling, secondPet]
        )
        expectClose(afterEdit[0].averageScore, 3, "editing one review immediately changes that pet's average")

        let singleReviewGroup = PetPalatabilityReviewGrouping.groups(
            productID: "product",
            reviews: [palatabilityReview("only", petID: bling.id, petName: bling.name, date: "2026-01-01", createdAt: 1, score: 5)],
            activePets: [bling]
        )
        expect(singleReviewGroup.count == 1 && singleReviewGroup[0].count == 1, "one review produces exactly one non-aggregated summary")
        expectClose(singleReviewGroup[0].averageScore, 5, "one-review summary shows that review's own score")
    }

    private static func heroAveragePricePresentation() throws {
        expect(PetItemHeroAveragePrice.text(average: nil, unit: "罐") == nil, "hero omits an unavailable inbound average")
        expect(PetItemHeroAveragePrice.text(average: 0, unit: "罐") == nil, "hero never displays a zero placeholder price")
        expect(PetItemHeroAveragePrice.text(average: .infinity, unit: "罐") == nil, "hero omits a non-finite average")
        expect(PetItemHeroAveragePrice.text(average: 4.67, unit: "罐") == "加权均价 ¥4.67/罐", "hero formats a valid weighted average with its unit")
    }

    private static func petItemDetailPresentationContracts() throws {
        let source = try String(contentsOfFile: "HomeOSNative/Views/PetItemViews.swift", encoding: .utf8)
        guard let detail = sourceSlice(
            source,
            from: "struct PetItemDetailView: View",
            to: "private enum PetItemDetailSheet"
        ), let heroLine = sourceSlice(
            detail,
            from: "private func productSpecificationLine(_ item: PetItem) -> some View {",
            to: "    private func isPetFood(_ item: PetItem) -> Bool {"
        ), let palatability = sourceSlice(
            detail,
            from: "private var palatabilityCard: some View {",
            to: "    @ViewBuilder private func detailProductImage"
        ), let priceCard = sourceSlice(
            detail,
            from: "private func priceCard(_ item: PetItem) -> some View {",
            to: "private var productReviewCard: some View {"
        ) else {
            fatalError("pet item detail presentation sections are missing")
        }

        expect(detail.contains("PetPalatabilityReviewGrouping.groups") && detail.contains("store.activePets"), "pet reviews are grouped in current pet-management order")
        expect(palatability.contains("ForEach(groups)") && palatability.contains("DisclosureGroup(isExpanded:") && palatability.contains("ForEach(group.records)"), "each pet has one collapsed summary and can reveal every review")
        expect(palatability.contains("group.count == 1") && palatability.contains("sheet = .palatability(reviewID: review.id)"), "a single review opens its original editor directly")
        expect(palatability.contains("store.petPalatabilityRating(productID: itemID, petID: group.petID)") && palatability.contains("次评价") && palatability.contains("查看 \\(group.count) 条") && palatability.contains("收起"), "multi-review summaries show the per-pet average, count and clear expand control")
        expect(palatability.contains("review.resolvedScore") && palatability.contains("review.note") && palatability.contains("HomeDateText.display(review.reviewDate)"), "expanded reviews retain resolved score, note, date and edit action")
        expect(!palatability.contains("records.prefix(6)"), "pet history is not truncated to six records")
        expect(heroLine.contains("store.petWeightedAverageInboundUnitPrice(for: item.id)") && heroLine.contains("PetItemHeroAveragePrice.text"), "hero uses the shared weighted-average inbound price")
        expect(heroLine.contains("ViewThatFits(in: .horizontal)") && heroLine.contains("HStack(alignment: .firstTextBaseline, spacing: 8)") && heroLine.contains("VStack(alignment: .leading"), "hero price stays beside the specification when possible and wraps when needed")
        expect(heroLine.contains("HomeTypography.supporting") && heroLine.contains("HomeTheme.muted") && !heroLine.contains("Spacer()"), "hero average uses muted supporting text without a far-right spacer")
        expect(priceCard.contains("入库加权均价") && priceCard.contains("averageUnitPrice"), "price history retains its original weighted-average reference")
    }

    private static func petProfile(_ id: String, name: String, createdAt: Double) -> PetProfile {
        PetProfile(id: id, name: name, image: nil, breed: "", birthDate: "", isDeleted: false, createdAt: createdAt, updatedAt: createdAt)
    }

    private static func palatabilityReview(
        _ id: String,
        productID: String = "product",
        petID: String,
        petName: String,
        date: String,
        createdAt: Double,
        score: Int? = nil,
        preference: String = "一般",
        note: String? = nil
    ) -> PetPalatabilityReview {
        PetPalatabilityReview(
            id: id, productID: productID, petID: petID, petNameSnapshot: petName,
            reviewDate: date, preference: preference, score: score, note: note,
            createdAt: createdAt, updatedAt: createdAt
        )
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
        total: Double? = nil,
        source: PetInventorySource = .manual,
        linkedOperationID: String? = nil
    ) -> PetInventoryTransaction {
        PetInventoryTransaction(
            id: id, productID: "product", type: type, quantityChange: quantityChange,
            quantityBefore: 0, quantityAfter: type == .adjustment ? abs(quantityChange) : 0,
            unit: "袋", occurrenceDate: occurrenceDate, reason: "reason \(id)", source: source,
            linkedOperationID: linkedOperationID, totalPrice: total,
            unitPrice: total.map { $0 / abs(quantityChange) }, purchaseChannel: "channel \(id)",
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
