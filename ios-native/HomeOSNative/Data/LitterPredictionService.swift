import Foundation

struct LitterPrediction: Hashable {
    var hasEnoughData: Bool
    var currentAmount: Double
    var progress: Double
    var averageDailyUsage: Double?
    var daysRemaining: Int?
    var thresholdDate: String?
    var shouldRefill: Bool

    static func insufficient(state: LitterBoxState) -> LitterPrediction {
        let progress = state.baseAmount > 0
            ? min(max(state.estimatedCurrentAmount / state.baseAmount, 0.03), 1)
            : 1
        return LitterPrediction(
            hasEnoughData: false,
            currentAmount: max(state.estimatedCurrentAmount, 0),
            progress: progress,
            averageDailyUsage: nil,
            daysRemaining: nil,
            thresholdDate: nil,
            shouldRefill: progress <= state.thresholdRatio
        )
    }
}

enum LitterPredictionService {
    static func evaluate(
        state: LitterBoxState,
        operations: [LitterOperation],
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> LitterPrediction {
        let effective = operations
            .filter { $0.type == .refill || $0.type == .replace }
            .sorted {
                if $0.occurrenceDate == $1.occurrenceDate { return $0.createdAt < $1.createdAt }
                return $0.occurrenceDate < $1.occurrenceDate
            }

        guard effective.count >= 2,
              let earliestDate = parse(effective.first?.occurrenceDate),
              let latestDate = parse(effective.last?.occurrenceDate) else {
            return .insufficient(state: state)
        }

        let earliestDay = calendar.startOfDay(for: earliestDate)
        let latestDay = calendar.startOfDay(for: latestDate)
        guard let spanDays = calendar.dateComponents([.day], from: earliestDay, to: latestDay).day,
              spanDays > 0 else {
            return .insufficient(state: state)
        }

        let totalAdded = effective.reduce(0) { $0 + max($1.totalBaseAmount, 0) }
        let dailyUsage = totalAdded / Double(spanDays)
        guard dailyUsage.isFinite, dailyUsage > 0,
              let lastOperationDate = parse(state.lastOperationDate) else {
            return .insufficient(state: state)
        }

        let today = calendar.startOfDay(for: date)
        let operationDay = calendar.startOfDay(for: lastOperationDate)
        let elapsedDays = max(calendar.dateComponents([.day], from: operationDay, to: today).day ?? 0, 0)
        let currentAmount = max(state.baseAmount - dailyUsage * Double(elapsedDays), 0)
        let rawProgress = state.baseAmount > 0 ? currentAmount / state.baseAmount : 0
        let visibleProgress = min(max(rawProgress, 0.03), 1)
        let daysRemaining = Int(floor(currentAmount / dailyUsage))
        let thresholdDays = state.baseAmount * (1 - state.thresholdRatio) / dailyUsage
        let thresholdDate = calendar.date(byAdding: .day, value: Int(ceil(thresholdDays)), to: operationDay)

        return LitterPrediction(
            hasEnoughData: true,
            currentAmount: currentAmount,
            progress: visibleProgress,
            averageDailyUsage: dailyUsage,
            daysRemaining: max(daysRemaining, 0),
            thresholdDate: thresholdDate.map(format),
            shouldRefill: rawProgress <= state.thresholdRatio
        )
    }

    static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        return formatter.date(from: value)
    }

    static func format(_ date: Date) -> String {
        formatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
