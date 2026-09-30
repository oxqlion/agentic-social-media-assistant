//
//  UITestFixtures.swift
//  app-v1UITests
//
//  OS27 case study: reads the shared prompt fixtures from
//  case-study/fixtures/prompts.json, reached via the `CaseStudyFixtures`
//  symlink alongside this file (pointing at ../../../case-study/fixtures —
//  the same shared folder the app target's own CaseStudyFixtures.swift
//  bundles photos/music from). Kept separate from the app target's
//  CaseStudyFixtures type since UI test code runs in its own bundle/
//  process and can't see the host app's Swift symbols.
//

import Foundation

private struct PromptFixture: Codable {
    let id: String
    let prompt: String
}

private struct PromptFixtureFile: Codable {
    let photo_selection_prompts: [PromptFixture]
}

/// Used only to resolve `Bundle(for:)` to this test target's bundle.
private final class UITestFixturesBundleToken {}

enum UITestFixtures {
    /// All fixture prompt strings, in file order. Empty if the fixtures
    /// bundle/JSON couldn't be found or parsed — callers should treat that
    /// as a setup problem worth failing loudly on, not a silent skip.
    static func loadPrompts() -> [String] {
        let bundle = Bundle(for: UITestFixturesBundleToken.self)
        let url = bundle.url(forResource: "prompts", withExtension: "json", subdirectory: "CaseStudyFixtures")
            ?? bundle.url(forResource: "prompts", withExtension: "json")
        guard let url,
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(PromptFixtureFile.self, from: data)
        else {
            return []
        }
        return file.photo_selection_prompts.map(\.prompt)
    }
}
