//
//  HashtagAgentTests.swift
//  app-v1Tests
//
//  HashtagAgent is orchestration only — these confirm it just wires
//  extract -> score -> select together and never throws, regardless of
//  what the extractor produces.
//

import Testing
@testable import app_v1

private struct StubExtractor: HashtagExtracting {
    let candidates: [RawHashtagCandidate]
    let corpus: [WebSearchResponse]
    func extract(for context: HashtagContext) async -> (candidates: [RawHashtagCandidate], corpus: [WebSearchResponse]) {
        (candidates, corpus)
    }
}

@Suite struct HashtagAgentTests {
    private let context = HashtagContext(prompt: "bali beach dog", observations: "a dog on a beach", caption: "Sandy paws in Bali")

    @Test func ordersCandidatesIntoAFinalHashtagList() async {
        let raw = (0..<8).map { RawHashtagCandidate(tag: "#tag\($0)", category: HashtagCategory.allCases[$0 % 5], popularity: .medium) }
        let extractor = StubExtractor(candidates: raw, corpus: [])
        let agent = HashtagAgent(extractor: extractor)

        let result = await agent.run(for: context)

        #expect(!result.hashtags.isEmpty)
        #expect(result.candidates.count == raw.count)
    }

    @Test func emptyExtractionYieldsEmptyResultWithoutThrowing() async {
        let extractor = StubExtractor(candidates: [], corpus: [])
        let agent = HashtagAgent(extractor: extractor)

        let result = await agent.run(for: context)

        #expect(result.hashtags.isEmpty)
        #expect(result.candidates.isEmpty)
    }
}
