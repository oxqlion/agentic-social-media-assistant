//
//  HashtagSelectorTests.swift
//  app-v1Tests
//
//  Covers the final 5-15 hashtag selection: category diversification,
//  popularity balancing, and the relaxation pass that guarantees a
//  minimum-size result even when supply is thin or lopsided.
//

import Testing
@testable import app_v1

private func candidate(
    _ tag: String,
    _ category: HashtagCategory,
    _ popularity: HashtagPopularity = .medium,
    score: Double
) -> HashtagCandidate {
    HashtagCandidate(
        tag: tag,
        category: category,
        popularity: popularity,
        searchFrequency: score,
        relevance: score,
        specificity: score,
        score: score
    )
}

@Suite struct HashtagSelectorTests {
    @Test func selectsBetween5And15() {
        let candidates = (0..<40).map { candidate("#tag\($0)", HashtagCategory.allCases[$0 % 5], score: Double(40 - $0) / 40) }
        let result = HashtagSelector().select(from: candidates)
        #expect(result.count >= 5)
        #expect(result.count <= 15)
    }

    @Test func returnsEverythingWhenFewerThanMinimumAvailable() {
        let candidates = [
            candidate("#one", .subject, score: 0.9),
            candidate("#two", .location, score: 0.8),
            candidate("#three", .activity, score: 0.7)
        ]
        let result = HashtagSelector().select(from: candidates)
        #expect(result.count == 3)
        #expect(Set(result) == Set(candidates.map(\.tag)))
    }

    @Test func diversifiesAcrossCategoriesWhenAlternativesExist() {
        // 10 high-scoring "subject" candidates plus one strong candidate
        // per other category — a naive top-N would return all subjects.
        var candidates = (0..<10).map { candidate("#subject\($0)", .subject, score: 0.95 - Double($0) * 0.01) }
        candidates.append(candidate("#location1", .location, score: 0.5))
        candidates.append(candidate("#activity1", .activity, score: 0.5))
        candidates.append(candidate("#mood1", .mood, score: 0.5))
        candidates.append(candidate("#niche1", .niche, score: 0.5))

        let result = HashtagSelector().select(from: candidates, min: 5, max: 8)

        #expect(result.contains("#location1"))
        #expect(result.contains("#activity1"))
        #expect(result.contains("#mood1"))
        #expect(result.contains("#niche1"))
    }

    @Test func respectsPopularityQuotasWhenSupplyAllows() {
        var candidates = (0..<12).map { candidate("#high\($0)", .subject, .high, score: 0.9 - Double($0) * 0.01) }
        candidates += (0..<12).map { candidate("#niche\($0)", .location, .niche, score: 0.5 - Double($0) * 0.01) }

        let result = HashtagSelector().select(from: candidates, min: 5, max: 12)
        let selectedCandidates = candidates.filter { result.contains($0.tag) }
        let highCount = selectedCandidates.filter { $0.popularity == .high }.count

        // High tier's target share is 30% of max (≈4 of 12) — a naive
        // top-score selection would instead be dominated by "high" tags.
        #expect(highCount < 12)
        #expect(selectedCandidates.contains { $0.popularity == .niche })
    }

    @Test func relaxationFillsToMinimumWhenOnlyOneCategoryHasCandidates() {
        let candidates = (0..<7).map { candidate("#subject\($0)", .subject, score: 0.9 - Double($0) * 0.05) }
        let result = HashtagSelector().select(from: candidates, min: 5, max: 15)
        #expect(result.count >= 5)
    }
}
