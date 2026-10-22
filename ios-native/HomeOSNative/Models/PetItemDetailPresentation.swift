import Foundation

enum PetProductReviewDimensionOrdering {
    static func ordered(scores: [String: Int], standardOrder: [String]) -> [String] {
        let standardDimensions = Set(standardOrder)
        let existingStandardDimensions = standardOrder.filter { scores[$0] != nil }
        let historicalExtraDimensions = scores.keys
            .filter { !standardDimensions.contains($0) }
            .sorted()
        return existingStandardDimensions + historicalExtraDimensions
    }
}

enum PetReviewDateText {
    static func display(_ storedValue: String) -> String {
        guard !storedValue.isEmpty else { return "--" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: storedValue) else { return storedValue }
        return formatter.string(from: date)
    }
}

struct PetPalatabilityReviewGroup: Identifiable {
    let petID: String
    let petName: String
    let records: [PetPalatabilityReview]
    let latestReviewDateRecord: PetPalatabilityReview?

    var id: String { petID }
    var count: Int { records.count }
    var latestRecord: PetPalatabilityReview? { records.first }
    var oldestFirstRecords: [PetPalatabilityReview] {
        records.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id < $1.id
        }
    }
    var averageScore: Double {
        guard !records.isEmpty else { return 0 }
        return Double(records.reduce(0) { $0 + $1.resolvedScore }) / Double(records.count)
    }
}

enum PetPalatabilityReviewGrouping {
    static func groups(
        productID: String,
        reviews: [PetPalatabilityReview],
        activePets: [PetProfile]
    ) -> [PetPalatabilityReviewGroup] {
        let grouped = Dictionary(
            grouping: reviews.filter { $0.productID == productID },
            by: \.petID
        )
        let activePetIDs = Set(activePets.map(\.id))

        let activeGroups = activePets.compactMap { pet -> PetPalatabilityReviewGroup? in
            guard let petReviews = grouped[pet.id] else { return nil }
            return PetPalatabilityReviewGroup(
                petID: pet.id,
                petName: pet.name,
                records: sortedByCreationDate(petReviews),
                latestReviewDateRecord: sortedByReviewDate(petReviews).first
            )
        }

        let historicalGroups = grouped.compactMap { petID, petReviews -> PetPalatabilityReviewGroup? in
            guard !activePetIDs.contains(petID) else { return nil }
            let latestReviewDateRecord = sortedByReviewDate(petReviews).first
            let snapshot = latestReviewDateRecord?.petNameSnapshot.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return PetPalatabilityReviewGroup(
                petID: petID,
                petName: snapshot.isEmpty ? petID : snapshot,
                records: sortedByCreationDate(petReviews),
                latestReviewDateRecord: latestReviewDateRecord
            )
        }.sorted { left, right in
            guard let leftLatest = left.latestReviewDateRecord, let rightLatest = right.latestReviewDateRecord else {
                return left.petName.localizedStandardCompare(right.petName) == .orderedAscending
            }
            if leftLatest.reviewDate != rightLatest.reviewDate {
                return leftLatest.reviewDate > rightLatest.reviewDate
            }
            if leftLatest.createdAt != rightLatest.createdAt {
                return leftLatest.createdAt > rightLatest.createdAt
            }
            return left.petName.localizedStandardCompare(right.petName) == .orderedAscending
        }

        return activeGroups + historicalGroups
    }

    private static func sortedByCreationDate(_ reviews: [PetPalatabilityReview]) -> [PetPalatabilityReview] {
        reviews.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id < $1.id
        }
    }

    private static func sortedByReviewDate(_ reviews: [PetPalatabilityReview]) -> [PetPalatabilityReview] {
        reviews.sorted {
            if $0.reviewDate != $1.reviewDate { return $0.reviewDate > $1.reviewDate }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id < $1.id
        }
    }
}

enum PetItemHeroAveragePrice {
    static func text(average: Double?, unit: String) -> String? {
        guard let average, average.isFinite, average > 0 else { return nil }
        guard let price = PetInventoryValuation.currencyText(average) else { return nil }
        return "\(price)/\(unit)"
    }
}

enum PetItemHomepageAveragePrice {
    static func text(average: Double?, unit: String) -> String? {
        guard let average, average.isFinite, average > 0 else { return nil }
        let price = average.formatted(
            .number
                .locale(Locale(identifier: "en_US_POSIX"))
                .precision(.fractionLength(1))
        )
        return "¥\(price)/\(unit)"
    }
}
