//
//  WebSearchResponse.swift
//  app-v1
//
//  Our own clean shape for a web search, independent of whichever search
//  provider produced it. `results` folds together organic results and any
//  answer-box / "people also ask" style blocks a provider returns — those
//  are often the densest source of real hashtags (e.g. an answer box
//  listing "#dogsofinstagram (433M)") — normalized into the same shape,
//  with `position` continuing on after the organic results. Callers never
//  need to know whether a provider had such a block at all.
//

import Foundation

struct WebSearchResult: Sendable, Equatable {
    let title: String
    let url: String
    let snippet: String
    let position: Int
}

struct WebSearchResponse: Sendable, Equatable {
    let query: String
    let results: [WebSearchResult]
    let relatedQueries: [String]
}
