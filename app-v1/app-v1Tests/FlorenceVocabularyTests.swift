//
//  FlorenceVocabularyTests.swift
//  app-v1Tests
//
//  Verifies byte-level BPE decoding against golden strings produced by the
//  real HF Florence tokenizer (see Fixtures/FlorenceTokenizerFixture.json).
//

import Foundation
import Testing
@testable import app_v1

private struct FlorenceFixtureCase: Codable {
    let text: String
    let ids: [Int]
    let decoded: String
}

private struct FlorenceFixture: Codable {
    let bos: Int
    let eos: Int
    let pad: Int
    let cases: [FlorenceFixtureCase]
}

private func loadFlorenceFixture() throws -> FlorenceFixture {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/FlorenceTokenizerFixture.json")
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(FlorenceFixture.self, from: data)
}

@Suite struct FlorenceVocabularyTests {
    @Test func specialTokenIdsMatchExport() throws {
        let fixture = try loadFlorenceFixture()
        #expect(fixture.bos == FlorenceVocabulary.beginOfSequence)
        #expect(fixture.eos == FlorenceVocabulary.endOfSequence)
        #expect(fixture.pad == FlorenceVocabulary.padToken)
    }

    @Test func decodesGoldenFixture() throws {
        let fixture = try loadFlorenceFixture()
        let vocabulary = try FlorenceVocabulary()

        for testCase in fixture.cases {
            let decoded = vocabulary.decode(testCase.ids)
            #expect(decoded == testCase.decoded, "decode mismatch for ids from: \(testCase.text)")
        }
    }

    @Test func skipsSpecialTokens() throws {
        let vocabulary = try FlorenceVocabulary()
        let withSpecials = [FlorenceVocabulary.beginOfSequence, 250, 2335, FlorenceVocabulary.endOfSequence]
        let withoutSpecials = [250, 2335]
        #expect(vocabulary.decode(withSpecials) == vocabulary.decode(withoutSpecials))
    }
}
