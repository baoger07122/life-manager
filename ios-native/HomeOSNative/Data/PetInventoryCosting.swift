import Foundation

struct PetInventoryBatchBalance: Identifiable, Hashable {
    var id: String
    var expirationDate: String?
    var remainingQuantity: Double
    var occurrenceDate: String
    var createdAt: Double
    var isUnassigned: Bool = false
}

struct PetInventoryExpiryGroup: Identifiable, Hashable {
    var id: String
    var expirationDate: String?
    var remainingQuantity: Double
    var batches: [PetInventoryBatchBalance]
}

struct PetInventoryBatchAllocationRequest: Identifiable, Hashable {
    var productID: String
    var productName: String
    var quantity: Double
    var unit: String
    var groups: [PetInventoryExpiryGroup]

    var id: String { productID }
}

enum PetInventoryBatchLedger {
    static let unassignedGroupID = "__no_expiration__"
    private static let tolerance = 0.000_001

    private enum EventPayload {
        case transaction(PetInventoryTransaction)
        case balanceAllocation(PetInventoryBalanceAllocation)
    }

    private struct TimelineEvent {
        var occurrenceDate: String
        var createdAt: Double
        var order: Int
        var payload: EventPayload
    }

    private struct BatchMetadata {
        var expirationDate: String?
        var occurrenceDate: String
        var createdAt: Double
    }

    struct InvalidLedger: Error, Equatable {
        var message: String
    }

    static func balances(
        productID: String,
        transactions: [PetInventoryTransaction],
        balanceAllocations: [PetInventoryBalanceAllocation] = [],
        excludingTransactionID: String? = nil
    ) throws -> [PetInventoryBatchBalance] {
        let records = transactions.filter {
            $0.productID == productID && $0.id != excludingTransactionID
        }
        let mappings = balanceAllocations.filter { $0.productID == productID }
        let total = records.reduce(0) { $0 + $1.quantityChange }
        guard total.isFinite, total >= -tolerance else {
            throw InvalidLedger(message: "库存批次与当前总库存不一致，请先检查库存流水。")
        }

        let transactionIDs = Set(records.map(\.id))
        guard transactionIDs.count == records.count,
              mappings.allSatisfy({ !transactionIDs.contains($0.id) }),
              Set(mappings.map(\.id)).count == mappings.count else {
            throw InvalidLedger(message: "库存批次来源标识重复，未修改库存。")
        }

        for mapping in mappings {
            guard mapping.quantity.isFinite, mapping.quantity > 0,
                  mapping.sourceAvailableBefore.isFinite,
                  mapping.sourceAvailableBefore >= mapping.quantity,
                  validExpirationDate(mapping.effectiveDate) != nil,
                  mapping.createdAt.isFinite,
                  mapping.expirationDate == nil || validExpirationDate(mapping.expirationDate) != nil else {
                throw InvalidLedger(message: "库存日期分配记录无效，未修改库存。")
            }
        }

        var remainingByBatch: [String: Double] = [:]
        var batchMetadataByID: [String: BatchMetadata] = [:]
        var batchIDsInCreationOrder: [String] = []
        var unassignedRemaining = 0.0
        let timeline = records.enumerated().map { offset, record in
            TimelineEvent(
                occurrenceDate: record.occurrenceDate,
                createdAt: record.createdAt,
                order: offset,
                payload: .transaction(record)
            )
        } + mappings.enumerated().map { offset, mapping in
            TimelineEvent(
                occurrenceDate: mapping.effectiveDate,
                createdAt: mapping.createdAt,
                order: records.count + offset,
                payload: .balanceAllocation(mapping)
            )
        }
        let orderedEvents = timeline.sorted { left, right in
            if left.occurrenceDate != right.occurrenceDate { return left.occurrenceDate < right.occurrenceDate }
            if left.createdAt != right.createdAt { return left.createdAt < right.createdAt }
            return left.order < right.order
        }

        for event in orderedEvents {
            if case .balanceAllocation(let mapping) = event.payload {
                let sourceID = mapping.sourceBatchID
                if sourceID == unassignedBatchID(for: productID) {
                    guard unassignedRemaining + tolerance >= mapping.sourceAvailableBefore else {
                        throw InvalidLedger(message: "日期分配超过当前未设日期库存，请检查库存流水和日期分配。")
                    }
                    unassignedRemaining = max(0, unassignedRemaining - mapping.quantity)
                } else {
                    guard let available = remainingByBatch[sourceID], batchMetadataByID[sourceID] != nil else {
                        throw InvalidLedger(message: "日期分配引用了尚不存在或已用完的库存批次。")
                    }
                    guard available + tolerance >= mapping.sourceAvailableBefore else {
                        throw InvalidLedger(message: "日期分配超过来源批次的当前余量。")
                    }
                    remainingByBatch[sourceID] = max(0, available - mapping.quantity)
                }

                guard remainingByBatch[mapping.id] == nil else {
                    throw InvalidLedger(message: "库存批次来源标识重复，未修改库存。")
                }
                remainingByBatch[mapping.id] = mapping.quantity
                batchMetadataByID[mapping.id] = BatchMetadata(
                    expirationDate: mapping.expirationDate,
                    occurrenceDate: mapping.effectiveDate,
                    createdAt: mapping.createdAt
                )
                batchIDsInCreationOrder.append(mapping.id)
                continue
            }

            guard case .transaction(let record) = event.payload else { continue }
            guard record.quantityChange.isFinite else {
                throw InvalidLedger(message: "库存流水数量无效，未修改库存。")
            }

            if record.type == .inbound {
                guard record.quantityChange > 0 else {
                    throw InvalidLedger(message: "入库流水数量无效，未修改库存。")
                }
                if record.tracksExpirationBatch == true {
                    guard remainingByBatch[record.id] == nil else {
                        throw InvalidLedger(message: "库存批次来源标识重复，未修改库存。")
                    }
                    remainingByBatch[record.id, default: 0] += record.quantityChange
                    batchMetadataByID[record.id] = BatchMetadata(
                        expirationDate: record.expirationDate,
                        occurrenceDate: record.occurrenceDate,
                        createdAt: record.createdAt
                    )
                    batchIDsInCreationOrder.append(record.id)
                } else {
                    unassignedRemaining += record.quantityChange
                }
                continue
            }

            if record.type == .adjustment, record.quantityChange > 0 {
                guard record.batchAllocations?.isEmpty != false else {
                    throw InvalidLedger(message: "增加库存不能引用出库批次。")
                }
                unassignedRemaining += record.quantityChange
                continue
            }

            let requested: Double
            if record.type == .outbound {
                guard record.quantityChange < 0 else {
                    throw InvalidLedger(message: "出库流水数量无效，未修改库存。")
                }
                requested = abs(record.quantityChange)
            } else if record.type == .adjustment, record.quantityChange < 0 {
                requested = abs(record.quantityChange)
            } else {
                guard record.batchAllocations?.isEmpty != false else {
                    throw InvalidLedger(message: "库存批次分配只能用于减少库存的流水。")
                }
                continue
            }

            guard let allocations = record.batchAllocations else {
                guard unassignedRemaining + tolerance >= requested else {
                    throw InvalidLedger(message: "旧版出库无法与未设日期库存对应。为避免错记批次日期，请先检查历史流水。")
                }
                unassignedRemaining = max(0, unassignedRemaining - requested)
                continue
            }

            let allocated = allocations.reduce(0) { $0 + $1.quantity }
            guard allocations.allSatisfy({ $0.quantity.isFinite && $0.quantity > 0 }),
                  allocated.isFinite, abs(allocated - requested) < tolerance else {
                throw InvalidLedger(message: "各到期批次的分配数量必须等于本次出库数量。")
            }

            for allocation in allocations {
                let amount = allocation.quantity
                if allocation.sourceBatchID == unassignedBatchID(for: productID) {
                    guard unassignedRemaining + tolerance >= amount else {
                        throw InvalidLedger(message: "出库引用了尚不存在或已用完的未设日期库存。")
                    }
                    unassignedRemaining = max(0, unassignedRemaining - amount)
                } else {
                    guard batchMetadataByID[allocation.sourceBatchID] != nil,
                          let available = remainingByBatch[allocation.sourceBatchID] else {
                        throw InvalidLedger(message: "出库引用了尚未入库或不存在的批次。请检查流水日期和来源。")
                    }
                    guard available + tolerance >= amount else {
                        throw InvalidLedger(message: "某条出库超过了对应入库批次数量，请检查该条历史记录。")
                    }
                    remainingByBatch[allocation.sourceBatchID] = max(0, available - amount)
                }
            }
        }

        var result: [PetInventoryBatchBalance] = []
        var trackedRemaining = 0.0
        for batchID in batchIDsInCreationOrder {
            let remaining = remainingByBatch[batchID, default: 0]
            let normalized = abs(remaining) < tolerance ? 0 : remaining
            if normalized > 0 {
                trackedRemaining += normalized
                result.append(PetInventoryBatchBalance(
                    id: batchID,
                    expirationDate: validExpirationDate(batchMetadataByID[batchID]?.expirationDate),
                    remainingQuantity: normalized,
                    occurrenceDate: batchMetadataByID[batchID]?.occurrenceDate ?? "0000-00-00",
                    createdAt: batchMetadataByID[batchID]?.createdAt ?? 0
                ))
            }
        }

        let unassigned = abs(unassignedRemaining) < tolerance ? 0 : unassignedRemaining
        guard unassigned >= -tolerance,
              abs((trackedRemaining + unassigned) - total) < tolerance else {
            throw InvalidLedger(message: "可确认批次与当前总库存不一致，未修改库存。")
        }
        if unassigned > tolerance {
            result.append(PetInventoryBatchBalance(
                id: unassignedBatchID(for: productID),
                expirationDate: nil,
                remainingQuantity: unassigned,
                occurrenceDate: "9999-12-31",
                createdAt: .greatestFiniteMagnitude,
                isUnassigned: true
            ))
        }
        return result
    }

    static func groups(from balances: [PetInventoryBatchBalance]) -> [PetInventoryExpiryGroup] {
        let grouped = Dictionary(grouping: balances, by: { $0.expirationDate ?? unassignedGroupID })
        return grouped.map { key, batches in
            let expiry = batches.first?.expirationDate
            return PetInventoryExpiryGroup(
                id: key,
                expirationDate: expiry,
                remainingQuantity: batches.reduce(0) { $0 + $1.remainingQuantity },
                batches: batches.sorted(by: receiptOrder)
            )
        }.sorted { left, right in
            switch (left.expirationDate, right.expirationDate) {
            case let (.some(leftDate), .some(rightDate)):
                if leftDate != rightDate { return leftDate < rightDate }
                return left.id < right.id
            case (.some(_), .none): return true
            case (.none, .some(_)): return false
            case (.none, .none): return left.id < right.id
            }
        }
    }

    static func editedBalanceAllocations(
        productID: String,
        currentGroups: [PetInventoryExpiryGroup],
        edits: [PetInventoryBalanceEdit],
        effectiveDate: String,
        createdAt: Double
    ) throws -> [PetInventoryBalanceAllocation] {
        let tolerance = 0.000_001
        guard validExpirationDate(effectiveDate) != nil, createdAt.isFinite else {
            throw InvalidLedger(message: "保质期修改日期无效。")
        }
        guard Set(currentGroups.map(\.id)).count == currentGroups.count,
              Set(edits.map(\.id)).count == edits.count else {
            throw InvalidLedger(message: "保质期行标识重复，请重新打开后再试。")
        }
        guard edits.allSatisfy({
            $0.quantity.isFinite && $0.quantity >= 0
                && ($0.sourceGroupQuantity.map { $0.isFinite && $0 >= 0 } ?? true)
                && ($0.expirationDate == nil || validExpirationDate($0.expirationDate) != nil)
        }) else {
            throw InvalidLedger(message: "保质期日期或数量无效。")
        }

        let editsBySource = Dictionary(grouping: edits.compactMap { edit -> (String, PetInventoryBalanceEdit)? in
            guard let sourceGroupID = edit.sourceGroupID else { return nil }
            return (sourceGroupID, edit)
        }, by: \.0)
        let sourceIDs = Set(editsBySource.keys)
        let currentIDs = Set(currentGroups.map(\.id))
        guard sourceIDs == currentIDs,
              editsBySource.values.allSatisfy({ $0.count == 1 }) else {
            throw InvalidLedger(message: "库存日期分组已变化，请重新打开后再试。")
        }

        let currentTotal = currentGroups.reduce(0) { $0 + $1.remainingQuantity }
        let desiredTotal = edits.reduce(0) { $0 + $1.quantity }
        guard currentTotal.isFinite, desiredTotal.isFinite,
              currentGroups.allSatisfy({ $0.remainingQuantity.isFinite && $0.remainingQuantity > 0 }),
              desiredTotal <= currentTotal + tolerance else {
            throw InvalidLedger(message: "日期分组数量不能超过当前库存。")
        }

        var transfers: [(source: PetInventoryExpiryGroup, destination: String?, quantity: Double)] = []
        var surpluses: [(source: PetInventoryExpiryGroup, quantity: Double)] = []
        var deficits: [(destination: String?, quantity: Double)] = []

        for group in currentGroups {
            guard let edit = editsBySource[group.id]?.first?.1 else {
                throw InvalidLedger(message: "库存日期分组已变化，请重新打开后再试。")
            }
            if let sourceQuantity = edit.sourceGroupQuantity,
               abs(sourceQuantity - group.remainingQuantity) > tolerance {
                throw InvalidLedger(message: "库存日期数量已变化，请重新打开后再试。")
            }
            let retained = min(group.remainingQuantity, edit.quantity)
            if retained > tolerance, group.expirationDate != edit.expirationDate {
                transfers.append((group, edit.expirationDate, retained))
            }
            let surplus = group.remainingQuantity - retained
            if surplus > tolerance {
                surpluses.append((group, surplus))
            }
            let deficit = edit.quantity - retained
            if deficit > tolerance {
                deficits.append((edit.expirationDate, deficit))
            }
        }

        for edit in edits where edit.sourceGroupID == nil && edit.quantity > tolerance {
            deficits.append((edit.expirationDate, edit.quantity))
        }

        for deficit in deficits {
            var remaining = deficit.quantity
            for index in surpluses.indices where remaining > tolerance {
                let amount = min(remaining, surpluses[index].quantity)
                guard amount > 0 else { continue }
                transfers.append((surpluses[index].source, deficit.destination, amount))
                surpluses[index].quantity -= amount
                remaining -= amount
            }
            guard remaining <= tolerance else {
                throw InvalidLedger(message: "日期分组总量超过当前库存。")
            }
        }

        for surplus in surpluses where surplus.quantity > tolerance {
            transfers.append((surplus.source, nil, surplus.quantity))
        }

        var availableByBatch = Dictionary(uniqueKeysWithValues: currentGroups.flatMap { group in
            group.batches.map { ($0.id, $0.remainingQuantity) }
        })
        var allocations: [PetInventoryBalanceAllocation] = []
        for transfer in transfers where transfer.source.expirationDate != transfer.destination {
            var remaining = transfer.quantity
            for batch in transfer.source.batches where remaining > tolerance {
                let available = availableByBatch[batch.id, default: 0]
                let quantity = min(remaining, available)
                guard quantity > tolerance else { continue }
                allocations.append(PetInventoryBalanceAllocation(
                    id: UUID().uuidString,
                    productID: productID,
                    sourceBatchID: batch.id,
                    sourceAvailableBefore: available,
                    expirationDate: transfer.destination,
                    quantity: quantity,
                    effectiveDate: effectiveDate,
                    createdAt: createdAt
                ))
                availableByBatch[batch.id] = max(0, available - quantity)
                remaining -= quantity
            }
            guard remaining <= tolerance else {
                throw InvalidLedger(message: "保质期分组已变化，请重新打开后再试。")
            }
        }
        return allocations
    }

    static func automaticAllocations(
        quantity: Double,
        groups: [PetInventoryExpiryGroup]
    ) throws -> [PetInventoryBatchAllocation] {
        guard quantity.isFinite, quantity > 0 else {
            throw InvalidLedger(message: "数量必须大于 0。")
        }
        guard groups.count <= 1 else {
            throw InvalidLedger(message: "库存包含多个到期批次，请先分配本次出库数量。")
        }
        guard let group = groups.first else {
            throw InvalidLedger(message: "没有可用的库存批次。")
        }
        return try allocations(groupQuantities: [group.id: quantity], groups: groups, requiredTotal: quantity)
    }

    static func allocations(
        groupQuantities: [String: Double],
        groups: [PetInventoryExpiryGroup],
        requiredTotal: Double
    ) throws -> [PetInventoryBatchAllocation] {
        guard requiredTotal.isFinite, requiredTotal >= 0 else {
            throw InvalidLedger(message: "分配数量无效。")
        }
        let providedTotal = groupQuantities.values.reduce(0, +)
        guard providedTotal.isFinite, abs(providedTotal - requiredTotal) < tolerance else {
            throw InvalidLedger(message: "各到期批次的分配数量必须等于本次出库数量。")
        }
        let validGroupIDs = Set(groups.map(\.id))
        guard Set(groupQuantities.keys).isSubset(of: validGroupIDs) else {
            throw InvalidLedger(message: "分配记录引用了不存在的到期批次。")
        }

        var result: [PetInventoryBatchAllocation] = []
        for group in groups {
            let requested = groupQuantities[group.id, default: 0]
            guard requested.isFinite, requested >= 0,
                  requested <= group.remainingQuantity + tolerance else {
                throw InvalidLedger(message: "某个到期批次的分配数量超过当前余量。")
            }
            var remaining = requested
            for batch in group.batches where remaining > tolerance {
                let amount = min(remaining, batch.remainingQuantity)
                if amount > tolerance {
                    result.append(PetInventoryBatchAllocation(sourceBatchID: batch.id, quantity: amount))
                }
                remaining -= amount
            }
            guard remaining <= tolerance else {
                throw InvalidLedger(message: "某个到期批次的分配数量超过当前余量。")
            }
        }

        let allocatedTotal = result.reduce(0) { $0 + $1.quantity }
        guard allocatedTotal.isFinite, abs(allocatedTotal - requiredTotal) < tolerance else {
            throw InvalidLedger(message: "各到期批次的分配数量必须等于本次出库数量。")
        }
        return result
    }

    static func defaultGroupQuantities(
        quantity: Double,
        groups: [PetInventoryExpiryGroup]
    ) -> [String: Double] {
        var remaining = max(quantity, 0)
        var result: [String: Double] = [:]
        for group in groups where remaining > tolerance {
            let amount = min(remaining, group.remainingQuantity)
            result[group.id] = amount
            remaining -= amount
        }
        return result
    }

    static func unassignedBatchID(for productID: String) -> String {
        "__unassigned_pet_inventory__\(productID)"
    }

    static func validExpirationDate(_ value: String?) -> String? {
        guard let value, value.count == 10 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return value
    }

    private static func receiptOrder(_ left: PetInventoryBatchBalance, _ right: PetInventoryBatchBalance) -> Bool {
        if left.isUnassigned != right.isUnassigned { return !left.isUnassigned }
        if left.occurrenceDate != right.occurrenceDate { return left.occurrenceDate < right.occurrenceDate }
        if left.createdAt != right.createdAt { return left.createdAt < right.createdAt }
        return left.id < right.id
    }

    private static func receiptOrder(_ left: PetInventoryTransaction, _ right: PetInventoryTransaction) -> Bool {
        if left.occurrenceDate != right.occurrenceDate { return left.occurrenceDate < right.occurrenceDate }
        if left.createdAt != right.createdAt { return left.createdAt < right.createdAt }
        return left.id < right.id
    }
}

enum PetInventoryCosting {
    enum Kind: Equatable {
        case inbound
        case outbound
        case adjustment
    }

    struct Event {
        var id: String
        var kind: Kind
        var occurrenceDate: String
        var createdAt: Double
        var quantityChange: Double
        var quantityBefore: Double
        var quantityAfter: Double
        var totalPrice: Double?
        var unitPrice: Double?
    }

    struct Replay {
        /// Results stay in the same order as the source array; tie ordering uses that source order.
        var events: [Event]
        var currentQuantity: Double
    }

    struct InvalidHistory: Error {
        var eventID: String
        var occurrenceDate: String
        var availableQuantity: Double
        var requestedQuantity: Double
    }

    static func replay(_ source: [Event]) throws -> Replay {
        var result = source
        let ordered = source.enumerated().sorted { left, right in
            if left.element.occurrenceDate != right.element.occurrenceDate {
                return left.element.occurrenceDate < right.element.occurrenceDate
            }
            if left.element.createdAt != right.element.createdAt {
                return left.element.createdAt < right.element.createdAt
            }
            return left.offset < right.offset
        }

        var quantity = 0.0
        // nil means some stock has an unknown cost. Keep that uncertainty until inventory reaches zero.
        var inventoryCost: Double? = 0

        for (sourceIndex, var event) in ordered {
            let quantityBefore = quantity
            event.quantityBefore = quantityBefore

            switch event.kind {
            case .inbound:
                guard event.quantityChange.isFinite, event.quantityChange > 0 else {
                    throw InvalidHistory(
                        eventID: event.id,
                        occurrenceDate: event.occurrenceDate,
                        availableQuantity: quantity,
                        requestedQuantity: event.quantityChange
                    )
                }
                quantity += event.quantityChange
                if let amount = recordedInboundTotal(
                    quantity: event.quantityChange,
                    totalPrice: event.totalPrice,
                    unitPrice: event.unitPrice
                ) {
                    if quantityBefore == 0 {
                        inventoryCost = amount
                    } else if let currentCost = inventoryCost {
                        inventoryCost = currentCost + amount
                    }
                } else {
                    inventoryCost = nil
                }

            case .outbound:
                guard event.quantityChange.isFinite, event.quantityChange < 0 else {
                    throw InvalidHistory(
                        eventID: event.id,
                        occurrenceDate: event.occurrenceDate,
                        availableQuantity: quantity,
                        requestedQuantity: abs(event.quantityChange)
                    )
                }
                let requested = abs(event.quantityChange)
                let after = quantity - requested
                guard after >= -0.000_001 else {
                    throw InvalidHistory(
                        eventID: event.id,
                        occurrenceDate: event.occurrenceDate,
                        availableQuantity: quantity,
                        requestedQuantity: requested
                    )
                }

                if let currentCost = inventoryCost, quantityBefore > 0 {
                    let averageUnitCost = currentCost / quantityBefore
                    let totalCost = averageUnitCost * requested
                    if averageUnitCost.isFinite, averageUnitCost > 0, totalCost.isFinite, totalCost > 0 {
                        event.unitPrice = averageUnitCost
                        event.totalPrice = totalCost
                        inventoryCost = max(0, currentCost - totalCost)
                    } else {
                        event.unitPrice = nil
                        event.totalPrice = nil
                        inventoryCost = nil
                    }
                } else {
                    event.unitPrice = nil
                    event.totalPrice = nil
                    inventoryCost = nil
                }
                quantity = after

            case .adjustment:
                let target = event.quantityAfter
                guard target.isFinite, target >= 0 else {
                    throw InvalidHistory(
                        eventID: event.id,
                        occurrenceDate: event.occurrenceDate,
                        availableQuantity: quantity,
                        requestedQuantity: target
                    )
                }
                if target == 0 {
                    inventoryCost = 0
                } else if target > quantityBefore {
                    // Added stock has no purchase amount, so its cost cannot be guessed.
                    inventoryCost = nil
                } else if target < quantityBefore, let currentCost = inventoryCost, quantityBefore > 0 {
                    // A downward correction removes stock at the current moving-average cost.
                    inventoryCost = currentCost * target / quantityBefore
                }
                quantity = target
                event.quantityChange = target - quantityBefore
            }

            if abs(quantity) < 0.000_001 { quantity = 0 }
            event.quantityAfter = quantity
            if quantity == 0 { inventoryCost = 0 }
            result[sourceIndex] = event
        }

        return Replay(events: result, currentQuantity: quantity)
    }

    static func recordedInboundTotal(quantity: Double, totalPrice: Double?, unitPrice: Double?) -> Double? {
        guard quantity.isFinite, quantity > 0 else { return nil }
        if let totalPrice {
            guard totalPrice.isFinite, totalPrice > 0 else { return nil }
            return totalPrice
        }
        guard let unitPrice, unitPrice.isFinite, unitPrice > 0 else { return nil }
        let amount = unitPrice * quantity
        return amount.isFinite && amount > 0 ? amount : nil
    }

    static func recordedInboundUnitPrice(quantity: Double, totalPrice: Double?, unitPrice: Double?) -> Double? {
        guard quantity.isFinite, quantity > 0,
              let amount = recordedInboundTotal(quantity: quantity, totalPrice: totalPrice, unitPrice: unitPrice) else {
            return nil
        }
        let result = amount / quantity
        return result.isFinite && result > 0 ? result : nil
    }

    static func weightedAverageInboundUnitPrice(_ events: [Event]) -> Double? {
        var quantity = 0.0
        var amount = 0.0
        for event in events where event.kind == .inbound {
            guard let recordedAmount = recordedInboundTotal(
                quantity: event.quantityChange,
                totalPrice: event.totalPrice,
                unitPrice: event.unitPrice
            ) else { continue }
            quantity += event.quantityChange
            amount += recordedAmount
        }
        guard quantity > 0, amount.isFinite, amount > 0 else { return nil }
        let result = amount / quantity
        return result.isFinite && result > 0 ? result : nil
    }

    static func recordedOutboundTotal(quantityChange: Double, totalPrice: Double?, unitPrice: Double?) -> Double? {
        guard quantityChange.isFinite, quantityChange < 0 else { return nil }
        if let totalPrice {
            return totalPrice.isFinite && totalPrice > 0 ? totalPrice : nil
        }
        guard let unitPrice, unitPrice.isFinite, unitPrice > 0 else { return nil }
        let amount = unitPrice * abs(quantityChange)
        return amount.isFinite && amount > 0 ? amount : nil
    }
}

extension PetInventoryTransaction {
    var recordedInboundTotalPrice: Double? {
        guard type == .inbound else { return nil }
        return PetInventoryCosting.recordedInboundTotal(
            quantity: quantityChange,
            totalPrice: totalPrice,
            unitPrice: unitPrice
        )
    }

    var recordedInboundUnitPrice: Double? {
        guard type == .inbound else { return nil }
        return PetInventoryCosting.recordedInboundUnitPrice(
            quantity: quantityChange,
            totalPrice: totalPrice,
            unitPrice: unitPrice
        )
    }

    var recordedOutboundTotalPrice: Double? {
        guard type == .outbound else { return nil }
        return PetInventoryCosting.recordedOutboundTotal(
            quantityChange: quantityChange,
            totalPrice: totalPrice,
            unitPrice: unitPrice
        )
    }
}
