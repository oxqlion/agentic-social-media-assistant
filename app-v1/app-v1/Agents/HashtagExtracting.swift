//
//  HashtagExtracting.swift
//  app-v1
//
//  The seam between "however we turn a post's prompt/photos/caption plus
//  live web search into candidate hashtags" and the rest of the pipeline.
//  Swapping the on-device language model for something else later means
//  implementing this protocol, not touching HashtagAgent.
//

/// Everything the extractor knows about the post being hashtagged.
struct HashtagContext: Sendable {
    /// The user's raw search/post prompt.
    let prompt: String
    /// Florence's raw visual observations of the selected photos.
    let observations: String
    /// The Caption Agent's generated social-media caption.
    let caption: String
}

/// An unscored hashtag candidate, labelled but not yet ranked.
struct RawHashtagCandidate: Sendable {
    let tag: String
    let category: HashtagCategory
    let popularity: HashtagPopularity
}

protocol HashtagExtracting: Sendable {
    /// Produces candidate hashtags for `context`, along with the raw web
    /// search corpus gathered while doing so (used downstream for
    /// deterministic search-frequency scoring). Never throws: an extractor
    /// that can't help returns an empty result.
    func extract(for context: HashtagContext) async -> (candidates: [RawHashtagCandidate], corpus: [WebSearchResponse])
}
