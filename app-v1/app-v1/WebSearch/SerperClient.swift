//
//  SerperClient.swift
//  app-v1
//
//  The only file that knows about Serper (google.serper.dev). Everything
//  else in the app talks to `WebSearching` / `WebSearchResponse` — Serper's
//  raw JSON shape (`organic`, `peopleAlsoAsk`, `searchParameters`, ...)
//  never leaves this file.
//
//  `nonisolated` so it never inherits this app's MainActor default
//  isolation — a network call must not run on the main thread.
//

import Foundation

enum WebSearchError: Error {
    case missingAPIKey
    case httpStatus(Int)
    case emptyResponse
}

nonisolated struct SerperClient: WebSearching {
    private static let endpoint = URL(string: "https://google.serper.dev/search")!

    private let apiKey: String
    private let session: URLSession

    init(apiKey: String = Secrets.serperAPIKey, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func search(_ query: String) async throws -> WebSearchResponse {
        guard !apiKey.isEmpty else { throw WebSearchError.missingAPIKey }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["q": query])

        let (data, response) = try await MLPerfLog.measure("search.serper") {
            try await session.data(for: request)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw WebSearchError.httpStatus(http.statusCode)
        }
        guard !data.isEmpty else { throw WebSearchError.emptyResponse }

        return try Self.parse(data, query: query)
    }

    /// Exposed so tests can exercise the mapping from Serper's raw JSON to
    /// `WebSearchResponse` without a network round-trip.
    nonisolated static func parse(_ data: Data, query: String) throws -> WebSearchResponse {
        let payload = try JSONDecoder().decode(SerperPayload.self, from: data)

        var results: [WebSearchResult] = (payload.organic ?? []).enumerated().map { index, item in
            WebSearchResult(
                title: item.title ?? "",
                url: item.link ?? "",
                snippet: item.snippet ?? "",
                position: item.position ?? index + 1
            )
        }

        var nextPosition = results.count + 1
        if let answerBox = payload.answerBox {
            results.append(WebSearchResult(
                title: answerBox.title ?? "",
                url: answerBox.link ?? "",
                snippet: answerBox.snippet ?? answerBox.answer ?? "",
                position: nextPosition
            ))
            nextPosition += 1
        }
        for item in payload.peopleAlsoAsk ?? [] {
            results.append(WebSearchResult(
                title: item.title ?? "",
                url: item.link ?? "",
                snippet: item.snippet ?? "",
                position: nextPosition
            ))
            nextPosition += 1
        }

        var relatedQueries: [String] = []
        var seenRelated = Set<String>()
        for candidate in (payload.relatedSearches ?? []).compactMap(\.query)
            + (payload.peopleAlsoAsk ?? []).compactMap(\.question) {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seenRelated.insert(trimmed.lowercased()).inserted else { continue }
            relatedQueries.append(trimmed)
        }

        return WebSearchResponse(query: query, results: results, relatedQueries: relatedQueries)
    }
}

// MARK: - Raw Serper response shape (private: never exposed outside this file)

private struct SerperPayload: Decodable {
    let organic: [SerperOrganicResult]?
    let peopleAlsoAsk: [SerperPeopleAlsoAsk]?
    let relatedSearches: [SerperRelatedSearch]?
    let answerBox: SerperAnswerBox?
}

private struct SerperOrganicResult: Decodable {
    let title: String?
    let link: String?
    let snippet: String?
    let position: Int?
}

private struct SerperPeopleAlsoAsk: Decodable {
    let question: String?
    let title: String?
    let snippet: String?
    let link: String?
}

private struct SerperRelatedSearch: Decodable {
    let query: String?
}

private struct SerperAnswerBox: Decodable {
    let title: String?
    let answer: String?
    let snippet: String?
    let link: String?
}
