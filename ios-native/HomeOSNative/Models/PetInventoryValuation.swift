import Foundation

struct PetInventoryValuationInput {
    let productID: String
    let quantity: Double
    let weightedUnitPrice: Double?
}

struct PetInventoryValuationSummary {
    let amount: Double
    let valuedProductCount: Int
    let unpricedProductCount: Int
    let invalidProductCount: Int

    var isIncomplete: Bool {
        unpricedProductCount > 0 || invalidProductCount > 0
    }

    var title: String {
        "库存估值"
    }

    var amountText: String {
        if valuedProductCount == 0 && isIncomplete { return "—" }
        return PetInventoryValuation.currencyText(amount) ?? "—"
    }

    var detailText: String? {
        var details: [String] = []
        if unpricedProductCount > 0 {
            details.append("未计价商品 \(unpricedProductCount) 种")
        }
        if invalidProductCount > 0 {
            details.append("数据异常商品 \(invalidProductCount) 种未计入")
        }
        return details.isEmpty ? nil : details.joined(separator: " · ")
    }

    var wholeAmountText: String {
        if valuedProductCount == 0 && isIncomplete { return "—" }
        return PetInventoryValuation.currencyIntegerText(amount) ?? "—"
    }

    var accessibilityLabel: String {
        var details = [isIncomplete ? "已计价小计" : title]
        if unpricedProductCount > 0 {
            details.append("未计价商品 \(unpricedProductCount) 种")
        }
        if invalidProductCount > 0 {
            details.append("数据异常商品 \(invalidProductCount) 种未计入")
        }
        details.append(wholeAmountText)
        return details.joined(separator: "，")
    }
}

enum PetInventoryValuation {
    static func summarize(_ inputs: [PetInventoryValuationInput]) -> PetInventoryValuationSummary {
        var seenProductIDs = Set<String>()
        var amount = 0.0
        var valuedProductCount = 0
        var unpricedProductCount = 0
        var invalidProductCount = 0

        for input in inputs {
            guard seenProductIDs.insert(input.productID).inserted else {
                invalidProductCount += 1
                continue
            }
            guard input.quantity.isFinite else {
                invalidProductCount += 1
                continue
            }
            guard input.quantity > 0 else { continue }

            guard let unitPrice = input.weightedUnitPrice else {
                unpricedProductCount += 1
                continue
            }
            guard unitPrice.isFinite else {
                invalidProductCount += 1
                continue
            }
            guard unitPrice > 0 else {
                unpricedProductCount += 1
                continue
            }

            let productValue = input.quantity * unitPrice
            guard productValue.isFinite, productValue > 0 else {
                invalidProductCount += 1
                continue
            }
            let nextAmount = amount + productValue
            guard nextAmount.isFinite else {
                invalidProductCount += 1
                continue
            }
            amount = nextAmount
            valuedProductCount += 1
        }

        return PetInventoryValuationSummary(
            amount: amount,
            valuedProductCount: valuedProductCount,
            unpricedProductCount: unpricedProductCount,
            invalidProductCount: invalidProductCount
        )
    }

    static func currencyText(_ amount: Double) -> String? {
        guard amount.isFinite, amount >= 0 else { return nil }
        return "¥\(amount.formatted(.number.precision(.fractionLength(2))))"
    }

    static func integerText(_ amount: Double) -> String? {
        guard amount.isFinite else { return nil }
        let roundedAmount = amount.rounded(.toNearestOrAwayFromZero)
        return roundedAmount.formatted(
            .number
                .locale(Locale(identifier: "en_US_POSIX"))
                .grouping(.always)
                .precision(.fractionLength(0))
        )
    }

    static func currencyIntegerText(_ amount: Double) -> String? {
        guard let value = integerText(amount), amount >= 0 else { return nil }
        return "¥\(value)"
    }
}
