//
//  WebSearchLog.swift
//  app-v1
//
//  Records the raw `WebSearchResponse`s a `WebSearchTool` call produced
//  during one hashtag-extraction session, so the deterministic scorer can
//  compute search-frequency signals from the actual corpus afterwards
//  instead of trusting numbers the language model might invent.
//
//  An actor because a `Tool` can be called concurrently by the language
//  model session.
//

actor WebSearchLog {
    private var responses: [WebSearchResponse] = []

    func record(_ response: WebSearchResponse) {
        responses.append(response)
    }

    func all() -> [WebSearchResponse] {
        responses
    }
}
