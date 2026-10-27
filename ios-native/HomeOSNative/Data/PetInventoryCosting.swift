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

    struct InvalidLedger: Error, Equatable {
        var message: String
    }

    static func balances(
        productID: String,
        transactions: [PetInventoryTransaction],
        excludingTransactionID: String? = nil
    ) throws -> [PetInventoryBatchBalance] {
        let records = transactions.filter {
            $0.productID == productID && $0.id != excludingTransactionID
        }
        let total = records.reduce(0) { $0 + $1.quantityChange }
        guard total.isFinite, total >= -tolerance else {
            throw InvalidLedger(message: "库存批次与当前总库存不一致，请先检查库存流水。")
        }

        let receipts = records.filter { $0.type == .inbound && $0.tracksExpirationBatch == true }
            .sorted(by: receiptOrder)
        let receiptIDs = Set(receipts.map(\.id))
        var remainingByBatch: [String: Double] = [:]
        var unassignedRemaining = 0.0
        let orderedRecords = records.enumerated().sorted { left, right in
            if left.element.occurrenceDate != right.element.occurrenceDate {
                return left.element.occurrenceDate < right.element.occurrenceDate
            }
            if left.element.createdAt != right.element.createdAt {
                return left.element.createdAt < right.element.createdAt
            }
            return left.offset < right.offset
        }

        for (_, record) in orderedRecords {
            guard record.quantityChange.isFinite else {
                throw InvalidLedger(message: "库存流水数量无效，未修改库存。")
            }

            if record.type == .inbound {
                guard record.quantityChange > 0 else {
                    throw InvalidLedger(message: "入库流水数量无效，未修改库存。")
                }
                if record.tracksExpirationBatch == true {
                    remainingByBatch[record.id, default: 0] += record.quantityChange
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
                    guard receiptIDs.contains(allocation.sourceBatchID),
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
        for receipt in receipts {
            let remaining = remainingByBatch[receipt.id, default: 0]
            let normalized = abs(remaining) < tolerance ? 0 : remaining
            if normalized > 0 {
                trackedRemaining += normalized
                result.append(PetInventoryBatchBalance(
                    id: receipt.id,
                    expirationDate: validExpirationDate(receipt.expirationDate),
                    remainingQuantity: normalized,
                    occurrenceDate: receipt.occurrenceDate,
                    createdAt: receipt.createdAt
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
