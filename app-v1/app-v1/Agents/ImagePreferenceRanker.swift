//
//  ImagePreferenceRanker.swift
//  app-v1
//
//  Re-ranks CLIP retrieval results using the user's learned image
//  preferences (UserPreferenceMemory, category .image) — a light nudge on
//  top of similarity score, not a hard filter or a replacement for it: a
//  photo that matches the query well still outranks one that merely
//  matches a liked theme.
//

import Foundation

enum ImagePreferenceRanker {
    /// Score adjustment per unit of confidence — kept small relative to
    /// typical CLIP cosine-similarity scores so preferences nudge the
    /// ranking instead of overriding query relevance.
    private static let weight: Float = 0.05

    static func apply(preferences: [UserPreferenceMemory], to results: [ScoredImage]) -> [ScoredImage] {
        let boosts: [String: Float] = preferences.reduce(into: [:]) { boosts, preference in
            guard preference.category == .image else { return }
            let sign: Float = preference.polarity == .prefer ? 1 : -1
            boosts[preference.value] = sign * Float(preference.confidence) * weight
        }
        guard !boosts.isEmpty else { return results }

        return results
            .map { scored -> ScoredImage in
                guard let caption = scored.image.caption else { return scored }
                let adjustment = BehavioralSignalExtractor.imageTags(in: caption)
                    .reduce(Float(0)) { $0 + (boosts[$1] ?? 0) }
                guard adjustment != 0 else { return scored }
                return ScoredImage(image: scored.image, score: scored.score + adjustment)
            }
            .sorted { $0.score > $1.score }
    }
}
