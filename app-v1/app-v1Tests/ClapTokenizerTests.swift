//
//  ClapTokenizerTests.swift
//  app-v1Tests
//
//  Verifies the hand-written Swift BPE against golden token ids produced by
//  the real HF `RobertaTokenizerFast` (see Fixtures/ClapTokenizerFixture.json,
//  generated from trial_models/export_for_ios/exported_models/clap_tokenizer).
//  This is the main correctness risk in the CLAP pipeline: a mismatched
//  token stream still "works" but silently returns wrong embeddings.
//

import Foundation
import Testing
@testable import app_v1

private struct ClapFixtureCase: Codable {
    let text: String
    let input_ids: [Int32]
    let attention_mask: [Int32]
}

private struct ClapFixture: Codable {
    let bos: Int32
    let eos: Int32
    let pad: Int32
    let unk: Int32
    let seqLen: Int
    let cases: [ClapFixtureCase]
}

private func loadClapFixture() throws -> ClapFixture {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/ClapTokenizerFixture.json")
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(ClapFixture.self, from: data)
}

@Suite struct ClapTokenizerTests {
    @Test func specialTokenIdsMatchExport() throws {
        let fixture = try loadClapFixture()
        #expect(fixture.bos == ClapTokenizer.beginOfTextToken)
        #expect(fixture.eos == ClapTokenizer.endOfTextToken)
        #expect(fixture.pad == ClapTokenizer.padToken)
        #expect(fixture.unk == ClapTokenizer.unknownToken)
        #expect(fixture.seqLen == ClapTokenizer.sequenceLength)
    }

    @Test func matchesGoldenFixture() throws {
        let fixture = try loadClapFixture()
        var tokenizer = try ClapTokenizer()

        for testCase in fixture.cases {
            let encoded = tokenizer.encode(testCase.text)
            #expect(encoded.inputIds == testCase.input_ids, "input_ids mismatch for: \(testCase.text)")
            #expect(encoded.attentionMask == testCase.attention_mask, "attention_mask mismatch for: \(testCase.text)")
        }
    }

    @Test func alwaysProducesFixedLength() throws {
        var tokenizer = try ClapTokenizer()
        for text in ["", "a", String(repeating: "word ", count: 50)] {
            let encoded = tokenizer.encode(text)
            #expect(encoded.inputIds.count == ClapTokenizer.sequenceLength)
            #expect(encoded.attentionMask.count == ClapTokenizer.sequenceLength)
        }
    }
}
