import Foundation

@main
struct PetInventoryCostingAcceptance {
    static func main() throws {
        try weightedAverageUsesInboundQuantity()
        try expiryBatchLedgerKeepsLegacyBalanceUndated()
        try expiryBatchLedgerAllocatesWithinSameDateFIFO()
        try expiryBatchLedgerRejectsOverAllocation()
        try expiryBatchLedgerRejectsFutureReceiptAllocation()
        try balanceDateAssignmentsPreserveLegacyBalanceAndBackupCompatibility()
        try directBalanceDateEditsPreserveCurrentStockAndExplicitGroups()
        try balanceDateAssignmentsRestoreOutboundAndKeepOldSourceHistory()
        try balanceDateAssignmentsRejectOveruseAndUnsafeSourceDeletion()
        try expiryBatchFieldsRemainBackwardCompatible()
        try untrackedLegacyReceiptCannotBeAssignedAnExpiryDate()
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
        try petReviewPresentationContracts()
        try petProductReviewDimensionOrdering()
        try petEventNavigationContracts()
        try heroAveragePricePresentation()
        try petExpiryPresentationContracts()
        try petItemDetailPresentationContracts()
        try petHomepagePriceAndInventoryValuationContracts()
        try inventoryValuation()
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

    private static func expiryBatchLedgerKeepsLegacyBalanceUndated() throws {
        var oldReceipt = transaction("old-receipt", .inbound, 5, "2026-01-01", 1)
        oldReceipt.expirationDate = "2026-02-01"
        oldReceipt.tracksExpirationBatch = false
        let oldOutbound = transaction("old-out", .outbound, -2, "2026-01-02", 2)
        var knownUnusedReceipt = transaction("new-receipt", .inbound, 4, "2026-01-03", 3)
        knownUnusedReceipt.expirationDate = "2026-03-01"
        knownUnusedReceipt.tracksExpirationBatch = true

        let groups = PetInventoryBatchLedger.groups(from: try PetInventoryBatchLedger.balances(
            productID: "product",
            transactions: [oldReceipt, oldOutbound, knownUnusedReceipt]
        ))
        expect(groups.map(\.expirationDate) == ["2026-03-01", nil], "undated legacy balances stay separate from dated unused receipts")
        expectClose(groups.first?.remainingQuantity, 4, "dated receipt remains fully available")
        expectClose(groups.last?.remainingQuantity, 3, "legacy net balance remains in the no-date group")
    }

    private static func expiryBatchLedgerAllocatesWithinSameDateFIFO() throws {
        var first = transaction("z-same-date-first", .inbound, 2, "2026-01-01", 1)
        first.expirationDate = "2026-02-01"
        first.tracksExpirationBatch = true
        var second = transaction("a-same-date-second", .inbound, 3, "2026-01-02", 2)
        second.expirationDate = "2026-02-01"
        second.tracksExpirationBatch = true
        let groups = PetInventoryBatchLedger.groups(from: try PetInventoryBatchLedger.balances(
            productID: "product",
            transactions: [first, second]
        ))
        let plan = try PetInventoryBatchLedger.allocations(
            groupQuantities: ["2026-02-01": 3],
            groups: groups,
            requiredTotal: 3
        )
        expect(plan.map(\.sourceBatchID) == ["z-same-date-first", "a-same-date-second"], "same-date receipts retain FIFO source order even when IDs sort differently")
        expectClose(plan.first?.quantity, 2, "FIFO allocation consumes the oldest receipt first")
        expectClose(plan.last?.quantity, 1, "FIFO allocation continues into the next same-date receipt")

        var outbound = transaction("same-date-out", .outbound, -3, "2026-01-03", 3)
        outbound.batchAllocations = plan
        let remaining = try PetInventoryBatchLedger.balances(
            productID: "product",
            transactions: [first, second, outbound]
        )
        expectClose(remaining.first(where: { $0.id == "a-same-date-second" })?.remainingQuantity, 2, "outbound keeps the exact remaining batch balance")
    }

    private static func expiryBatchLedgerRejectsOverAllocation() throws {
        var receipt = transaction("small-receipt", .inbound, 2, "2026-01-01", 1)
        receipt.expirationDate = "2026-02-01"
        receipt.tracksExpirationBatch = true
        let groups = PetInventoryBatchLedger.groups(from: try PetInventoryBatchLedger.balances(
            productID: "product",
            transactions: [receipt]
        ))
        do {
            _ = try PetInventoryBatchLedger.allocations(
                groupQuantities: ["2026-02-01": 3],
                groups: groups,
                requiredTotal: 3
            )
            fatalError("batch allocation must not exceed the available batch quantity")
        } catch is PetInventoryBatchLedger.InvalidLedger {
            // Expected: allocation validation is atomic and leaves source records unchanged.
        }
    }

    private static func expiryBatchLedgerRejectsFutureReceiptAllocation() throws {
        var futureReceipt = transaction("future-receipt", .inbound, 2, "2026-02-01", 1)
        futureReceipt.expirationDate = "2026-03-01"
        futureReceipt.tracksExpirationBatch = true
        var earlierOutbound = transaction("earlier-out", .outbound, -1, "2026-01-01", 2)
        earlierOutbound.batchAllocations = [PetInventoryBatchAllocation(sourceBatchID: futureReceipt.id, quantity: 1)]
        do {
            _ = try PetInventoryBatchLedger.balances(
                productID: "product",
                transactions: [futureReceipt, earlierOutbound]
            )
            fatalError("an outbound must not use a receipt that occurs later in history")
        } catch is PetInventoryBatchLedger.InvalidLedger {
            // Expected: allocation sources must exist earlier in the transaction timeline.
        }
    }

    private static func expiryBatchFieldsRemainBackwardCompatible() throws {
        let oldBackup = """
        {"petInventoryTransactions":[{"id":"legacy","productID":"product","type":"outbound","quantityChange":-1,"quantityBefore":2,"quantityAfter":1,"unit":"袋","occurrenceDate":"2026-01-01","reason":"旧出库","source":"manual","createdAt":1,"updatedAt":1}]}
        """
        let decoded = try JSONDecoder().decode(HomeBackup.self, from: Data(oldBackup.utf8))
        let record = decoded.petInventoryTransactions.first!
        expect(record.tracksExpirationBatch == nil && record.batchAllocations == nil, "older backups decode with no invented batch tracking or allocation")
        expect(decoded.petInventoryBalanceAllocations.isEmpty, "older backups decode without invented balance date assignments")
    }

    private static func balanceDateAssignmentsPreserveLegacyBalanceAndBackupCompatibility() throws {
        let receipt = transaction("legacy-in", .inbound, 11, "2026-01-01", 1, total: 110)
        let oldOutbound = transaction("legacy-out", .outbound, -2, "2026-01-02", 2)
        let mappings = [
            balanceAllocation("date-a", source: PetInventoryBatchLedger.unassignedBatchID(for: "product"), sourceAvailableBefore: 9, expiry: "2026-02-01", quantity: 3, date: "2026-01-03", createdAt: 3),
            balanceAllocation("date-b", source: PetInventoryBatchLedger.unassignedBatchID(for: "product"), sourceAvailableBefore: 6, expiry: "2026-03-01", quantity: 6, date: "2026-01-03", createdAt: 4)
        ]
        let source = backup(
            transactions: [receipt, oldOutbound],
            activities: [activity(receipt), activity(oldOutbound)],
            quantity: 9,
            price: 10
        )
        let balances = try PetInventoryBatchLedger.balances(
            productID: "product",
            transactions: source.petInventoryTransactions,
            balanceAllocations: mappings
        )
        let groups = PetInventoryBatchLedger.groups(from: balances)
        expect(groups.map(\.expirationDate) == ["2026-02-01", "2026-03-01"], "legacy undated balance can be split across multiple expiry dates")
        expectClose(groups[0].remainingQuantity, 3, "first mapped expiry balance")
        expectClose(groups[1].remainingQuantity, 6, "second mapped expiry balance")
        expectClose(groups.reduce(0) { $0 + $1.remainingQuantity }, 9, "date assignments preserve the existing stock quantity")
        expect(source.petInventoryTransactions == [receipt, oldOutbound], "date assignment does not create or edit inventory transactions")
        expect(source.activities == [activity(receipt), activity(oldOutbound)], "date assignment does not add inventory activity records")

        var encodedBackup = source
        encodedBackup.petInventoryBalanceAllocations = mappings
        let encoded = try JSONEncoder().encode(encodedBackup)
        let decoded = try JSONDecoder().decode(HomeBackup.self, from: encoded)
        expect(decoded.petInventoryBalanceAllocations == mappings, "balance date assignments survive backup encode and decode")
        let reopenedGroups = PetInventoryBatchLedger.groups(from: try PetInventoryBatchLedger.balances(
            productID: "product",
            transactions: decoded.petInventoryTransactions,
            balanceAllocations: decoded.petInventoryBalanceAllocations
        ))
        expect(reopenedGroups == groups, "reopened backup recreates the same expiry groups and balances")

        let replay = try PetInventoryCosting.replay([receipt, oldOutbound].map(costEvent))
        expectClose(replay.currentQuantity, 9, "weighted-cost replay retains the same quantity after date assignment")
        expectClose(PetInventoryCosting.weightedAverageInboundUnitPrice([receipt, oldOutbound].map(costEvent)), 10, "weighted inbound price is independent of date assignment")
        let outboundExpense = replay.events.compactMap {
            PetInventoryCosting.recordedOutboundTotal(quantityChange: $0.quantityChange, totalPrice: $0.totalPrice, unitPrice: $0.unitPrice)
        }.reduce(0, +)
        expectClose(outboundExpense, 20, "recorded expense remains unchanged after date assignment")
    }

    private static func directBalanceDateEditsPreserveCurrentStockAndExplicitGroups() throws {
        let receipt = transaction("direct-edit-in", .inbound, 10, "2026-01-01", 1, total: 80)
        let oldOutbound = transaction("direct-edit-out", .outbound, -2, "2026-01-02", 2)
        let source = backup(
            transactions: [receipt, oldOutbound],
            activities: [activity(receipt), activity(oldOutbound)],
            quantity: 8,
            price: 8
        )
        let sourceGroups = PetInventoryBatchLedger.groups(from: try PetInventoryBatchLedger.balances(
            productID: "product",
            transactions: source.petInventoryTransactions
        ))
        expect(sourceGroups.count == 1 && sourceGroups[0].expirationDate == nil, "legacy on-hand quantity starts as one undated balance row")

        let blankRowPlan = try PetInventoryBatchLedger.editedBalanceAllocations(
            productID: "product",
            currentGroups: sourceGroups,
            edits: [
                PetInventoryBalanceEdit(id: sourceGroups[0].id, sourceGroupID: sourceGroups[0].id, expirationDate: nil, quantity: 8),
                PetInventoryBalanceEdit(id: "blank", sourceGroupID: nil, expirationDate: nil, quantity: 0)
            ],
            effectiveDate: "2026-10-30",
            createdAt: 10
        )
        expect(blankRowPlan.isEmpty, "an untouched blank added row creates no balance mapping")

        let mappings = try PetInventoryBatchLedger.editedBalanceAllocations(
            productID: "product",
            currentGroups: sourceGroups,
            edits: [
                PetInventoryBalanceEdit(id: sourceGroups[0].id, sourceGroupID: sourceGroups[0].id, expirationDate: "2026-03-01", quantity: 5),
                PetInventoryBalanceEdit(id: "second-date", sourceGroupID: nil, expirationDate: "2026-04-01", quantity: 2)
            ],
            effectiveDate: "2026-10-30",
            createdAt: 10
        )
        let editedGroups = PetInventoryBatchLedger.groups(from: try PetInventoryBatchLedger.balances(
            productID: "product",
            transactions: source.petInventoryTransactions,
            balanceAllocations: mappings
        ))
        expect(editedGroups.map(\.expirationDate) == ["2026-03-01", "2026-04-01", nil], "direct date edits create two dated rows and keep the remainder undated")
        expectClose(editedGroups.first { $0.expirationDate == "2026-03-01" }?.remainingQuantity, 5, "first directly edited date quantity")
        expectClose(editedGroups.first { $0.expirationDate == "2026-04-01" }?.remainingQuantity, 2, "new date row receives only its explicitly entered quantity")
        expectClose(editedGroups.first { $0.expirationDate == nil }?.remainingQuantity, 1, "unassigned stock remains undated")
        expectClose(editedGroups.reduce(0) { $0 + $1.remainingQuantity }, 8, "editing date rows preserves total on-hand stock")
        expect(source.petInventoryTransactions == [receipt, oldOutbound], "direct date edits do not create or modify inventory transactions")
        expect(source.activities == [activity(receipt), activity(oldOutbound)], "direct date edits do not create inventory activity records")

        let setSingleDate = try PetInventoryBatchLedger.editedBalanceAllocations(
            productID: "product",
            currentGroups: sourceGroups,
            edits: [PetInventoryBalanceEdit(
                id: sourceGroups[0].id,
                sourceGroupID: sourceGroups[0].id,
                sourceGroupQuantity: sourceGroups[0].remainingQuantity,
                expirationDate: "2026-05-01",
                quantity: 8
            )],
            effectiveDate: "2026-10-30",
            createdAt: 11
        )
        let setSingleDateGroups = PetInventoryBatchLedger.groups(from: try PetInventoryBatchLedger.balances(
            productID: "product",
            transactions: source.petInventoryTransactions,
            balanceAllocations: setSingleDate
        ))
        expect(setSingleDateGroups.count == 1 && setSingleDateGroups[0].expirationDate == "2026-05-01", "a single undated balance can be assigned one expiry date without re-entering its quantity")
        let clearSingleDate = try PetInventoryBatchLedger.editedBalanceAllocations(
            productID: "product",
            currentGroups: setSingleDateGroups,
            edits: [PetInventoryBalanceEdit(
                id: setSingleDateGroups[0].id,
                sourceGroupID: setSingleDateGroups[0].id,
                sourceGroupQuantity: setSingleDateGroups[0].remainingQuantity,
                expirationDate: nil,
                quantity: 8
            )],
            effectiveDate: "2026-10-30",
            createdAt: 12
        )
        let clearedSingleDateGroups = PetInventoryBatchLedger.groups(from: try PetInventoryBatchLedger.balances(
            productID: "product",
            transactions: source.petInventoryTransactions,
            balanceAllocations: setSingleDate + clearSingleDate
        ))
        expect(clearedSingleDateGroups.count == 1 && clearedSingleDateGroups[0].expirationDate == nil, "clearing a date moves the complete existing balance back to the undated group")
        expectClose(clearedSingleDateGroups[0].remainingQuantity, 8, "clearing a single date preserves its complete quantity")

        var rejectedStaleQuantity = false
        do {
            _ = try PetInventoryBatchLedger.editedBalanceAllocations(
                productID: "product",
                currentGroups: sourceGroups,
                edits: [PetInventoryBalanceEdit(
                    id: sourceGroups[0].id,
                    sourceGroupID: sourceGroups[0].id,
                    sourceGroupQuantity: 7,
                    expirationDate: "2026-03-01",
                    quantity: 8
                )],
                effectiveDate: "2026-10-30",
                createdAt: 10
            )
        } catch is PetInventoryBatchLedger.InvalidLedger {
            rejectedStaleQuantity = true
        }
        expect(rejectedStaleQuantity, "stale date rows cannot overwrite a group changed by another inventory action")

        var editedBackup = source
        editedBackup.petInventoryBalanceAllocations = mappings
        let decodedBackup = try JSONDecoder().decode(HomeBackup.self, from: JSONEncoder().encode(editedBackup))
        let reopenedGroups = PetInventoryBatchLedger.groups(from: try PetInventoryBatchLedger.balances(
            productID: "product",
            transactions: decodedBackup.petInventoryTransactions,
            balanceAllocations: decodedBackup.petInventoryBalanceAllocations
        ))
        expect(reopenedGroups == editedGroups, "direct date rows survive backup encode, restart decode and ledger replay")
        expectClose(PetInventoryCosting.weightedAverageInboundUnitPrice([receipt, oldOutbound].map(costEvent)), 8, "date editing does not change the weighted inbound price")
        let costBefore = try PetInventoryCosting.replay([receipt, oldOutbound].map(costEvent))
        let costAfter = try PetInventoryCosting.replay(decodedBackup.petInventoryTransactions.map(costEvent))
        expectClose(costAfter.currentQuantity, costBefore.currentQuantity, "date editing does not change inventory valuation quantity")
        expectClose(costAfter.events.compactMap { PetInventoryCosting.recordedOutboundTotal(quantityChange: $0.quantityChange, totalPrice: $0.totalPrice, unitPrice: $0.unitPrice) }.reduce(0, +), costBefore.events.compactMap { PetInventoryCosting.recordedOutboundTotal(quantityChange: $0.quantityChange, totalPrice: $0.totalPrice, unitPrice: $0.unitPrice) }.reduce(0, +), "date editing does not change historical outbound expense")

        var firstDatedReceipt = transaction("edit-date-a", .inbound, 5, "2026-01-01", 3)
        firstDatedReceipt.expirationDate = "2026-02-01"
        firstDatedReceipt.tracksExpirationBatch = true
        var secondDatedReceipt = transaction("edit-date-b", .inbound, 3, "2026-01-02", 4)
        secondDatedReceipt.expirationDate = "2026-03-01"
        secondDatedReceipt.tracksExpirationBatch = true
        let multiDateReceipts = [firstDatedReceipt, secondDatedReceipt]
        let multiDateGroups = PetInventoryBatchLedger.groups(from: try PetInventoryBatchLedger.balances(
            productID: "product",
            transactions: multiDateReceipts
        ))
        let explicitTransfers = try PetInventoryBatchLedger.editedBalanceAllocations(
            productID: "product",
            currentGroups: multiDateGroups,
            edits: [
                PetInventoryBalanceEdit(id: "edit-date-a", sourceGroupID: "2026-02-01", expirationDate: "2026-02-01", quantity: 3),
                PetInventoryBalanceEdit(id: "edit-date-b", sourceGroupID: "2026-03-01", expirationDate: "2026-03-01", quantity: 3),
                PetInventoryBalanceEdit(id: "edit-date-c", sourceGroupID: nil, expirationDate: "2026-04-01", quantity: 2)
            ],
            effectiveDate: "2026-10-30",
            createdAt: 10
        )
        let explicitGroups = PetInventoryBatchLedger.groups(from: try PetInventoryBatchLedger.balances(
            productID: "product",
            transactions: multiDateReceipts,
            balanceAllocations: explicitTransfers
        ))
        expectClose(explicitGroups.first { $0.expirationDate == "2026-02-01" }?.remainingQuantity, 3, "editing one date row leaves the other existing date intact")
        expectClose(explicitGroups.first { $0.expirationDate == "2026-03-01" }?.remainingQuantity, 3, "an unchanged date row is not silently overwritten")
        expectClose(explicitGroups.first { $0.expirationDate == "2026-04-01" }?.remainingQuantity, 2, "a newly added date row receives only its explicit quantity")

        let sameDateEdits = try PetInventoryBatchLedger.editedBalanceAllocations(
            productID: "product",
            currentGroups: sourceGroups,
            edits: [
                PetInventoryBalanceEdit(id: sourceGroups[0].id, sourceGroupID: sourceGroups[0].id, expirationDate: "2026-05-01", quantity: 3),
                PetInventoryBalanceEdit(id: "same-date-extra", sourceGroupID: nil, expirationDate: "2026-05-01", quantity: 5)
            ],
            effectiveDate: "2026-10-30",
            createdAt: 10
        )
        let mergedGroups = PetInventoryBatchLedger.groups(from: try PetInventoryBatchLedger.balances(
            productID: "product",
            transactions: source.petInventoryTransactions,
            balanceAllocations: sameDateEdits
        ))
        expect(mergedGroups.count == 1 && mergedGroups[0].expirationDate == "2026-05-01", "direct rows with the same date merge into one date group")
        expectClose(mergedGroups.first?.remainingQuantity, 8, "same-date grouping retains the complete balance")

        var rejectedOversize = false
        do {
            _ = try PetInventoryBatchLedger.editedBalanceAllocations(
                productID: "product",
                currentGroups: sourceGroups,
                edits: [PetInventoryBalanceEdit(id: sourceGroups[0].id, sourceGroupID: sourceGroups[0].id, expirationDate: "2026-03-01", quantity: 9)],
                effectiveDate: "2026-10-30",
                createdAt: 10
            )
        } catch is PetInventoryBatchLedger.InvalidLedger {
            rejectedOversize = true
        }
        expect(rejectedOversize, "direct quantity edits cannot exceed total current inventory")

        var rejectedNegative = false
        do {
            _ = try PetInventoryBatchLedger.editedBalanceAllocations(
                productID: "product",
                currentGroups: sourceGroups,
                edits: [PetInventoryBalanceEdit(id: sourceGroups[0].id, sourceGroupID: sourceGroups[0].id, expirationDate: nil, quantity: -1)],
                effectiveDate: "2026-10-30",
                createdAt: 10
            )
        } catch is PetInventoryBatchLedger.InvalidLedger {
            rejectedNegative = true
        }
        expect(rejectedNegative, "direct quantity edits reject negative values")
    }

    private static func balanceDateAssignmentsRestoreOutboundAndKeepOldSourceHistory() throws {
        let receipt = transaction("mapped-in", .inbound, 11, "2026-01-01", 1, total: 110)
        let oldOutbound = transaction("unassigned-out", .outbound, -2, "2026-01-02", 2)
        let mapA = balanceAllocation("map-a", source: PetInventoryBatchLedger.unassignedBatchID(for: "product"), sourceAvailableBefore: 9, expiry: "2026-02-01", quantity: 3, date: "2026-01-03", createdAt: 3)
        let mapB = balanceAllocation("map-b", source: PetInventoryBatchLedger.unassignedBatchID(for: "product"), sourceAvailableBefore: 6, expiry: "2026-03-01", quantity: 6, date: "2026-01-03", createdAt: 3)
        var assignedOutbound = transaction("mapped-out", .outbound, -1, "2026-01-04", 4)
        assignedOutbound.batchAllocations = [PetInventoryBatchAllocation(sourceBatchID: "map-a", quantity: 1)]
        var source = backup(
            transactions: [receipt, oldOutbound, assignedOutbound],
            activities: [activity(receipt), activity(oldOutbound), activity(assignedOutbound)],
            quantity: 8,
            price: 10
        )
        source.petInventoryBalanceAllocations = [mapA, mapB]
        var groups = PetInventoryBatchLedger.groups(from: try PetInventoryBatchLedger.balances(
            productID: "product",
            transactions: source.petInventoryTransactions,
            balanceAllocations: source.petInventoryBalanceAllocations
        ))
        expectClose(groups.first { $0.expirationDate == "2026-02-01" }?.remainingQuantity, 2, "mapped outbound consumes the selected expiry date")

        let deletion = try PetInventoryHistoryMutation.delete(transactionID: "mapped-out", from: source, now: 9)
        groups = PetInventoryBatchLedger.groups(from: try PetInventoryBatchLedger.balances(
            productID: "product",
            transactions: deletion.backup.petInventoryTransactions,
            balanceAllocations: deletion.backup.petInventoryBalanceAllocations
        ))
        expectClose(groups.first { $0.expirationDate == "2026-02-01" }?.remainingQuantity, 3, "deleting the outbound restores stock to its mapped expiry date")
        expectClose(deletion.backup.petItems.first?.quantity, 9, "deleting mapped outbound restores its quantity")

        let correctedDate = balanceAllocation("corrected-a", source: "map-a", sourceAvailableBefore: 2, expiry: "2026-04-01", quantity: 1, date: "2026-01-05", createdAt: 5)
        let correctedGroups = PetInventoryBatchLedger.groups(from: try PetInventoryBatchLedger.balances(
            productID: "product",
            transactions: source.petInventoryTransactions,
            balanceAllocations: source.petInventoryBalanceAllocations + [correctedDate]
        ))
        expectClose(correctedGroups.first { $0.expirationDate == "2026-02-01" }?.remainingQuantity, 1, "correcting a batch date moves only the remaining quantity")
        expectClose(correctedGroups.first { $0.expirationDate == "2026-04-01" }?.remainingQuantity, 1, "corrected remaining quantity appears under its new date")
        expect(source.petInventoryTransactions.first { $0.id == "mapped-out" }?.batchAllocations?.first?.sourceBatchID == "map-a", "past outbound remains associated with its original mapping source")
    }

    private static func balanceDateAssignmentsRejectOveruseAndUnsafeSourceDeletion() throws {
        let smallReceipt = transaction("small-legacy", .inbound, 2, "2026-01-01", 1)
        let overAllocation = balanceAllocation("too-much", source: PetInventoryBatchLedger.unassignedBatchID(for: "product"), sourceAvailableBefore: 2, expiry: "2026-02-01", quantity: 3, date: "2026-01-02", createdAt: 2)
        var rejected = false
        do {
            _ = try PetInventoryBatchLedger.balances(
                productID: "product",
                transactions: [smallReceipt],
                balanceAllocations: [overAllocation]
            )
        } catch is PetInventoryBatchLedger.InvalidLedger {
            rejected = true
        }
        expect(rejected, "date assignment cannot move more than the current source balance")

        let receipt = transaction("source-to-map", .inbound, 4, "2026-01-01", 1)
        var trackedReceipt = receipt
        trackedReceipt.tracksExpirationBatch = true
        let trackedMap = balanceAllocation("tracked-map", source: trackedReceipt.id, sourceAvailableBefore: 4, expiry: "2026-02-01", quantity: 2, date: "2026-01-02", createdAt: 2)
        var source = backup(transactions: [trackedReceipt], activities: [activity(trackedReceipt)], quantity: 4)
        source.petInventoryBalanceAllocations = [trackedMap]
        do {
            _ = try PetInventoryHistoryMutation.delete(transactionID: trackedReceipt.id, from: source, now: 3)
            fatalError("a receipt that directly backs a balance date assignment cannot be deleted")
        } catch let error as PetInventoryHistoryMutation.Failure {
            guard case .batchAllocationSourceInUse = error else {
                fatalError("unexpected failure while protecting a mapped receipt source")
            }
        }
        expect(source.petInventoryTransactions == [trackedReceipt] && source.petInventoryBalanceAllocations == [trackedMap], "rejected source deletion leaves the backup unchanged")

        let legacy = transaction("legacy-map-source", .inbound, 4, "2026-01-01", 1)
        let otherLegacy = transaction("other-legacy-map-source", .inbound, 4, "2026-01-01", 1.5)
        let mapping = balanceAllocation("legacy-map", source: PetInventoryBatchLedger.unassignedBatchID(for: "product"), sourceAvailableBefore: 8, expiry: "2026-02-01", quantity: 2, date: "2026-01-02", createdAt: 2)
        var legacySource = backup(
            transactions: [legacy, otherLegacy],
            activities: [activity(legacy), activity(otherLegacy)],
            quantity: 8
        )
        legacySource.petInventoryBalanceAllocations = [mapping]
        do {
            _ = try PetInventoryHistoryMutation.delete(transactionID: legacy.id, from: legacySource, now: 3)
            fatalError("deleting an untracked legacy receipt must not invalidate its undated-pool mapping")
        } catch is PetInventoryBatchLedger.InvalidLedger {
            // Expected: replay cannot consume a date assignment whose unassigned source no longer exists.
        }
        expect(legacySource.petInventoryTransactions == [legacy, otherLegacy] && legacySource.petInventoryBalanceAllocations == [mapping], "failed legacy source deletion keeps original transactions and mappings")
    }

    private static func untrackedLegacyReceiptCannotBeAssignedAnExpiryDate() throws {
        var receipt = transaction("legacy-receipt", .inbound, 2, "2026-01-01", 1)
        receipt.expirationDate = "2026-02-01"
        receipt.tracksExpirationBatch = false
        let source = backup(transactions: [receipt], activities: [activity(receipt)], quantity: 2, price: nil)
        do {
            _ = try PetInventoryHistoryMutation.update(
                transactionID: receipt.id,
                quantity: 2,
                occurrenceDate: receipt.occurrenceDate,
                totalPrice: nil,
                note: nil,
                expirationDate: "2026-03-01",
                updateExpirationDate: true,
                now: 2,
                in: source
            )
            fatalError("untracked legacy stock must not be assigned a misleading expiry date")
        } catch let error as PetInventoryHistoryMutation.Failure {
            guard case .batchExpirationNotTrackable = error else {
                fatalError("unexpected failure while protecting untracked legacy expiry")
            }
        }
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
        ), let noRepurchase = sourceSlice(
            petItemsSource,
            from: "struct PetNoRepurchaseLibraryView: View",
            to: "struct PetItemDetailView: View"
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
        expect(pending.contains(".navigationDestination(item: $detailItemID)") && pending.contains("PetItemDetailView(itemID: itemID)"), "pending items retain their detail navigation")
        expect(pending.contains("PetProductThumbnail(item: item)") && pending.contains("PetProductListRowContent(item: item)") && pending.contains("panelDivider") && pending.contains("panelBottomCap") && pending.contains(".listStyle(.plain)"), "pending list reuses the home thumbnail, shared product row and divided card layout")
        expect(!pending.contains("quickManagerRow") && !pending.contains("openEditor") && !pending.contains("新增"), "pending list has no stock quick actions or add-item control")
        expect(noRepurchase.contains("store.categories(for: .pet)") && noRepurchase.contains("store.categories(for: .pet, parentID: $0.id)"), "no-repurchase library reuses the live two-level pet categories")
        expect(noRepurchase.contains("ForEach(primaryCategories)") && noRepurchase.contains("ForEach(secondaryCategories)") && noRepurchase.contains("HomeUnderlineTab"), "no-repurchase library displays both category levels with the same home selectors")
        expect(noRepurchase.contains("$0.resolvedPrimaryCategory == selectedPrimary.name") && noRepurchase.contains("$0.resolvedSecondaryCategory == selectedSecondary.name"), "no-repurchase products are isolated by both selected category levels")
        expect(noRepurchase.contains("secondaryID = preferredSecondary?.id ?? \"\"") && noRepurchase.contains("onChange(of: secondaryCategories.map(\\.id))"), "no-repurchase category selection stays valid as managed categories change")
        expect(noRepurchase.contains("PetProductListRowContent(item: item)") && noRepurchase.contains("panelDivider") && noRepurchase.contains("panelBottomCap") && noRepurchase.contains(".listStyle(.plain)"), "no-repurchase products use the shared row and the same rounded divided-card list layout")
        expect(noRepurchase.contains("store.setPetItemRepurchase(id: item.id, willRepurchase: true)") && noRepurchase.contains("permanentlyDeletePetItem(id: item.id)"), "category filtering retains restore and permanent-delete actions")
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
            palatabilityReview("bling-old", petID: bling.id, petName: bling.name, date: "2026-01-05", createdAt: 1, preference: "喜欢"),
            palatabilityReview("bling-same-day", petID: bling.id, petName: bling.name, date: "2026-01-01", createdAt: 2, score: 4),
            palatabilityReview("bling-new", petID: bling.id, petName: bling.name, date: "2026-01-01", createdAt: 3, score: 3, note: "最近添加的记录"),
            deletedPetReviews[0],
            palatabilityReview("other-product", productID: "other", petID: bling.id, petName: bling.name, date: "2026-01-05", createdAt: 5, score: 1)
        ]

        let groups = PetPalatabilityReviewGrouping.groups(
            productID: "product",
            reviews: reviews,
            activePets: [bling, secondPet]
        )
        expect(groups.map(\.petID) == ["bling", "second", "deleted-pet"], "palatability summaries follow active-pet order, then include deleted-pet history")
        expect(groups[0].petName == "BLING" && groups[0].count == 3, "multiple reviews collapse into one current-pet summary")
        expectClose(groups[0].averageScore, 4, "legacy preference score participates in the per-pet average")
        expect(groups[0].records.map(\.id) == ["bling-new", "bling-same-day", "bling-old"], "collapsed latest record and source history follow creation time even when review dates differ")
        expect(groups[0].latestRecord?.note == "最近添加的记录", "the collapsed summary uses the note from the most recently added review")
        expect(groups[0].oldestFirstRecords.map(\.id) == ["bling-old", "bling-same-day", "bling-new"], "expanded history is chronologically ordered by creation time with stable same-day records")
        expect(groups[1].count == 1, "a single review remains one editable pet entry")
        expectClose(groups[1].averageScore, 3, "legacy neutral preference maps to its resolved score")
        expect(groups[2].petName == "历史猫", "deleted pets retain their recorded name")
        expectClose(groups[2].averageScore, 1, "legacy dislike preference maps to its resolved score")

        var editedReview = reviews.first { $0.id == "bling-new" }!
        editedReview.score = 1
        editedReview.preference = "不喜欢"
        editedReview.reviewDate = "2025-12-31"
        expect(editedReview.createdAt == 3, "editing a historical review date preserves its creation timestamp")
        let afterEdit = PetPalatabilityReviewGrouping.groups(
            productID: "product",
            reviews: reviews.map { $0.id == editedReview.id ? editedReview : $0 },
            activePets: [bling, secondPet]
        )
        expectClose(afterEdit[0].averageScore, 10.0 / 3.0, "editing one review immediately changes that pet's average")
        expect(afterEdit[0].latestRecord?.id == "bling-new", "editing a review date does not make it stop being the newest-added summary")

        let singleReviewGroup = PetPalatabilityReviewGrouping.groups(
            productID: "product",
            reviews: [palatabilityReview("only", petID: bling.id, petName: bling.name, date: "2026-01-01", createdAt: 1, score: 5)],
            activePets: [bling]
        )
        expect(singleReviewGroup.count == 1 && singleReviewGroup[0].count == 1, "one review produces exactly one non-aggregated summary")
        expectClose(singleReviewGroup[0].averageScore, 5, "one-review summary shows that review's own score")
    }

    private static func petReviewPresentationContracts() throws {
        let presentationSource = try String(contentsOfFile: "HomeOSNative/Models/PetItemDetailPresentation.swift", encoding: .utf8)
        let itemViewSource = try String(contentsOfFile: "HomeOSNative/Views/PetItemViews.swift", encoding: .utf8)
        let editorSource = try String(contentsOfFile: "HomeOSNative/Views/PetInventoryViews.swift", encoding: .utf8)
        let storeSource = try String(contentsOfFile: "HomeOSNative/Data/HomeStore.swift", encoding: .utf8)
        let designSource = try String(contentsOfFile: "HomeOSNative/Design/DesignSystem.swift", encoding: .utf8)
        guard let productCard = sourceSlice(
            itemViewSource,
            from: "    private var productReviewCard: some View {",
            to: "    private var palatabilityCard: some View {"
        ), let palatability = sourceSlice(
            itemViewSource,
            from: "    private var palatabilityCard: some View {",
            to: "    @ViewBuilder private func detailProductImage"
        ), let productEditor = sourceSlice(
            editorSource,
            from: "struct PetProductReviewEditorView: View",
            to: "struct PetPalatabilityEditorView: View"
        ), let catEditor = sourceSlice(
            editorSource,
            from: "struct PetPalatabilityEditorView: View",
            to: "struct PetPreferenceSummaryView: View"
        ), let palatabilitySave = sourceSlice(
            storeSource,
            from: "    func savePetPalatabilityReview(",
            to: "    func initializeLitter(amount: Double, occurrenceDate: String) -> Bool {"
        ), let productSave = sourceSlice(
            storeSource,
            from: "    func savePetProductReview(",
            to: "    func petProductRating(productID: String) -> PetRatingSummary? {"
        ), let productUpdate = sourceSlice(
            productSave,
            from: "        if let id {",
            to: "        } else {"
        ), let palatabilityUpdate = sourceSlice(
            palatabilitySave,
            from: "        if let id, let index = next.petPalatabilityReviews.firstIndex",
            to: "        } else {"
        ) else {
            fatalError("pet product or cat review presentation source is missing")
        }

        expect(PetReviewDateText.display("2026-10-22") == "2026-10-22", "product detail dates keep the yyyy-MM-dd numeric form")
        expect(PetReviewDateText.display("") == "--" && PetReviewDateText.display("legacy date") == "legacy date", "empty and legacy review dates remain readable")
        expect(presentationSource.contains("dateFormat = \"yyyy-MM-dd\"") && designSource.contains("enum HomeDateText") && designSource.contains("yyyy年M月d日"), "numeric review dates do not change the global date presentation")

        expect(productCard.contains("sorted { $0.reviewDate > $1.reviewDate }") && productCard.contains("LazyVStack") && productCard.contains("ForEach(records)"), "product review history preserves review-date order and renders every record lazily")
        expect(!productCard.contains("prefix(") && productCard.contains("PetReviewDateText.display(review.reviewDate)"), "product review history is unlimited and uses numeric dates")
        if let dimensionPosition = productCard.range(of: "Text(orderedPetReviewDimensions")?.lowerBound,
           let datePosition = productCard.range(of: "Text(PetReviewDateText.display(review.reviewDate))")?.lowerBound {
            expect(dimensionPosition < datePosition, "product review date follows the note and dimension summary")
        } else {
            fatalError("product review note, dimensions or date source is missing")
        }
        let productNotePosition = productEditor.range(of: "TextField(\"产品评价\"")?.lowerBound
        let productDatePosition = productEditor.range(of: "DatePicker(\"评价日期\"")?.lowerBound
        expect(productNotePosition != nil && productDatePosition != nil && productNotePosition! < productDatePosition!, "product review editor puts its date picker after the note")
        let catNotePosition = catEditor.range(of: "TextField(\"备注（可选）\"")?.lowerBound
        let catDatePosition = catEditor.range(of: "DatePicker(\"评价日期\"")?.lowerBound
        expect(catNotePosition != nil && catDatePosition != nil && catNotePosition! < catDatePosition!, "cat review editor puts its date picker after the note")

        expect(!palatability.contains("DisclosureGroup") && palatability.contains("ForEach(group.oldestFirstRecords)") && palatability.contains("LazyVStack"), "multi-review groups expand inline and render oldest-first history lazily")
        guard let summary = sourceSlice(palatability, from: "private func palatabilityGroupSummary", to: "private func palatabilitySingleReviewRow"),
              let single = sourceSlice(palatability, from: "private func palatabilitySingleReviewRow", to: "private func palatabilityHistoryEntry"),
              let history = sourceSlice(itemViewSource, from: "private func palatabilityHistoryEntry", to: "@ViewBuilder private func detailProductImage") else {
            fatalError("cat review row sources are missing")
        }
        expect(summary.contains("if group.count > 1") && summary.contains("Text(\"\\(group.count)条\")"), "cat review count appears beside the name only for multiple reviews")
        expect(summary.contains("group.latestRecord") && summary.contains("if !isExpanded") && summary.contains(".fixedSize(horizontal: false, vertical: true)"), "collapsed cat groups show the full latest-added note and hide it while expanded")
        expect(summary.contains("average.formatted") && summary.contains("分") && !summary.contains("chevron") && !summary.contains("查看"), "cat group summary shows one average score without disclosure clutter")
        expect(single.contains("review.resolvedScore") && single.contains("PetReviewDateText.display(review.reviewDate)") && single.contains("review.note"), "a single cat review shows its score, complete note and numeric date")
        expect(history.contains("review.resolvedScore") && history.contains("review.note") && history.contains("PetReviewDateText.display(review.reviewDate)") && history.contains("sheet = .palatability(reviewID: review.id)"), "expanded cat history keeps full notes, dates and the existing edit sheet")
        expect(productUpdate.contains("reviewDate = date") && !productUpdate.contains("createdAt ="), "editing a product review keeps its original creation timestamp")
        expect(palatabilityUpdate.contains("reviewDate = date") && !palatabilityUpdate.contains("createdAt ="), "editing a cat review keeps its original creation timestamp")
    }

    private static func heroAveragePricePresentation() throws {
        expect(PetItemHeroAveragePrice.text(average: nil, unit: "罐") == nil, "hero omits an unavailable inbound average")
        expect(PetItemHeroAveragePrice.text(average: 0, unit: "罐") == nil, "hero never displays a zero placeholder price")
        expect(PetItemHeroAveragePrice.text(average: .infinity, unit: "罐") == nil, "hero omits a non-finite average")
        expect(PetItemHeroAveragePrice.text(average: 4.67, unit: "罐") == "¥4.67/罐", "hero formats a valid weighted average with its unit and no label")
        expect(PetItemHomepageAveragePrice.text(average: 4.67, unit: "盒") == "¥4.7", "homepage rounds the displayed weighted price to one decimal without a unit")
        expect(PetItemHomepageAveragePrice.text(average: 4.64, unit: "盒") == "¥4.6", "homepage rounds down to the nearest displayed tenth when appropriate")
        expect(PetItemHomepageAveragePrice.text(average: nil, unit: "盒") == nil, "homepage hides products without valid inbound prices")
        expect(PetItemHomepageAveragePrice.text(average: .nan, unit: "盒") == nil, "homepage hides non-finite inbound prices")
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
        let detailOrder = ["productHeroCard(item)", "inventoryCard(item)", "productReviewCard", "balanceExpiryCard(item)", "priceCard(item)", "productNotesCard(item)", "transactionCard(item)"]
        let detailPositions = detailOrder.compactMap { detail.range(of: $0)?.lowerBound }
        expect(detailPositions.count == detailOrder.count && detailPositions == detailPositions.sorted(), "the standalone expiry card sits directly above price history and item notes remain second-to-last")
        if let noteCard = sourceSlice(detail, from: "private func productNotesCard(_ item: PetItem)", to: "private func inventoryCard(_ item: PetItem)") {
            expect(noteCard.contains("if !note.isEmpty"), "the moved item-notes card remains hidden when there is no note")
        } else {
            fatalError("pet item notes card source is missing")
        }
        if let inventoryCard = sourceSlice(detail, from: "private func inventoryCard(_ item: PetItem)", to: "private func balanceExpiryCard(_ item: PetItem) -> some View {") {
            expect(!inventoryCard.contains("PetInventoryBalanceRowsEditor") && !inventoryCard.contains("保存保质期"), "the inventory card contains only stock and actions; expiry editing is moved out")
        } else {
            fatalError("pet inventory card source is missing")
        }
        if let expiryCard = sourceSlice(detail, from: "private func balanceExpiryCard(_ item: PetItem) -> some View {", to: "private func expiryBalanceLabel(") {
            expect(expiryCard.contains("HomeCard(padding: 12)") && expiryCard.contains("expiryBalanceLabel(\"未设置\"") && expiryCard.contains("展开 · \\(groups.count)条") && expiryCard.contains("sheet = .balanceEdit"), "expiry is a read-only card with an unset state, expandable groups, and a single edit entry")
            expect(expiryCard.contains("group.expirationDate.map(petExpirationDisplayDate)") && expiryCard.contains("group.remainingQuantity") && expiryCard.contains("unit: item.unit"), "each displayed expiry date remains paired with its quantity and unit")
        } else {
            fatalError("pet expiry summary card source is missing")
        }
        expect(source.contains("private struct PetInventoryBalanceEditorSheet") && source.contains(".navigationTitle(\"编辑保质期\")") && source.contains("Button(\"取消\")") && source.contains("store.updatePetInventoryBalanceDates(productID: productID, edits: balanceDateEdits)"), "the detail opens one draft editor sheet with cancel/save persistence")
        expect(palatability.contains("ForEach(groups)") && !palatability.contains("DisclosureGroup(isExpanded:") && palatability.contains("ForEach(group.oldestFirstRecords)"), "each pet has one collapsed summary and can reveal every review inline")
        expect(palatability.contains("group.count == 1") && palatability.contains("sheet = .palatability(reviewID: review.id)"), "a single review opens its original editor directly")
        expect(palatability.contains("group.count > 1") && palatability.contains("Text(\"\\(group.count)条\")") && palatability.contains("average.formatted") && palatability.contains("分"), "multi-review summaries show only the adjacent count and average score")
        expect(palatability.contains("review.resolvedScore") && palatability.contains("review.note") && palatability.contains("PetReviewDateText.display(review.reviewDate)"), "expanded and single reviews retain resolved score, full note, numeric date and edit action")
        expect(!palatability.contains("records.prefix(6)"), "pet history is not truncated to six records")
        expect(heroLine.contains("store.petWeightedAverageInboundUnitPrice(for: item.id)") && heroLine.contains("PetItemHeroAveragePrice.text"), "hero uses the shared weighted-average inbound price")
        expect(heroLine.contains("ViewThatFits(in: .horizontal)") && heroLine.contains("HStack(alignment: .firstTextBaseline, spacing: 8)") && heroLine.contains("VStack(alignment: .leading"), "hero price stays beside the specification when possible and wraps when needed")
        expect(heroLine.contains("HomeTypography.supporting") && heroLine.contains("HomeTheme.muted") && !heroLine.contains("Spacer()"), "hero average uses muted supporting text without a far-right spacer")
        expect(priceCard.contains("入库加权均价") && priceCard.contains("averageUnitPrice"), "price history retains its original weighted-average reference")
    }

    private static func petProductReviewDimensionOrdering() throws {
        let foodOrder = ["适口性", "品质", "性价比", "回购意愿"]
        let supplyOrder = ["使用效果", "便利性", "耐用性", "性价比"]
        let litterOrder = ["除臭性", "结团性", "耐用性", "性价比"]
        let foodScores = ["回购意愿": 4, "性价比": 2, "品质": 5, "适口性": 3]
        let supplyScores = ["性价比": 4, "耐用性": 3, "便利性": 5, "使用效果": 2]
        let litterScores = ["耐用性": 4, "性价比": 3, "结团性": 5, "除臭性": 2]
        expect(PetProductReviewDimensionOrdering.ordered(scores: foodScores, standardOrder: foodOrder) == foodOrder, "food reviews follow the food standard order")
        expect(PetProductReviewDimensionOrdering.ordered(scores: supplyScores, standardOrder: supplyOrder) == supplyOrder, "supply reviews follow the supply standard order")
        expect(PetProductReviewDimensionOrdering.ordered(scores: litterScores, standardOrder: litterOrder) == litterOrder, "litter reviews follow the litter standard order")

        let legacyScores = foodScores.merging(["历史维度 A": 1, "历史维度 B": 5]) { current, _ in current }
        let orderedLegacyScores = PetProductReviewDimensionOrdering.ordered(scores: legacyScores, standardOrder: foodOrder)
        expect(Array(orderedLegacyScores.prefix(foodOrder.count)) == foodOrder, "known food dimensions stay in standard order before historical extras")
        expect(Set(orderedLegacyScores.dropFirst(foodOrder.count)) == Set(["历史维度 A", "历史维度 B"]), "unknown historical dimensions are retained after standard dimensions")
        expect(legacyScores["历史维度 A"] == 1 && legacyScores["历史维度 B"] == 5, "dimension ordering never changes historical scores")
        expect(PetProductReviewDimensionOrdering.ordered(scores: ["品质": 4], standardOrder: foodOrder) == ["品质"], "legacy reviews do not gain missing dimensions during editing")

        let inventorySource = try String(contentsOfFile: "HomeOSNative/Views/PetInventoryViews.swift", encoding: .utf8)
        let itemSource = try String(contentsOfFile: "HomeOSNative/Views/PetItemViews.swift", encoding: .utf8)
        guard let editor = sourceSlice(inventorySource, from: "struct PetProductReviewEditorView", to: "struct PetPalatabilityEditorView"),
              let reviewCard = sourceSlice(itemSource, from: "private var productReviewCard: some View {", to: "private var palatabilityCard: some View {") else {
            fatalError("product review history presentation source is missing")
        }
        expect(editor.contains("orderedPetReviewDimensions(existingReview.resolvedDimensionScores, item: item)"), "history editor orders persisted review dimensions by the selected item's type")
        expect(reviewCard.contains("orderedPetReviewDimensions(review.resolvedDimensionScores, item: item)"), "history summary orders dimensions by the selected item's type")
        expect(reviewCard.contains(".sorted { $0.reviewDate > $1.reviewDate }"), "review records retain their existing date ordering")
    }

    private static func petEventNavigationContracts() throws {
        let petViewSource = try String(contentsOfFile: "HomeOSNative/Views/PetView.swift", encoding: .utf8)
        let itemViewSource = try String(contentsOfFile: "HomeOSNative/Views/PetItemViews.swift", encoding: .utf8)
        let eventViewSource = try String(contentsOfFile: "HomeOSNative/Views/PetEventViews.swift", encoding: .utf8)
        guard let petView = sourceSlice(petViewSource, from: "struct PetView: View", to: "    private var header: some View {"),
              let timeline = sourceSlice(petViewSource, from: "    private var timelineSection: some View {", to: "    private func filterTab("),
              let filterRow = sourceSlice(petViewSource, from: "    private var eventFilters: some View {", to: "    private var filteredEvents: [PetEvent] {"),
              let timelineRow = sourceSlice(petViewSource, from: "    private func timelineRow(", to: "    private func shouldShowType(for event: PetEvent) -> Bool {"),
              let eventDetail = sourceSlice(eventViewSource, from: "struct PetEventDetailView: View", to: "    private func detailRow("),
              let eventEditor = sourceSlice(eventViewSource, from: "struct PetEventEditorView: View", to: "struct PetEventDetailView: View") else {
            fatalError("pet event navigation source sections are missing")
        }
        expect(petView.contains("NavigationStack(path: $navigationPath)") && petView.contains(".navigationDestination(for: PetViewRoute.self)"), "pet statistics and event screens share one explicit navigation path")
        expect(petView.contains("editsVisibleEvent = navigationPath.last == .petEventDetail(eventID)") && petView.contains("!navigationPath.contains(route)"), "only the visible event detail can push its matching editor, with repeat pushes ignored")
        expect(timeline.contains("Text(\"宠物事项\")") && timeline.contains("Button {") && timeline.contains(".newPetEvent") && timeline.contains("Image(systemName: \"plus.circle\")"), "the add button is placed on the pet-events title row")
        expect(!timeline.contains("NavigationLink") && !timeline.contains("simultaneousGesture") && !filterRow.contains("NavigationLink"), "the single list-footer row contains no competing event links or gesture recognizers")
        expect(timelineRow.contains("Button {") && timelineRow.contains(".petEventDetail(event.id)") && !timelineRow.contains("NavigationLink") && petViewSource.contains("guard navigationPath.isEmpty else { return }"), "each history row routes once to its own event, ignoring rapid taps during transitions")
        expect(petViewSource.contains("ForEach(store.activePetEventCategories)") && petViewSource.contains("selectedCategoryID == \"all\" || event.categoryID == selectedCategoryID"), "category filters continue to select the matching event history")
        expect(eventDetail.contains("Button(\"编辑\", action: onEdit)") && !eventDetail.contains("NavigationLink"), "editing pushes one explicit editor route from the active detail")
        expect(eventEditor.contains("if store.activePetEventCategories.isEmpty") && eventEditor.contains("PetEventCategorySettingsView()"), "the empty-category editor state still offers category setup")
        expect(eventDetail.contains("if event.litterOperationID == nil") && eventDetail.contains("不能单独删除"), "generated litter events keep their existing edit and delete restrictions")
        expect(petViewSource.contains("if $0.occurrenceDate == $1.occurrenceDate { return $0.createdAt > $1.createdAt }") && petViewSource.contains("return $0.occurrenceDate > $1.occurrenceDate"), "event ordering by occurrence date and creation time is unchanged")
    }

    private static func petHomepagePriceAndInventoryValuationContracts() throws {
        let listSource = try String(contentsOfFile: "HomeOSNative/Views/PetItemViews.swift", encoding: .utf8)
        let storeSource = try String(contentsOfFile: "HomeOSNative/Data/HomeStore.swift", encoding: .utf8)
        let statisticsSource = try String(contentsOfFile: "HomeOSNative/Views/PetInventoryStatisticsView.swift", encoding: .utf8)
        let valuationSource = try String(contentsOfFile: "HomeOSNative/Models/PetInventoryValuation.swift", encoding: .utf8)
        let petHomeSource = try String(contentsOfFile: "HomeOSNative/Views/PetView.swift", encoding: .utf8)
        guard let homeRow = sourceSlice(
            listSource,
            from: "    private func itemRow(_ item: PetItem) -> some View {",
            to: "    private func quickManagerRow(_ item: PetItem) -> some View {"
        ), let sharedRow = sourceSlice(
            listSource,
            from: "private struct PetProductListRowContent: View {",
            to: "private struct PetProductThumbnail: View {"
        ), let averagePriceMethod = sourceSlice(
            storeSource,
            from: "    func petWeightedAverageInboundUnitPrice(for productID: String) -> Double? {",
            to: "    func latestPetUnitPrice(for productID: String, in backup: HomeBackup? = nil) -> Double? {"
        ), let overview = sourceSlice(
            statisticsSource,
            from: "    private var overviewCard: some View {",
            to: "    private func sectionLabel(_ title: String) -> some View {"
        ), let snapshot = sourceSlice(
            statisticsSource,
            from: "private struct PetInventoryStatisticsSnapshot {",
            to: "private struct PetInventoryCategoryAccumulator {"
        ) else {
            fatalError("pet homepage pricing or inventory valuation source is missing")
        }

        guard let brandPosition = sharedRow.range(of: "Text(brandName)")?.lowerBound,
              let separatorPosition = sharedRow.range(of: "Text(\"·\")")?.lowerBound,
              let pricePosition = sharedRow.range(of: "Text(averagePriceText ?? \"—\")")?.lowerBound,
              let namePosition = sharedRow.range(of: "Text(item.name)")?.lowerBound,
              let expirationPosition = sharedRow.range(of: "if let expirationText {")?.lowerBound,
              let ratingPosition = sharedRow.range(of: "if let rating = store.petProductRating")?.lowerBound,
              let specificationPosition = sharedRow.range(of: "Text(specificationAndStock)")?.lowerBound else {
            fatalError("homepage price, item name, specification or rating source is missing")
        }
        let sharedRowUseCount = listSource.components(separatedBy: "PetProductListRowContent(item: item)").count - 1
        expect(sharedRowUseCount == 3 && homeRow.contains("PetProductListRowContent(item: item)"), "main, pending-repurchase and no-repurchase product rows share one presentation component")
        expect(sharedRow.contains("store.petWeightedAverageInboundUnitPrice(for: item.id)") && sharedRow.contains("PetItemHomepageAveragePrice.text") && sharedRow.contains("store.petInventoryEarliestExpirationDate(for: item.id)"), "shared rows use the live weighted price and earliest remaining batch expiry")
        expect(brandPosition < separatorPosition && separatorPosition < pricePosition && pricePosition < namePosition && namePosition < expirationPosition, "shared rows place price beside brand, followed by product name and optional expiry")
        expect(sharedRow.contains("size: 14, weight: .medium") && sharedRow.contains("Text(averagePriceText ?? \"—\")") && sharedRow.contains("font(.system(size: 12))") && sharedRow.contains("HomeTheme.muted"), "brand and unitless one-decimal price use the requested 14 and 12 point styles")
        expect(sharedRow.contains("HStack(alignment: .firstTextBaseline, spacing: 3)") && sharedRow.contains("Image(systemName: \"star.fill\")") && sharedRow.contains("Text(\"未评分\")") && ratingPosition < specificationPosition && sharedRow.contains(".frame(width: 100, alignment: .trailing)"), "rating and specification share the right column on the first two information lines")
        expect(sharedRow.contains("if let expirationText {") && sharedRow.contains(".map(petExpirationDisplayDate)") && !sharedRow.contains("?? \"未设日期\"") && sharedRow.contains(".frame(maxWidth: .infinity, minHeight: 64"), "only dated remaining stock gets a third line while equal-size thumbnails keep a consistent row height")
        expect(sharedRow.contains("Text(item.name)") && sharedRow.contains("size: 13, weight: .semibold") && sharedRow.contains("Text(flavor)") && sharedRow.contains("font(.system(size: 13))") && sharedRow.contains(".lineLimit(1)") && !sharedRow.contains("minimumScaleFactor"), "name and flavor keep separate 13 point styles without shrinking ordinary content")
        expect(listSource.contains(".frame(width: 64, height: 64)") && listSource.contains(".clipShape(RoundedRectangle(cornerRadius: 12"), "shared product rows use the 64 point rounded thumbnail")
        expect(averagePriceMethod.contains("data.petInventoryTransactions") && averagePriceMethod.contains("PetInventoryCosting.weightedAverageInboundUnitPrice(events)"), "weighted prices are recomputed from current transaction data")
        let metricCalls = overview.components(separatedBy: "overviewMetric(").count - 1
        guard let metric = sourceSlice(
            statisticsSource,
            from: "    private func overviewMetric(",
            to: "    private func categoryCard(_ category: PetInventoryCategorySummary) -> some View {"
        ), let netContent = sourceSlice(
            statisticsSource,
            from: "    private var netContent: String {",
            to: "}\n}\n\nprivate struct PetInventoryStatisticsSnapshot"
        ) else {
            fatalError("inventory overview metric or net-content source is missing")
        }
        expect(metricCalls == 3 && overview.components(separatedBy: "Divider().frame(height: 82)").count - 1 == 2, "inventory overview keeps exactly three columns on one row with separators")
        expect(metric.contains(".frame(maxWidth: .infinity)") && metric.contains(".lineLimit(1)") && metric.contains(".minimumScaleFactor(0.58)"), "all overview metric columns share width and keep titles and values on one line")
        expect(overview.contains("snapshot.valuation.title") && overview.contains("snapshot.valuation.wholeAmountText") && !overview.contains("按当前库存数量") && !overview.contains("detailText"), "the valuation shares the overview row without adding an explanatory row")
        expect(overview.contains("PetInventoryValuation.integerText(snapshot.totalQuantity)") && netContent.contains("mass(snapshot.totalMassGrams)") && netContent.contains("volume(snapshot.totalVolumeMilliliters)") && statisticsSource.contains("PetInventoryValuation.integerText(scaled)"), "quantity and net-content overview values use integer-only display formatting")
        expect(valuationSource.contains("\"库存估值\"") && valuationSource.contains("\"已计价小计\"") && valuationSource.contains("未计价商品"), "partial valuation is distinguished in its accessible summary without a visible note row")
        expect(snapshot.contains("store.petInventory(for: item.id)") && snapshot.contains("store.petWeightedAverageInboundUnitPrice(for: item.id)") && snapshot.contains("PetInventoryValuation.summarize"), "statistics estimate current stock against live weighted inbound prices")
        expect(petHomeSource.contains("PetInventoryStatisticsView(capabilityKey: \"petFood\")") && petHomeSource.contains("PetInventoryStatisticsView(capabilityKey: \"petSupply\")"), "food and supply count buttons use their root-specific statistics destinations")
    }

    private static func petExpiryPresentationContracts() throws {
        let itemsSource = try String(contentsOfFile: "HomeOSNative/Views/PetItemViews.swift", encoding: .utf8)
        let inventorySource = try String(contentsOfFile: "HomeOSNative/Views/PetInventoryViews.swift", encoding: .utf8)
        let litterSource = try String(contentsOfFile: "HomeOSNative/Views/LitterViews.swift", encoding: .utf8)
        let storeSource = try String(contentsOfFile: "HomeOSNative/Data/HomeStore.swift", encoding: .utf8)
        let costingSource = try String(contentsOfFile: "HomeOSNative/Data/PetInventoryCosting.swift", encoding: .utf8)
        let uiTests = try String(contentsOfFile: "UITests/PetExpiryPresentationUITests.swift", encoding: .utf8)
        let homeSource = try String(contentsOfFile: "HomeOSNative/Views/HomeView.swift", encoding: .utf8)
        let storedImageSource = try String(contentsOfFile: "HomeOSNative/Views/PetEventViews.swift", encoding: .utf8)
        guard let pending = sourceSlice(itemsSource, from: "struct PetPendingRepurchaseView: View", to: "struct PetNoRepurchaseLibraryView: View"),
              let transactionEditor = sourceSlice(inventorySource, from: "struct PetInventoryTransactionEditorView: View", to: "struct PetProductReviewEditorView: View"),
              let initialEditor = sourceSlice(inventorySource, from: "struct PetItemEditorView: View", to: "private enum PetItemEditorField"),
              let balanceEditor = sourceSlice(inventorySource, from: "struct PetInventoryBalanceEditDraft: Identifiable, Hashable", to: "struct PetItemEditorView: View"),
              let detail = sourceSlice(itemsSource, from: "struct PetItemDetailView: View", to: "func petExpirationDisplayDate"),
              let productListRow = sourceSlice(itemsSource, from: "private struct PetProductListRowContent: View", to: "private enum PetItemsRoute"),
              let expiryControl = sourceSlice(inventorySource, from: "struct PetExpirationDatePickerControl: View", to: "struct PetInventoryBalanceEditDraft: Identifiable, Hashable") else {
            fatalError("expiry presentation source sections are missing")
        }
        expect(itemsSource.contains("case .expiryNearest") && itemsSource.contains("保质期由近到远") && itemsSource.contains("@AppStorage(\"homeos.pet.items.sortMode\")"), "expiry sort uses the existing remembered sort selection")
        expect(itemsSource.contains("func expirySortsBefore") && itemsSource.contains("case (.some(_), .none): return true") && itemsSource.contains("return left.id < right.id"), "earlier dated stock sorts first, no-date stock last, and ties remain stable")
        expect(itemsSource.contains("store.petInventoryBatchGroups(for: itemID)") && inventorySource.contains("quantityText = group.remainingQuantity.formatted(.number.grouping(.never).precision(.fractionLength(0...8)))"), "product detail preloads each positive remaining expiry group with its current quantity")
        expect(initialEditor.contains("PetExpirationDateRow(selectedDate: $initialExpirationDate)") && initialEditor.contains("initialStock > 0") && initialEditor.contains("initialExpirationDate.map(LitterPredictionService.format)"), "new products have a persistent optional expiry row and only positive opening stock creates a batch")
        expect(!inventorySource.contains("initialHasExpiration") && !itemsSource.contains("quickHasExpiration"), "expiry entry uses a selected date instead of an enable switch")
        expect(itemsSource.contains("PetExpirationDateRow(selectedDate: $quickExpirationDate)") && itemsSource.contains("quickExpirationDate.map(LitterPredictionService.format)"), "quick inbound uses the persistent expiry row")
        expect(inventorySource.contains("PetExpirationDateRow(selectedDate: $expirationDate)") && inventorySource.contains("expirationDate: mode == .inbound"), "full inbound records the selected expiry on its source batch")
        expect(expiryControl.contains("DatePicker(\"保质期\", selection: selection, displayedComponents: .date)") && expiryControl.contains(".datePickerStyle(.compact)") && expiryControl.contains("if selectedDate != nil || isChoosingDate") && expiryControl.contains("Button(emptyValue)") && expiryControl.contains("Button(\"今天\")"), "expiry keeps the compact native picker behind a separate unset entry and offers an explicit today choice")
        expect(!expiryControl.contains("Text(emptyValue)") && !expiryControl.contains("ZStack") && !expiryControl.contains("allowsHitTesting(false)") && !expiryControl.contains("overlay"), "an unset row never covers a visible fallback date with placeholder text")
        expect(expiryControl.contains("selectedDate = nil") && expiryControl.contains("selectedDate ?? temporaryDate"), "opening the picker does not persist its temporary date; clear and cancel remain available")
        expect(!inventorySource.contains("PetExpirationDatePickerSheet") && !inventorySource.contains(".datePickerStyle(.graphical)"), "expiry no longer uses a custom graphical picker sheet")
        expect(balanceEditor.contains("summaryDates.count > 1") && balanceEditor.contains("\\(summaryDates.count)条") && balanceEditor.contains("TextField(\"0\", text: row.quantityText)") && balanceEditor.contains("＋增加日期") && balanceEditor.contains("enteredTotal <= currentInventory") && balanceEditor.contains("保持未设日期"), "balance rows collapse in place, expose editable quantities, constrain totals, and keep any remainder undated")
        expect(initialEditor.contains("PetInventoryBalanceRowsEditor(") && initialEditor.contains("balanceRows = groups.map(PetInventoryBalanceEditDraft.init(group:))") && initialEditor.contains("store.savePetItem("), "item editing prefills each live date group and saves product fields with date edits")
        expect(detail.contains("balanceExpiryCard(item)") && detail.contains("priceCard(item)") && !detail.contains("保存保质期") && itemsSource.contains("private struct PetInventoryBalanceEditorSheet") && itemsSource.contains("case .balanceEdit"), "product detail shows a standalone read-only expiry card above price history and opens one editor sheet")
        expect(itemsSource.contains("showsSummaryHeader: false") && itemsSource.contains("store.updatePetInventoryBalanceDates(productID: productID, edits: balanceDateEdits)"), "detail expiry editing reuses the shared date/quantity rows and persists through the existing ledger mapping")
        expect(!itemsSource.contains("PetInventoryBalanceManagerView") && !inventorySource.contains("PetInventoryBalanceManagerView") && !inventorySource.contains("拆分日期") && !inventorySource.contains("调整库存日期"), "the nested balance manager and split-date flow are removed")
        expect(storeSource.contains("func appendPetInventoryBalanceEdits(") && storeSource.contains("petInventoryBalanceAllocations.append(contentsOf: additions)") && costingSource.contains("static func editedBalanceAllocations(") && costingSource.contains("sourceAvailableBefore: available"), "date edits persist as replayable balance mappings and preserve transaction records")
        expect(productListRow.contains("PetItemHomepageAveragePrice.text(") && productListRow.contains("store.petInventoryEarliestExpirationDate(for: item.id)") && productListRow.contains("Text(specificationAndStock)") && productListRow.contains("minHeight: 64") && itemsSource.contains("frame(width: 64, height: 64)") && itemsSource.contains("cornerRadius: 12") && itemsSource.contains("contentMode: .fit") && storedImageSource.contains("aspectRatio(contentMode: contentMode)"), "product rows use a 64-point full-image thumbnail with preserved source aspect ratio")
        expect(productListRow.contains("size: 14, weight: .medium") && productListRow.contains("size: 13, weight: .semibold") && productListRow.contains("frame(width: 100, alignment: .trailing)") && itemsSource.contains("PetProductThumbnail(item: item)"), "the larger thumbnail keeps the approved text sizes and rating/specification column")
        expect(homeSource.contains("PetProductThumbnail(item: item)"), "the home stock library shares the same thumbnail sizing and fit mode")
        expect(uiTests.contains("app.datePickers.count, 0") && uiTests.contains("XCTAttachment(screenshot: XCUIScreen.main.screenshot())") && uiTests.contains("保质期设为今天"), "iPhone Simulator UI checks capture the unset date state and exercise explicit today selection")
        expect(uiTests.contains("testMultipleExpiryGroupsExpandAndDateRowsOpenTheEditor") && uiTests.contains("2027.03.01") && uiTests.contains("2027.08.08"), "iPhone Simulator UI checks collapse/expand multiple expiry rows and open editing from a date")
        expect(uiTests.contains("testProductRowsFitLongFlavorAndKeepDatesOnTheirOwnLine") && uiTests.contains("thumbnail.frame.width.rounded(), 64") && uiTests.contains("鸡肉三文鱼蔓越莓") && uiTests.contains("185g × 2罐"), "iPhone Simulator UI checks long flavor, missing rating/date, and three-line expiry row sizing")
        expect(productListRow.contains("accessibilitySummary") && productListRow.contains("if let expirationText { parts.append(\"保质期 \\(expirationText)\") }"), "list row accessibility preserves product, rating, stock, and optional expiry details for layout checks")
        expect(transactionEditor.contains("transaction.expirationDate.map(petExpirationDisplayDate)") && transactionEditor.contains("updateExpirationDate: transaction?.type == .inbound && transaction?.tracksExpirationBatch == true") && transactionEditor.contains("无法单独修改到期日期"), "inbound transaction detail edits tracked expiry batches and explains uncertain legacy batches")
        expect(inventorySource.contains("PetInventoryBatchAllocationSheet") && transactionEditor.contains("excludingTransactionID: transaction.id"), "editing an outbound restores its old allocations before choosing replacements")
        expect(litterSource.contains("PetInventoryBatchAllocationSheet") && storeSource.contains("batchAllocationsByProduct[allocation.productID]"), "cat litter consumption records its batch allocations through the shared ledger")
        expect(pending.contains("ForEach(primaryCategories)") && pending.contains("ForEach(secondaryCategories)") && pending.contains("PetProductListRowContent(item: item)") && itemsSource.contains("if let expirationText {") && itemsSource.contains("PetItemHomepageAveragePrice.text"), "pending repurchase remains split by live categories and uses the shared optional-expiry product layout")
        expect(storeSource.contains("tracksExpirationBatch = !hasLaterUnattributedReduction") && storeSource.contains("tracksExpirationBatch == nil"), "legacy batch migration is one-time and leaves uncertain old balances unassigned")
    }

    private static func inventoryValuation() throws {
        let full = PetInventoryValuation.summarize([
            PetInventoryValuationInput(productID: "food", quantity: 3, weightedUnitPrice: 4.67),
            PetInventoryValuationInput(productID: "supply", quantity: 2, weightedUnitPrice: 10)
        ])
        expectClose(full.amount, 34.01, "inventory value multiplies on-hand quantity by weighted inbound unit price")
        expect(full.amountText == "¥34.01" && full.wholeAmountText == "¥34" && full.title == "库存估值" && !full.isIncomplete, "full valuation preserves raw precision and displays a whole-currency overview value")

        let partial = PetInventoryValuation.summarize([
            PetInventoryValuationInput(productID: "food", quantity: 3, weightedUnitPrice: 4.67),
            PetInventoryValuationInput(productID: "unpriced", quantity: 2, weightedUnitPrice: nil)
        ])
        expect(partial.amountText == "¥14.01" && partial.wholeAmountText == "¥14" && partial.title == "库存估值", "missing prices never appear as zero and overview values round only for display")
        expect(partial.unpricedProductCount == 1 && partial.detailText == "未计价商品 1 种", "partial estimates identify the number of unpriced products")
        expect(partial.accessibilityLabel.contains("已计价小计") && partial.accessibilityLabel.contains("未计价商品 1 种"), "partial valuations are announced as subtotals with the unpriced item count")

        let noPrices = PetInventoryValuation.summarize([
            PetInventoryValuationInput(productID: "unpriced", quantity: 2, weightedUnitPrice: nil)
        ])
        expect(noPrices.amountText == "—" && noPrices.wholeAmountText == "—" && noPrices.unpricedProductCount == 1, "an inventory with no valid prices does not display ¥0")
        expect(noPrices.accessibilityLabel.contains("已计价小计"), "an all-unpriced estimate is identified as an incomplete subtotal")

        let invalid = PetInventoryValuation.summarize([
            PetInventoryValuationInput(productID: "infinite-stock", quantity: .infinity, weightedUnitPrice: 2),
            PetInventoryValuationInput(productID: "overflow", quantity: 1e308, weightedUnitPrice: 1e308),
            PetInventoryValuationInput(productID: "unpriced", quantity: 1, weightedUnitPrice: .nan)
        ])
        expect(invalid.amount.isFinite && invalid.amountText == "—" && invalid.invalidProductCount == 3, "non-finite stock, price and multiplication are excluded safely")

        let sumOverflow = PetInventoryValuation.summarize([
            PetInventoryValuationInput(productID: "first", quantity: 1e308, weightedUnitPrice: 1),
            PetInventoryValuationInput(productID: "second", quantity: 1e308, weightedUnitPrice: 1)
        ])
        expect(sumOverflow.amount.isFinite && sumOverflow.invalidProductCount == 1 && sumOverflow.isIncomplete && sumOverflow.accessibilityLabel.contains("已计价小计"), "aggregate overflow is excluded and the remaining amount is marked partial")

        expect(PetInventoryValuation.currencyText(.infinity) == nil, "currency presentation rejects non-finite amounts")
        expect(PetInventoryValuation.integerText(246.5) == "247" && PetInventoryValuation.integerText(246.4) == "246", "overview quantities round to the nearest integer without changing source values")
        expect(PetInventoryValuation.integerText(.nan) == nil, "overview integer formatting rejects non-finite values")
        expect(PetInventoryValuation.currencyIntegerText(1_695.49) == "¥1,695" && PetInventoryValuation.currencyIntegerText(1_695.5) == "¥1,696", "overview currency rounds to whole dollars and keeps thousands separators")
        expect(PetInventoryValuation.currencyIntegerText(.infinity) == nil, "whole-currency formatting rejects non-finite values")
        let corrected = PetInventoryValuation.summarize([
            PetInventoryValuationInput(productID: "food", quantity: 3, weightedUnitPrice: 5)
        ])
        expect(corrected.amountText == "¥15.00" && corrected.amountText != full.amountText, "the summary reflects a corrected source price without a cached total")
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

    private static func balanceAllocation(
        _ id: String,
        source sourceBatchID: String,
        sourceAvailableBefore: Double,
        expiry expirationDate: String?,
        quantity: Double,
        date effectiveDate: String,
        createdAt: Double
    ) -> PetInventoryBalanceAllocation {
        PetInventoryBalanceAllocation(
            id: id,
            productID: "product",
            sourceBatchID: sourceBatchID,
            sourceAvailableBefore: sourceAvailableBefore,
            expirationDate: expirationDate,
            quantity: quantity,
            effectiveDate: effectiveDate,
            createdAt: createdAt
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
