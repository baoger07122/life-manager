import Foundation

struct PetPalatabilityReviewGroup: Identifiable {
    let petID: String
    let petName: String
    let records: [PetPalatabilityReview]

    var id: String { petID }
    var count: Int { records.count }
    var latestRecord: PetPalatabilityReview? { records.first }
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
                records: sorted(petReviews)
            )
        }

        let historicalGroups = grouped.compactMap { petID, petReviews -> PetPalatabilityReviewGroup? in
            guard !activePetIDs.contains(petID) else { return nil }
            let orderedReviews = sorted(petReviews)
            let snapshot = orderedReviews.first?.petNameSnapshot.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return PetPalatabilityReviewGroup(
                petID: petID,
                petName: snapshot.isEmpty ? petID : snapshot,
                records: orderedReviews
            )
        }.sorted { left, right in
            guard let leftLatest = left.latestRecord, let rightLatest = right.latestRecord else {
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

    private static func sorted(_ reviews: [PetPalatabilityReview]) -> [PetPalatabilityReview] {
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
        return "加权均价 ¥\(average.formatted(.number.precision(.fractionLength(2))))/\(unit)"
    }
}
