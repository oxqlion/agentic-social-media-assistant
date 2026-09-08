//
//  WebSearchTool.swift
//  app-v1
//
//  The only thing the language model knows about the outside world: a
//  `web_search` tool it can call when it needs current/trending hashtag
//  information. It never sees Serper, or any provider name — just
//  `WebSearching`. The digest handed back is plain text, never raw JSON.
//

import FoundationModels

struct WebSearchTool: Tool {
    let name = "web_search"
    let description = """
    Search the live web for current, trending hashtag information. Use \
    this whenever you need to know which hashtags people are actually \
    posting right now for a place, subject, or activity.
    """

    @Generable
    struct Arguments {
        @Guide(description: "A web search query, e.g. \"trending Bali beach dog hashtags instagram\"")
        var query: String
    }

    private static let maxResults = 8
    private static let maxSnippetLength = 240

    let search: WebSearching
    let log: WebSearchLog

    func call(arguments: Arguments) async throws -> String {
        let response: WebSearchResponse
        do {
            response = try await search.search(arguments.query)
        } catch {
            MLPerfLog.info("web_search failed for \"\(arguments.query)\": \(error)")
            return "web_search failed: no results available."
        }

        await log.record(response)

        guard !response.results.isEmpty else {
            return "No results found for \"\(arguments.query)\"."
        }

        var lines = ["Results for \"\(arguments.query)\":"]
        for (index, result) in response.results.prefix(Self.maxResults).enumerated() {
            let snippet = result.snippet.prefix(Self.maxSnippetLength)
            lines.append("\(index + 1). \(result.title) — \(snippet)")
        }
        if !response.relatedQueries.isEmpty {
            lines.append("Related searches: \(response.relatedQueries.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }
}
