//
//  SearchOnlyHashtagExtractor.swift
//  app-v1
//
//  Extractor of last resort: no on-device language model involved at all.
//  Builds one search query straight from the context, pulls hashtags
//  directly out of the returned titles/snippets with a regex, and labels
//  them with a small keyword lexicon. Used whenever Apple Intelligence
//  isn't available (Simulator, an ineligible device, or a model failure),
//  so the Hashtag Agent still returns something.
//

import Foundation

struct SearchOnlyHashtagExtractor: HashtagExtracting {
    let search: WebSearching

    init(search: WebSearching = SerperClient()) {
        self.search = search
    }

    func extract(for context: HashtagContext) async -> (candidates: [RawHashtagCandidate], corpus: [WebSearchResponse]) {
        let query = Self.buildQuery(for: context)
        do {
            let response = try await MLPerfLog.measure("agent.hashtag.searchOnly") {
                try await search.search(query)
            }
            return (Self.extractCandidates(from: response), [response])
        } catch {
            MLPerfLog.info("search-only hashtag extraction failed: \(error)")
            return ([], [])
        }
    }

    static func buildQuery(for context: HashtagContext) -> String {
        let topic = [context.prompt, context.observations]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "trending instagram hashtags" : "trending \(trimmed) hashtags instagram"
    }

    private static let hashtagPattern = try! NSRegularExpression(pattern: "#[A-Za-z0-9_]{2,30}")

    static func extractCandidates(from response: WebSearchResponse) -> [RawHashtagCandidate] {
        var seen = Set<String>()
        var candidates: [RawHashtagCandidate] = []

        for result in response.results {
            let text = "\(result.title) \(result.snippet)"
            let range = NSRange(text.startIndex..., in: text)
            for match in hashtagPattern.matches(in: text, range: range) {
                guard let matchRange = Range(match.range, in: text) else { continue }
                let normalized = String(text[matchRange]).lowercased()
                guard seen.insert(normalized).inserted else { continue }
                candidates.append(RawHashtagCandidate(
                    tag: normalized,
                    category: category(for: normalized),
                    popularity: popularity(for: normalized)
                ))
            }
        }
        return candidates
    }

    // MARK: - Keyword lexicon

    private static let locationKeywords = [
        "bali", "beach", "island", "city", "town", "park", "mountain", "lake",
        "resort", "coast", "village", "downtown"
    ]
    private static let activityKeywords = [
        "hike", "hiking", "swim", "surf", "surfing", "walk", "run", "running",
        "yoga", "dance", "cook", "cooking", "travel", "adventure", "workout",
        "camping", "trip", "vacation", "diving"
    ]
    private static let moodKeywords = [
        "vibes", "love", "happy", "sunset", "sunrise", "aesthetic", "mood",
        "beautiful", "cute", "dreamy", "wanderlust", "goodvibes"
    ]
    private static let subjectKeywords = [
        "dog", "dogs", "cat", "cats", "pet", "pets", "puppy", "food",
        "fashion", "animal", "nature", "photography", "art"
    ]
    /// Popularity is a coarse guess from generic tag length here — the
    /// deterministic scorer's `searchFrequency` signal is the real
    /// popularity proxy once the corpus is available.
    private static let highPopularityKeywords = [
        "dog", "dogs", "cat", "cats", "love", "instagood", "photooftheday",
        "travel", "beach", "nature", "food", "fashion"
    ]

    private static func category(for tag: String) -> HashtagCategory {
        let body = tag.dropFirst() // strip "#"
        if locationKeywords.contains(where: { body.contains($0) }) { return .location }
        if activityKeywords.contains(where: { body.contains($0) }) { return .activity }
        if moodKeywords.contains(where: { body.contains($0) }) { return .mood }
        if subjectKeywords.contains(where: { body.contains($0) }) { return .subject }
        return .niche
    }

    private static func popularity(for tag: String) -> HashtagPopularity {
        let body = tag.dropFirst()
        if highPopularityKeywords.contains(where: { body == $0 }) { return .high }
        return body.count <= 12 ? .medium : .niche
    }
}
