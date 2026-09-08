//
//  FoundationModelHashtagExtractor.swift
//  app-v1
//
//  Uses Apple's on-device Foundation Models framework (Apple Intelligence)
//  to research and label hashtag candidates for a post. The model itself
//  never talks to the network — it can only call the `web_search` tool,
//  which is the sole seam to the outside world. Falls back to
//  `SearchOnlyHashtagExtractor` whenever the system model is unavailable
//  or generation fails, so callers never need to special-case that.
//

import Foundation
import FoundationModels

@Generable
enum GeneratedHashtagCategory: String {
    case location
    case subject
    case activity
    case mood
    case niche
}

@Generable
enum GeneratedHashtagPopularity: String {
    case high
    case medium
    case niche
}

@Generable
struct GeneratedHashtagCandidate {
    @Guide(description: "A hashtag including the leading '#', e.g. \"#balidoglovers\"")
    var tag: String
    var category: GeneratedHashtagCategory
    @Guide(description: "How widely used this hashtag is on social media right now")
    var popularity: GeneratedHashtagPopularity
}

@Generable
struct HashtagExtraction {
    @Guide(description: "Candidate hashtags for this post, gathered from web search", .count(10...40))
    var candidates: [GeneratedHashtagCandidate]
}

struct FoundationModelHashtagExtractor: HashtagExtracting {
    private static let instructions = """
    You are a social-media hashtag researcher. You're given a post's \
    search prompt, visual observations of its photos, and its caption. \
    Your job is to find hashtags people are actually using right now for \
    this kind of post.

    You MUST call the web_search tool at least once — search for the \
    post's location, subject, and activity combined with words like \
    "trending hashtags" or "instagram hashtags" — before answering. Use \
    the search results to find real, currently-used hashtags; do not \
    invent hashtags that never appeared in a search result unless they \
    are an obvious, well-known variant.

    For each hashtag, classify its category as one of: location (place \
    names), subject (who/what is in the post), activity (what's \
    happening), mood (feeling or visual style), or niche (specific \
    community/interest). Estimate its popularity as high, medium, or \
    niche based on how often it appeared in the search results.
    """

    let search: WebSearching
    let fallback: HashtagExtracting

    init(search: WebSearching = SerperClient(), fallback: HashtagExtracting? = nil) {
        self.search = search
        self.fallback = fallback ?? SearchOnlyHashtagExtractor(search: search)
    }

    func extract(for context: HashtagContext) async -> (candidates: [RawHashtagCandidate], corpus: [WebSearchResponse]) {
        guard case .available = SystemLanguageModel.default.availability else {
            MLPerfLog.info("foundation model unavailable, using search-only hashtag extraction")
            return await fallback.extract(for: context)
        }

        let log = WebSearchLog()
        let tool = WebSearchTool(search: search, log: log)
        let session = LanguageModelSession(tools: [tool], instructions: Self.instructions)

        let prompt = """
        Prompt: \(context.prompt)
        Visual observations: \(context.observations)
        Caption: \(context.caption)
        """

        do {
            let response = try await MLPerfLog.measure("agent.hashtag.extract") {
                try await session.respond(to: prompt, generating: HashtagExtraction.self)
            }
            let candidates = response.content.candidates.map { candidate in
                RawHashtagCandidate(
                    tag: candidate.tag,
                    category: HashtagCategory(rawValue: candidate.category.rawValue) ?? .niche,
                    popularity: HashtagPopularity(rawValue: candidate.popularity.rawValue) ?? .medium
                )
            }
            let corpus = await log.all()
            if candidates.isEmpty {
                MLPerfLog.info("hashtag extraction produced no candidates, using search-only fallback")
                return await fallback.extract(for: context)
            }
            return (candidates, corpus)
        } catch {
            MLPerfLog.info("hashtag extraction failed, using search-only fallback: \(error)")
            return await fallback.extract(for: context)
        }
    }
}
