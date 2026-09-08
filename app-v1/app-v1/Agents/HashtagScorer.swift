//
//  HashtagScorer.swift
//  app-v1
//
//  Pure, deterministic scoring: normalizes and deduplicates raw candidates,
//  then computes searchFrequency/relevance/specificity signals and a final
//  weighted score. No I/O, no language model — kept separate from
//  HashtagExtracting so it's easy to unit test and reason about.
//

import Foundation

nonisolated struct HashtagScorer {
    static let relevanceWeight = 0.45
    static let searchFrequencyWeight = 0.30
    static let specificityWeight = 0.25

    /// Tags that survive normalization but are never useful hashtags.
    private static let stopwords: Set<String> = [
        "the", "and", "com", "www", "http", "https", "for", "with", "this", "that"
    ]

    func score(_ raw: [RawHashtagCandidate], corpus: [WebSearchResponse], context: HashtagContext) -> [HashtagCandidate] {
        var seen = Set<String>()
        var normalized: [(tag: String, category: HashtagCategory, popularity: HashtagPopularity)] = []
        for candidate in raw {
            guard let tag = Self.normalize(candidate.tag) else { continue }
            guard seen.insert(tag).inserted else { continue }
            normalized.append((tag, candidate.category, candidate.popularity))
        }

        let allResults = corpus.flatMap(\.results)
        let totalResults = allResults.count
        let vocabulary = Self.vocabulary(from: [context.prompt, context.observations, context.caption].joined(separator: " "))

        return normalized.map { item in
            let body = String(item.tag.dropFirst())
            let searchFrequency = Self.searchFrequency(for: body, in: allResults, totalResults: totalResults)
            let conceptTokens = Self.conceptTokens(for: body, vocabulary: vocabulary)
            let relevance = Self.relevance(conceptTokenCount: conceptTokens.count)
            let specificity = Self.specificity(body: body, conceptCount: conceptTokens.count)
            let score = Self.relevanceWeight * relevance
                + Self.searchFrequencyWeight * searchFrequency
                + Self.specificityWeight * specificity
            return HashtagCandidate(
                tag: item.tag,
                category: item.category,
                popularity: item.popularity,
                searchFrequency: searchFrequency,
                relevance: relevance,
                specificity: specificity,
                score: score
            )
        }
    }

    // MARK: - Normalization

    /// Strips the leading "#", lowercases, drops non-alphanumerics, and
    /// rejects anything too short/long, purely numeric, or a stopword.
    static func normalize(_ raw: String) -> String? {
        let stripped = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        let body = stripped.lowercased().filter { $0.isLetter || $0.isNumber }
        guard body.count >= 3, body.count <= 30 else { return nil }
        guard body.contains(where: \.isLetter) else { return nil }
        guard !stopwords.contains(body) else { return nil }
        return "#" + body
    }

    // MARK: - Signals

    private static func vocabulary(from text: String) -> Set<String> {
        Set(
            text.lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { $0.count >= 3 }
        )
    }

    /// Vocabulary words that appear as substrings of the tag body, e.g.
    /// "#balibeach" resolves to ["bali", "beach"].
    private static func conceptTokens(for body: String, vocabulary: Set<String>) -> [String] {
        vocabulary.filter { body.contains($0) }
    }

    /// A 0.4 floor for any tag the extractor considered worth surfacing,
    /// boosted as more of the post's own vocabulary is recognized in it.
    private static func relevance(conceptTokenCount: Int) -> Double {
        let floor = 0.4
        let boost = min(0.6, Double(conceptTokenCount) * 0.3)
        return floor + boost
    }

    /// Compound/place-specific tags (more recognized concepts, longer
    /// bodies) score higher than generic single-word tags.
    private static func specificity(body: String, conceptCount: Int) -> Double {
        let lengthFactor = min(1.0, Double(body.count) / 18.0)
        return min(1.0, (Double(conceptCount) + lengthFactor) / 3.0)
    }

    /// Fraction of web search results (title + snippet) that mention the
    /// tag — the real-world trend/consensus signal, computed purely from
    /// the corpus the web_search tool actually returned.
    private static func searchFrequency(for body: String, in results: [WebSearchResult], totalResults: Int) -> Double {
        guard totalResults > 0 else { return 0 }
        let matches = results.filter { ($0.title + " " + $0.snippet).lowercased().contains(body) }.count
        return Double(matches) / Double(totalResults)
    }
}
