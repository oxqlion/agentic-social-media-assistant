//
//  WebSearchToolTests.swift
//  app-v1Tests
//
//  Confirms the web_search tool never leaks provider-specific field names
//  to the language model, records the raw corpus for downstream scoring,
//  and degrades gracefully instead of throwing when the search fails.
//

import Testing
@testable import app_v1

private struct StubWebSearch: WebSearching {
    let response: WebSearchResponse?
    func search(_ query: String) async throws -> WebSearchResponse {
        guard let response else { throw StubError.searchFailed }
        return response
    }
}

private enum StubError: Error { case searchFailed }

@Suite struct WebSearchToolTests {
    @Test func digestContainsSnippetsButNoProviderFieldNames() async throws {
        let response = WebSearchResponse(
            query: "trending Bali beach dog hashtags",
            results: [
                WebSearchResult(title: "Beach dogs in Bali", url: "https://example.com", snippet: "#balidoglovers #sesehbeach", position: 1)
            ],
            relatedQueries: ["dog hashtags instagram"]
        )
        let log = WebSearchLog()
        let tool = WebSearchTool(search: StubWebSearch(response: response), log: log)

        let digest = try await tool.call(arguments: .init(query: "trending Bali beach dog hashtags"))

        #expect(digest.contains("#balidoglovers"))
        #expect(digest.contains("dog hashtags instagram"))
        #expect(!digest.contains("organic"))
        #expect(!digest.contains("searchParameters"))
        #expect(!digest.contains("credits"))
        #expect(!digest.contains("\"link\""))
    }

    @Test func recordsResponseInLogForDownstreamScoring() async throws {
        let response = WebSearchResponse(query: "q", results: [], relatedQueries: [])
        let log = WebSearchLog()
        let tool = WebSearchTool(search: StubWebSearch(response: response), log: log)

        _ = try await tool.call(arguments: .init(query: "q"))

        let recorded = await log.all()
        #expect(recorded.count == 1)
        #expect(recorded.first?.query == "q")
    }

    @Test func searchFailureReturnsGracefulMessageInsteadOfThrowing() async throws {
        let log = WebSearchLog()
        let tool = WebSearchTool(search: StubWebSearch(response: nil), log: log)

        let digest = try await tool.call(arguments: .init(query: "q"))

        #expect(digest.contains("failed"))
        let recorded = await log.all()
        #expect(recorded.isEmpty)
    }
}
