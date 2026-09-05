import Foundation

struct ResolvedPetSpecification: Hashable {
    enum Dimension: String, Hashable {
        case mass
        case volume
    }

    let value: Double
    let unit: String
    let baseValue: Double
    let dimension: Dimension

    var displayText: String {
        switch dimension {
        case .mass:
            if baseValue >= 1_000 {
                return "\(PetSpecificationResolver.number(baseValue / 1_000))kg"
            }
            return "\(PetSpecificationResolver.number(baseValue))g"
        case .volume:
            if baseValue >= 1_000 {
                return "\(PetSpecificationResolver.number(baseValue / 1_000))L"
            }
            return "\(PetSpecificationResolver.number(baseValue))ml"
        }
    }

    var groupingKey: String { "\(dimension.rawValue)-\(PetSpecificationResolver.number(baseValue))" }
}

enum PetSpecificationResolver {
    static let selectableUnits = ["g", "kg", "ml", "L"]

    static func resolve(item: PetItem) -> ResolvedPetSpecification? {
        if let value = item.specValue, value > 0,
           let unit = normalizedUnit(item.specUnit ?? "") {
            return make(value: value, unit: unit)
        }
        return parse(item.spec)
    }

    static func parse(_ text: String) -> ResolvedPetSpecification? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let pattern = #"([0-9]+(?:[.,][0-9]+)?)\s*(kg|千克|公斤|g|克|ml|毫升|l|升)"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: clean, range: NSRange(clean.startIndex..., in: clean)),
              let valueRange = Range(match.range(at: 1), in: clean),
              let unitRange = Range(match.range(at: 2), in: clean),
              let value = Double(clean[valueRange].replacingOccurrences(of: ",", with: ".")),
              value > 0,
              let unit = normalizedUnit(String(clean[unitRange])) else { return nil }
        return make(value: value, unit: unit)
    }

    static func canonicalText(value: Double, unit: String) -> String {
        "\(number(value))\(unit)"
    }

    static func number(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...3)))
    }

    private static func normalizedUnit(_ raw: String) -> String? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "g", "克": return "g"
        case "kg", "千克", "公斤": return "kg"
        case "ml", "毫升": return "ml"
        case "l", "升": return "L"
        default: return nil
        }
    }

    private static func make(value: Double, unit: String) -> ResolvedPetSpecification? {
        switch unit {
        case "g": return ResolvedPetSpecification(value: value, unit: unit, baseValue: value, dimension: .mass)
        case "kg": return ResolvedPetSpecification(value: value, unit: unit, baseValue: value * 1_000, dimension: .mass)
        case "ml": return ResolvedPetSpecification(value: value, unit: unit, baseValue: value, dimension: .volume)
        case "L": return ResolvedPetSpecification(value: value, unit: unit, baseValue: value * 1_000, dimension: .volume)
        default: return nil
        }
    }
}
