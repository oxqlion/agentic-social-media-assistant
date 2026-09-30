//
//  GetUserPreferencesToolTests.swift
//  app-v1Tests
//
//  Uses an injected provider so the real MemoryManager is never touched.
//

import Testing
import Foundation
@testable import app_v1

@Suite struct GetUserPreferencesToolTests {
    @Test func returnsFactsForTheRequestedDomain() async throws {
        let tool = GetUserPreferencesTool { category in
            category == .music ? "likes acoustic" : "likes landscape"
        }
        let music = try await tool.call(arguments: .init(domain: .music))
        let image = try await tool.call(arguments: .init(domain: .image))
        #expect(music == "likes acoustic")
        #expect(image == "likes landscape")
    }

    @Test func saysSoWhenThereIsNothingLearned() async throws {
        let tool = GetUserPreferencesTool { _ in "" }
        let result = try await tool.call(arguments: .init(domain: .music))
        #expect(result == "No learned music preferences yet.")
    }
}
