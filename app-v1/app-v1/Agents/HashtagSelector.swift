//
//  HashtagSelector.swift
//  app-v1
//
//  Turns a scored candidate pool into the final 5-15 hashtags, diversified
//  across categories (location/subject/activity/mood/niche) and balanced
//  across popularity tiers (high/medium/niche), rather than just taking
//  the top-N by score.
//

nonisolated struct HashtagSelector {
    static let minimumCount = 5
    static let maximumCount = 15

    /// Target share of `maximumCount` for each popularity tier.
    private static let popularityShare: [HashtagPopularity: Double] = [
        .high: 0.30,
        .medium: 0.45,
        .niche: 0.25
    ]

    func select(from candidates: [HashtagCandidate], min: Int = HashtagSelector.minimumCount, max: Int = HashtagSelector.maximumCount) -> [String] {
        guard !candidates.isEmpty else { return [] }

        let sorted = candidates.sorted { $0.score > $1.score }
        var remaining = sorted
        var selected: [HashtagCandidate] = []

        var popularityQuota: [HashtagPopularity: Int] = Dictionary(
            uniqueKeysWithValues: Self.popularityShare.map { tier, share in
                (tier, Swift.max(1, Int((share * Double(max)).rounded())))
            }
        )

        // Phase 1: guarantee one representative per category (its best
        // remaining candidate), so category coverage can never be starved
        // by a popularity tier that happens to be exhausted. Prefer a
        // candidate that's still within its tier's quota; fall back to the
        // category's best candidate outright otherwise.
        for category in HashtagCategory.allCases {
            guard selected.count < max else { break }
            let withinQuotaIndex = remaining.firstIndex {
                $0.category == category && (popularityQuota[$0.popularity] ?? 0) > 0
            }
            guard let index = withinQuotaIndex ?? remaining.firstIndex(where: { $0.category == category }) else { continue }

            let candidate = remaining.remove(at: index)
            popularityQuota[candidate.popularity, default: 0] -= 1
            selected.append(candidate)
        }

        // Phase 2: round-robin the remaining slots across categories,
        // strictly respecting popularity quotas now that every category
        // already has coverage, so no single tier dominates the rest.
        while selected.count < max && !remaining.isEmpty {
            var pickedThisPass = false
            for category in HashtagCategory.allCases {
                guard selected.count < max else { break }
                guard let index = remaining.firstIndex(where: {
                    $0.category == category && (popularityQuota[$0.popularity] ?? 0) > 0
                }) else { continue }

                let candidate = remaining.remove(at: index)
                popularityQuota[candidate.popularity, default: 0] -= 1
                selected.append(candidate)
                pickedThisPass = true
            }
            if !pickedThisPass { break }
        }

        // Relaxation pass: fill up to `min` from whatever's left, ignoring
        // category/tier quotas, so thin categories never leave the final
        // list short.
        if selected.count < min {
            for candidate in sorted where selected.count < min {
                guard !selected.contains(where: { $0.tag == candidate.tag }) else { continue }
                selected.append(candidate)
            }
        }

        return selected.sorted { $0.score > $1.score }.map(\.tag)
    }
}
