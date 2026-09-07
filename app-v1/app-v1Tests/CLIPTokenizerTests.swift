//
//  CLIPTokenizerTests.swift
//  app-v1Tests
//
//  Verifies the hand-written Swift BPE against golden token ids produced by
//  the real HF `CLIPTokenizer` (see Fixtures/CLIPTokenizerFixture.json,
//  generated from trial_models/export_for_ios/exported_models/clip_tokenizer).
//  This is the main correctness risk in the CLIP pipeline: a mismatched
//  token stream still "works" but silently returns wrong embeddings.
//

import Foundation
import Testing
@testable import app_v1

private struct CLIPFixtureCase: Codable {
    let text: String
    let input_ids: [Int32]
    let attention_mask: [Int32]
}

private struct CLIPFixture: Codable {
    let bos: Int32
    let eos: Int32
    let pad: Int32
    let seqLen: Int
    let cases: [CLIPFixtureCase]
}

private func loadCLIPFixture() throws -> CLIPFixture {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/CLIPTokenizerFixture.json")
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(CLIPFixture.self, from: data)
}

@Suite struct CLIPTokenizerTests {
    @Test func specialTokenIdsMatchExport() throws {
        let fixture = try loadCLIPFixture()
        #expect(fixture.bos == CLIPTokenizer.beginOfTextToken)
        #expect(fixture.eos == CLIPTokenizer.endOfTextToken)
        #expect(fixture.pad == CLIPTokenizer.endOfTextToken)
        #expect(fixture.seqLen == CLIPTokenizer.sequenceLength)
    }

    @Test func matchesGoldenFixture() throws {
        let fixture = try loadCLIPFixture()
        var tokenizer = try CLIPTokenizer()

        for testCase in fixture.cases {
            let encoded = tokenizer.encode(testCase.text)
            #expect(encoded.inputIds == testCase.input_ids, "input_ids mismatch for: \(testCase.text)")
            #expect(encoded.attentionMask == testCase.attention_mask, "attention_mask mismatch for: \(testCase.text)")
        }
    }

    @Test func alwaysProducesFixedLength() throws {
        var tokenizer = try CLIPTokenizer()
        for text in ["", "a", String(repeating: "word ", count: 50)] {
            let encoded = tokenizer.encode(text)
            #expect(encoded.inputIds.count == CLIPTokenizer.sequenceLength)
            #expect(encoded.attentionMask.count == CLIPTokenizer.sequenceLength)
        }
    }
}
