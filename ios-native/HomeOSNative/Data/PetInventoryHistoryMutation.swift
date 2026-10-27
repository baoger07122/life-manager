import Foundation

enum PetInventoryHistoryMutation {
    enum Failure: Error {
        case transactionNotFound
        case litterOperationMustBeChangedAsAGroup
        case adjustmentIsReadOnly
        case ambiguousActivityMatch
        case batchAllocationSourceInUse
        case batchExpirationNotTrackable
        case invalidQuantity
        case invalidPrice
    }

    struct DeletionResult {
        var backup: HomeBackup
        var deletedTransaction: PetInventoryTransaction
    }

    static func update(
        transactionID: String,
        quantity: Double,
        occurrenceDate: String,
        totalPrice: Double?,
        note: String?,
        expirationDate: String? = nil,
        updateExpirationDate: Bool = false,
        batchAllocations: [PetInventoryBatchAllocation]? = nil,
        now: Double,
        in source: HomeBackup
    ) throws -> HomeBackup {
        var next = source
        guard let transactionIndex = next.petInventoryTransactions.firstIndex(where: { $0.id == transactionID }) else {
            throw Failure.transactionNotFound
        }
        let original = next.petInventoryTransactions[transactionIndex]
        guard original.type != .adjustment else { throw Failure.adjustmentIsReadOnly }
        guard !isLitterLinked(original) else { throw Failure.litterOperationMustBeChangedAsAGroup }
        if updateExpirationDate, original.type == .inbound, original.tracksExpirationBatch != true {
            throw Failure.batchExpirationNotTrackable
        }
        let activityMatch = matchingActivities(for: original, in: source.activities)
        if case .ambiguous = activityMatch { throw Failure.ambiguousActivityMatch }
        guard quantity.isFinite, quantity > 0 else { throw Failure.invalidQuantity }
        if let totalPrice, (!totalPrice.isFinite || totalPrice < 0) { throw Failure.invalidPrice }

        let signedQuantity = original.type == .outbound ? -quantity : quantity
        let historyChanged = signedQuantity != original.quantityChange || occurrenceDate != original.occurrenceDate
        next.petInventoryTransactions[transactionIndex].quantityChange = signedQuantity
        next.petInventoryTransactions[transactionIndex].occurrenceDate = occurrenceDate
        next.petInventoryTransactions[transactionIndex].updatedAt = now

        if original.type == .inbound {
            next.petInventoryTransactions[transactionIndex].totalPrice = totalPrice
            next.petInventoryTransactions[transactionIndex].unitPrice = totalPrice.flatMap { $0 > 0 ? $0 / quantity : nil }
            if updateExpirationDate {
                next.petInventoryTransactions[transactionIndex].expirationDate = expirationDate
            }
        } else {
            next.petInventoryTransactions[transactionIndex].batchAllocations = batchAllocations
        }
        if let note {
            let cleaned = note.trimmingCharacters(in: .whitespacesAndNewlines)
            next.petInventoryTransactions[transactionIndex].note = cleaned.isEmpty ? nil : cleaned
        }

        try replayProduct(
            productID: original.productID,
            in: &next,
            now: now,
            allowInvalidHistory: !historyChanged,
            synchronizeMatchingActivities: false
        )

        for other in next.petInventoryTransactions where other.productID == original.productID && other.id != original.id {
            synchronizeActivity(for: other, in: &next)
        }
        if case .indices(let indices) = activityMatch,
           let updated = next.petInventoryTransactions.first(where: { $0.id == original.id }) {
            updateActivities(at: indices, for: updated, in: &next)
        }

        guard let itemIndex = next.petItems.firstIndex(where: { $0.id == original.productID }) else { return next }
        let updatedTransaction = next.petInventoryTransactions[transactionIndex]
        let shouldUpdatePriceCache = original.type == .inbound
            && (original.recordedInboundTotalPrice != updatedTransaction.recordedInboundTotalPrice
                || original.quantityChange != updatedTransaction.quantityChange
                || original.occurrenceDate != updatedTransaction.occurrenceDate)
        if shouldUpdatePriceCache {
            next.petItems[itemIndex].price = latestRecordedInboundUnitPrice(for: original.productID, in: next)
        }
        next.petItems[itemIndex].updatedAt = now
        return next
    }

    static func delete(transactionID: String, from source: HomeBackup, now: Double) throws -> DeletionResult {
        guard let transactionIndex = source.petInventoryTransactions.firstIndex(where: { $0.id == transactionID }) else {
            throw Failure.transactionNotFound
        }
        let removed = source.petInventoryTransactions[transactionIndex]
        guard !isLitterLinked(removed) else { throw Failure.litterOperationMustBeChangedAsAGroup }
        if removed.type == .inbound && (
           source.petInventoryTransactions.contains(where: {
               $0.batchAllocations?.contains(where: {
                   $0.sourceBatchID == removed.id && $0.quantity > 0
               }) == true
           }) || source.petInventoryBalanceAllocations.contains(where: {
               $0.productID == removed.productID && $0.sourceBatchID == removed.id
           })) {
            throw Failure.batchAllocationSourceInUse
        }

        let activityMatch = matchingActivities(for: removed, in: source.activities)
        if case .ambiguous = activityMatch { throw Failure.ambiguousActivityMatch }

        var next = source
        next.petInventoryTransactions.remove(at: transactionIndex)
        removeLegacyPurchaseRecord(for: removed, from: &next)
        switch activityMatch {
        case .none, .ambiguous:
            break
        case .indices(let indices):
            let removedIndices = Set(indices)
            next.activities = next.activities.enumerated()
                .filter { !removedIndices.contains($0.offset) }
                .map(\.element)
        }

        try replayProduct(productID: removed.productID, in: &next, now: now)
        if let itemIndex = next.petItems.firstIndex(where: { $0.id == removed.productID }) {
            let latestPrice = latestRecordedInboundUnitPrice(for: removed.productID, in: next)
            if next.petItems[itemIndex].price != latestPrice {
                next.petItems[itemIndex].price = latestPrice
            }
            next.petItems[itemIndex].updatedAt = now
        }
        return DeletionResult(backup: next, deletedTransaction: removed)
    }

    static func replayProduct(
        productID: String,
        in backup: inout HomeBackup,
        now: Double,
        allowInvalidHistory: Bool = false,
        synchronizeMatchingActivities: Bool = true
    ) throws {
        let indices = backup.petInventoryTransactions.indices.filter {
            backup.petInventoryTransactions[$0].productID == productID
        }
        guard !indices.isEmpty else {
            if let itemIndex = backup.petItems.firstIndex(where: { $0.id == productID }) {
                if backup.petItems[itemIndex].quantity != 0 {
                    backup.petItems[itemIndex].quantity = 0
                    backup.petItems[itemIndex].updatedAt = now
                }
            }
            _ = try PetInventoryBatchLedger.balances(
                productID: productID,
                transactions: backup.petInventoryTransactions,
                balanceAllocations: backup.petInventoryBalanceAllocations
            )
            return
        }

        let events = indices.map { costEvent(backup.petInventoryTransactions[$0]) }
        do {
            let replay = try PetInventoryCosting.replay(events)
            for (index, result) in zip(indices, replay.events) {
                var transaction = backup.petInventoryTransactions[index]
                let derivedValuesChanged = transaction.quantityChange != result.quantityChange
                    || transaction.quantityBefore != result.quantityBefore
                    || transaction.quantityAfter != result.quantityAfter
                    || transaction.totalPrice != result.totalPrice
                    || transaction.unitPrice != result.unitPrice
                transaction.quantityChange = result.quantityChange
                transaction.quantityBefore = result.quantityBefore
                transaction.quantityAfter = result.quantityAfter
                if transaction.type == .outbound {
                    transaction.totalPrice = result.totalPrice
                    transaction.unitPrice = result.unitPrice
                }
                if derivedValuesChanged { transaction.updatedAt = now }
                backup.petInventoryTransactions[index] = transaction
            }
            if let itemIndex = backup.petItems.firstIndex(where: { $0.id == productID }) {
                if backup.petItems[itemIndex].quantity != replay.currentQuantity {
                    backup.petItems[itemIndex].quantity = replay.currentQuantity
                    backup.petItems[itemIndex].updatedAt = now
                }
            }
            _ = try PetInventoryBatchLedger.balances(
                productID: productID,
                transactions: backup.petInventoryTransactions,
                balanceAllocations: backup.petInventoryBalanceAllocations
            )
            if synchronizeMatchingActivities { synchronizeActivities(for: productID, in: &backup) }
        } catch let error as PetInventoryCosting.InvalidHistory {
            guard allowInvalidHistory else { throw error }
            for index in indices where backup.petInventoryTransactions[index].type == .outbound {
                if backup.petInventoryTransactions[index].totalPrice != nil
                    || backup.petInventoryTransactions[index].unitPrice != nil {
                    backup.petInventoryTransactions[index].totalPrice = nil
                    backup.petInventoryTransactions[index].unitPrice = nil
                    backup.petInventoryTransactions[index].updatedAt = now
                }
            }
            if synchronizeMatchingActivities { synchronizeActivities(for: productID, in: &backup) }
        }
    }

    static func latestRecordedInboundUnitPrice(for productID: String, in backup: HomeBackup) -> Double? {
        backup.petInventoryTransactions.enumerated()
            .filter { $0.element.productID == productID && $0.element.type == .inbound }
            .sorted { left, right in
                if left.element.occurrenceDate != right.element.occurrenceDate {
                    return left.element.occurrenceDate > right.element.occurrenceDate
                }
                if left.element.createdAt != right.element.createdAt {
                    return left.element.createdAt > right.element.createdAt
                }
                return left.offset > right.offset
            }
            .compactMap { $0.element.recordedInboundUnitPrice }
            .first
    }

    static func synchronizeActivities(for productID: String, in backup: inout HomeBackup) {
        for transaction in backup.petInventoryTransactions where transaction.productID == productID {
            synchronizeActivity(for: transaction, in: &backup)
        }
    }

    private static func synchronizeActivity(for transaction: PetInventoryTransaction, in backup: inout HomeBackup) {
        guard case .indices(let indices) = matchingActivities(for: transaction, in: backup.activities) else { return }
        updateActivities(at: indices, for: transaction, in: &backup)
    }

    private static func updateActivities(at indices: [Int], for transaction: PetInventoryTransaction, in backup: inout HomeBackup) {
        let amount: Double?
        switch transaction.type {
        case .inbound: amount = transaction.recordedInboundTotalPrice
        case .outbound: amount = transaction.recordedOutboundTotalPrice
        case .adjustment: amount = nil
        }
        for activityIndex in indices where backup.activities.indices.contains(activityIndex) {
            backup.activities[activityIndex].quantity = abs(transaction.quantityChange)
            backup.activities[activityIndex].unit = transaction.unit
            backup.activities[activityIndex].totalPrice = amount
            backup.activities[activityIndex].time = activityDateText(transaction.occurrenceDate)
            backup.activities[activityIndex].occurredAt = transaction.createdAt
        }
    }

    private enum ActivityMatch {
        case none
        case indices([Int])
        case ambiguous
    }

    private static func matchingActivities(for transaction: PetInventoryTransaction, in activities: [ActivityItem]) -> ActivityMatch {
        let deterministicID = "pet-inventory-\(transaction.id)"
        let exact = activities.indices.filter { activities[$0].id == deterministicID }
        if !exact.isEmpty { return .indices(exact) }

        let action: String
        switch transaction.type {
        case .inbound: action = "入库"
        case .outbound: action = "出库"
        case .adjustment: action = "修正"
        }
        let expectedDate = activityDateText(transaction.occurrenceDate)
        let expectedQuantity = abs(transaction.quantityChange)
        let candidates = activities.indices.filter { index in
            let activity = activities[index]
            guard activity.type == "pet",
                  activity.targetId == transaction.productID,
                  activity.action == action,
                  activity.unit == transaction.unit,
                  activity.time == expectedDate,
                  let quantity = activity.quantity,
                  abs(quantity - expectedQuantity) < 0.000_001 else { return false }
            if let occurredAt = activity.occurredAt {
                return abs(occurredAt - transaction.createdAt) < 1
            }
            return true
        }
        guard !candidates.isEmpty else { return .none }
        guard candidates.count > 1 else { return .indices(candidates) }

        // Old records may lack deterministic IDs. Only use the timestamp to break a
        // strict tie when every candidate has timing data and one is uniquely nearest.
        guard candidates.allSatisfy({ activities[$0].occurredAt != nil }) else { return .ambiguous }
        let distances = candidates.map { abs((activities[$0].occurredAt ?? 0) - transaction.createdAt) }
        guard let minimum = distances.min() else { return .ambiguous }
        let nearest = zip(candidates, distances).filter { abs($0.1 - minimum) < 0.000_001 }.map(\.0)
        return nearest.count == 1 ? .indices(nearest) : .ambiguous
    }

    private static func isLitterLinked(_ transaction: PetInventoryTransaction) -> Bool {
        transaction.linkedOperationID != nil
            || transaction.source == .litterRefill
            || transaction.source == .litterReplace
    }

    private static func removeLegacyPurchaseRecord(for transaction: PetInventoryTransaction, from backup: inout HomeBackup) {
        guard transaction.source == .migration,
              transaction.type == .inbound,
              let itemIndex = backup.petItems.firstIndex(where: { $0.id == transaction.productID }) else { return }
        let prefix = "legacy-purchase-\(transaction.productID)-"
        guard transaction.id.hasPrefix(prefix) else { return }
        let purchaseID = String(transaction.id.dropFirst(prefix.count))
        guard !purchaseID.isEmpty else { return }

        let expectedTotal = transaction.totalPrice
            ?? transaction.unitPrice.map { $0 * transaction.quantityChange }
            ?? 0
        func matches(_ purchase: PetPurchaseRecord) -> Bool {
            purchase.id == purchaseID
                && purchase.date == transaction.occurrenceDate
                && abs(purchase.quantity - transaction.quantityChange) < 0.000_001
                && abs(purchase.price - expectedTotal) < 0.000_001
        }

        if let history = backup.petItems[itemIndex].purchaseHistory {
            backup.petItems[itemIndex].purchaseHistory = history.filter { !matches($0) }
        }
        if let history = backup.petItems[itemIndex].replenishmentHistory {
            backup.petItems[itemIndex].replenishmentHistory = history.filter { !matches($0) }
        }
    }

    private static func costEvent(_ transaction: PetInventoryTransaction) -> PetInventoryCosting.Event {
        let kind: PetInventoryCosting.Kind
        switch transaction.type {
        case .inbound: kind = .inbound
        case .outbound: kind = .outbound
        case .adjustment: kind = .adjustment
        }
        return PetInventoryCosting.Event(
            id: transaction.id,
            kind: kind,
            occurrenceDate: transaction.occurrenceDate,
            createdAt: transaction.createdAt,
            quantityChange: transaction.quantityChange,
            quantityBefore: transaction.quantityBefore,
            quantityAfter: transaction.quantityAfter,
            totalPrice: transaction.totalPrice,
            unitPrice: transaction.unitPrice
        )
    }

    private static func activityDateText(_ storedDate: String) -> String {
        let storage = DateFormatter()
        storage.locale = Locale(identifier: "zh_CN")
        storage.calendar = Calendar(identifier: .gregorian)
        storage.dateFormat = "yyyy-MM-dd"
        let date = storage.date(from: storedDate) ?? Date()
        let display = DateFormatter()
        display.locale = Locale(identifier: "zh_CN")
        display.calendar = Calendar(identifier: .gregorian)
        display.dateFormat = "yyyy年M月d日"
        return display.string(from: date)
    }
}
