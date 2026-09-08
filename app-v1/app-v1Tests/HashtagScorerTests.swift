//
//  HashtagScorerTests.swift
//  app-v1Tests
//
//  Covers normalization/dedup/rejection rules and the three scoring
//  signals (searchFrequency, relevance, specificity) that feed the final
//  weighted score.
//

import Testing
@testable import app_v1

@Suite struct HashtagScorerTests {
    private let context = HashtagContext(
        prompt: "bali beach dog",
        observations: "a dog running on a beach",
        caption: "Sandy paws and salty kisses in Bali"
    )

    @Test func normalizationCollapsesEquivalentForms() {
        #expect(HashtagScorer.normalize("#Bali!") == "#bali")
        #expect(HashtagScorer.normalize("bali") == "#bali")
        #expect(HashtagScorer.normalize("#bali") == "#bali")
    }

    @Test func rejectsTooShortPurelyNumericAndStopwords() {
        #expect(HashtagScorer.normalize("#a") == nil)
        #expect(HashtagScorer.normalize("#123") == nil)
        #expect(HashtagScorer.normalize("#the") == nil)
    }

    @Test func dedupesEquivalentCandidatesKeepingOne() {
        let raw = [
            RawHashtagCandidate(tag: "#Bali", category: .location, popularity: .high),
            RawHashtagCandidate(tag: "bali", category: .location, popularity: .high)
        ]
        let scored = HashtagScorer().score(raw, corpus: [], context: context)
        #expect(scored.count == 1)
    }

    @Test func searchFrequencyReflectsCorpusOccurrenceRatio() {
        let raw = [RawHashtagCandidate(tag: "#balidoglovers", category: .niche, popularity: .medium)]
        let corpus = [
            WebSearchResponse(
                query: "q",
                results: [
                    WebSearchResult(title: "T1", url: "u1", snippet: "great #balidoglovers post", position: 1),
                    WebSearchResult(title: "T2", url: "u2", snippet: "unrelated content", position: 2)
                ],
                relatedQueries: []
            )
        ]
        let scored = HashtagScorer().score(raw, corpus: corpus, context: context)
        #expect(scored.first?.searchFrequency == 0.5)
    }

    @Test func specificTagScoresHigherSpecificityThanGenericTag() {
        let raw = [
            RawHashtagCandidate(tag: "#dog", category: .subject, popularity: .high),
            RawHashtagCandidate(tag: "#sesehbeach", category: .location, popularity: .niche)
        ]
        let scored = HashtagScorer().score(raw, corpus: [], context: context)
        let dog = scored.first { $0.tag == "#dog" }
        let sesehbeach = scored.first { $0.tag == "#sesehbeach" }
        #expect((sesehbeach?.specificity ?? 0) > (dog?.specificity ?? 0))
    }

    @Test func scoreMatchesDocumentedWeightedSum() throws {
        let raw = [RawHashtagCandidate(tag: "#balidog", category: .subject, popularity: .medium)]
        let scored = HashtagScorer().score(raw, corpus: [], context: context)
        let candidate = try #require(scored.first)
        let expected = HashtagScorer.relevanceWeight * candidate.relevance
            + HashtagScorer.searchFrequencyWeight * candidate.searchFrequency
            + HashtagScorer.specificityWeight * candidate.specificity
        #expect(abs(candidate.score - expected) < 0.0001)
    }
}
