//
//  HashtagCandidate.swift
//  app-v1
//
//  A scored, categorized hashtag candidate on its way through the Hashtag
//  Agent's pipeline: extract -> score -> diversify/select.
//

enum HashtagCategory: String, CaseIterable, Sendable {
    case location
    case subject
    case activity
    case mood
    case niche
}

enum HashtagPopularity: String, CaseIterable, Sendable {
    case high
    case medium
    case niche
}

struct HashtagCandidate: Sendable, Equatable, Identifiable {
    var id: String { tag }

    /// Normalized form: "#" followed by lowercased alphanumerics, e.g. "#balidoglovers".
    let tag: String
    let category: HashtagCategory
    let popularity: HashtagPopularity

    /// How often the tag (or its concept) shows up across the web search
    /// corpus, 0...1.
    let searchFrequency: Double
    /// How well the tag matches the user's prompt/photos/caption, 0...1.
    let relevance: Double
    /// How narrowly targeted the tag is versus generic, 0...1.
    let specificity: Double
    /// Weighted combination of the three signals above.
    let score: Double
}
