//
//  FlorenceVocabulary.swift
//  app-v1
//
//  Decode-only counterpart to CLIPTokenizer: Florence's task prompt is
//  frozen inside FlorenceEncoder at export time (see FlorenceCaptioner), so
//  the app never needs to *encode* text for it — only turn the decoder's
//  generated token ids back into a caption string. Uses the same GPT-2/BART
//  byte-level alphabet as CLIP, decoded via ByteLevelBPE.
//

import Foundation

struct FlorenceVocabulary {
    static let beginOfSequence = 0
    static let padToken = 1
    static let endOfSequence = 2

    private let idToToken: [Int: String]
    private let addedTokenIds: Set<Int>

    init(vocab: [String: Int], addedTokens: [String: Int]) {
        var idToToken: [Int: String] = [:]
        for (token, id) in vocab { idToToken[id] = token }
        for (token, id) in addedTokens { idToToken[id] = token }
        self.idToToken = idToToken
        self.addedTokenIds = Set(addedTokens.values)
    }

    /// Loads `florence_vocab.json` / `florence_added_tokens.json` from the app bundle.
    init() throws {
        guard let vocabURL = Bundle.main.url(forResource: "florence_vocab", withExtension: "json") else {
            throw ModelLoadError.resourceNotFound("florence_vocab.json")
        }
        guard let addedURL = Bundle.main.url(forResource: "florence_added_tokens", withExtension: "json") else {
            throw ModelLoadError.resourceNotFound("florence_added_tokens.json")
        }

        let vocab = try JSONDecoder().decode([String: Int].self, from: Data(contentsOf: vocabURL))
        let added = try JSONDecoder().decode([String: Int].self, from: Data(contentsOf: addedURL))
        self.init(vocab: vocab, addedTokens: added)
    }

    /// Decodes generated token ids to text, skipping BOS/EOS/PAD. Regular
    /// vocab tokens are byte-level BPE (may span multi-byte UTF-8
    /// sequences across adjacent tokens); added special tokens are literal
    /// strings and are never byte-decoded.
    func decode(_ ids: [Int]) -> String {
        var byteBuffer: [UInt8] = []
        var output = ""

        func flushBytes() {
            guard !byteBuffer.isEmpty else { return }
            output += String(decoding: byteBuffer, as: UTF8.self)
            byteBuffer.removeAll()
        }

        for id in ids {
            if id == Self.beginOfSequence || id == Self.padToken || id == Self.endOfSequence { continue }
            guard let token = idToToken[id] else { continue }
            if addedTokenIds.contains(id) {
                flushBytes()
                output += token
            } else {
                byteBuffer.append(contentsOf: ByteLevelBPE.decode(token))
            }
        }
        flushBytes()
        return output
    }
}
