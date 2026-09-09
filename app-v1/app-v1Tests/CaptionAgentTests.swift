//
//  CaptionAgentTests.swift
//  app-v1Tests
//
//  CaptionAgent is orchestration only — confirms it passes preferenceContext
//  through to the generator and short-circuits on empty observations,
//  regardless of what the generator does with it.
//

import Testing
@testable import app_v1

private struct RecordingCaptionGenerator: CaptionGenerating {
    var lastPreferenceContext: String?

    func generate(from observations: String, preferenceContext: String) async -> String {
        "caption(\(observations))[\(preferenceContext)]"
    }
}

@Suite struct CaptionAgentTests {
    @Test func passesPreferenceContextThroughToTheGenerator() async {
        let agent = CaptionAgent(generator: RecordingCaptionGenerator())

        let result = await agent.run(observations: "a dog on a beach", preferenceContext: "likes landscape, avoids selfie")

        #expect(result == "caption(a dog on a beach)[likes landscape, avoids selfie]")
    }

    @Test func emptyObservationsShortCircuitWithoutCallingTheGenerator() async {
        let agent = CaptionAgent(generator: RecordingCaptionGenerator())

        let result = await agent.run(observations: "", preferenceContext: "likes landscape")

        #expect(result.isEmpty)
    }

    @Test func preferenceContextDefaultsToEmpty() async {
        let agent = CaptionAgent(generator: RecordingCaptionGenerator())

        let result = await agent.run(observations: "a sunset")

        #expect(result == "caption(a sunset)[]")
    }
}
