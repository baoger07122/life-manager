import Foundation

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
