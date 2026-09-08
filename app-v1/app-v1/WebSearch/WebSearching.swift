//
//  WebSearching.swift
//  app-v1
//
//  The seam between "however we search the web" and the rest of the
//  pipeline. Swapping Serper for another search provider later means
//  implementing this protocol, not touching WebSearchTool or HashtagAgent.
//

protocol WebSearching: Sendable {
    /// Runs a web search for `query`. Throws if the search itself fails
    /// (network error, bad response) — callers decide how to degrade.
    func search(_ query: String) async throws -> WebSearchResponse
}

/// Searcher of last resort: returns no results. Used when no search
/// provider is configured.
struct EmptyWebSearch: WebSearching {
    func search(_ query: String) async throws -> WebSearchResponse {
        WebSearchResponse(query: query, results: [], relatedQueries: [])
    }
}
