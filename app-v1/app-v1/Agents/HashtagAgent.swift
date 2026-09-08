//
//  HashtagAgent.swift
//  app-v1
//
//  Orchestration only: extract candidates (on-device model + web_search
//  tool) -> score them deterministically -> diversify/select the final
//  list. No scoring math and no language-model code lives here — that's
//  HashtagScorer/HashtagSelector's and HashtagExtracting's job.
//
//      HashtagContext -> HashtagExtracting -> HashtagScorer -> HashtagSelector -> hashtags
//

import Foundation

struct HashtagAgent {
    let extractor: HashtagExtracting
    let scorer: HashtagScorer
    let selector: HashtagSelector

    init(
        extractor: HashtagExtracting = FoundationModelHashtagExtractor(),
        scorer: HashtagScorer = HashtagScorer(),
        selector: HashtagSelector = HashtagSelector()
    ) {
        self.extractor = extractor
        self.scorer = scorer
        self.selector = selector
    }

    struct Result {
        let hashtags: [String]
        let candidates: [HashtagCandidate]
    }

    /// Never throws: a failed search or unavailable on-device model yields
    /// an empty result rather than derailing the rest of the flow.
    func run(for context: HashtagContext) async -> Result {
        let extraction = await MLPerfLog.measure("agent.hashtag.run") {
            await extractor.extract(for: context)
        }
        let candidates = scorer.score(extraction.candidates, corpus: extraction.corpus, context: context)
        let hashtags = selector.select(from: candidates)
        return Result(hashtags: hashtags, candidates: candidates)
    }
}
