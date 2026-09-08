//
//  CLIPTokenizer.swift
//  app-v1
//
//  Re-implements OpenAI CLIP's byte-level BPE tokenizer in Swift (lowercase
//  + regex pre-tokenize + `</w>`-suffixed byte-pair merges), matching
//  `openai/clip-vit-base-patch32`'s tokenizer exactly so the exported
//  CLIPTextEncoder — which pools on `argmax(input_ids)` landing on the
//  first end-of-text token — sees the tokens it was trained/exported with.
//  Verified against golden fixtures produced by the real HF tokenizer; see
//  app-v1Tests/CLIPTokenizerTests.swift.
//

import Foundation

struct CLIPTokenizer {
    static let sequenceLength = 77
    static let beginOfTextToken: Int32 = 49406
    /// Also the pad token and the unk token — the CLIP tokenizer reuses
    /// end-of-text for all three, and the exported model's EOS pooling
    /// (`argmax(input_ids)`) relies on the padding sharing this id so the
    /// first occurrence found is the true end-of-text.
    static let endOfTextToken: Int32 = 49407

    struct Encoded {
        let inputIds: [Int32]
        let attentionMask: [Int32]
    }

    private let vocab: [String: Int32]
    private let mergeRanks: [String: Int]
    private let pretokenizeRegex: NSRegularExpression
    private var bpeCache: [String: [String]] = [:]

    private static let pattern =
        #"<\|startoftext\|>|<\|endoftext\|>|'s|'t|'re|'ve|'m|'ll|'d|[\p{L}]+|[\p{N}]|[^\s\p{L}\p{N}]+"#

    init(vocab: [String: Int32], merges: [String]) {
        self.vocab = vocab
        var ranks: [String: Int] = [:]
        for (index, line) in merges.enumerated() {
            ranks[line] = index
        }
        self.mergeRanks = ranks
        self.pretokenizeRegex = try! NSRegularExpression(pattern: Self.pattern)
    }

    /// Loads `clip_vocab.json` / `clip_merges.txt` from the app bundle.
    init() throws {
        guard let vocabURL = Bundle.main.url(forResource: "clip_vocab", withExtension: "json") else {
            throw ModelLoadError.resourceNotFound("clip_vocab.json")
        }
        guard let mergesURL = Bundle.main.url(forResource: "clip_merges", withExtension: "txt") else {
            throw ModelLoadError.resourceNotFound("clip_merges.txt")
        }

        let vocabData = try Data(contentsOf: vocabURL)
        let vocab = try JSONDecoder().decode([String: Int32].self, from: vocabData)

        let mergesText = try String(contentsOf: mergesURL, encoding: .utf8)
        let lines = mergesText.split(separator: "\n").map(String.init)
        // First line is a version header comment ("#version: 0.2"); drop it.
        let merges = lines.first?.hasPrefix("#") == true ? Array(lines.dropFirst()) : lines

        self.init(vocab: vocab, merges: merges)
    }

    /// Tokenizes to exactly `sequenceLength` (77) ids, padded with
    /// end-of-text, plus the matching attention mask.
    mutating func encode(_ text: String) -> Encoded {
        let words = pretokenize(text.lowercased())

        var contentIds: [Int32] = []
        for word in words {
            for piece in bpe(word) {
                contentIds.append(vocab[piece] ?? Self.endOfTextToken)
            }
        }

        let maxContent = Self.sequenceLength - 2 // room for bos + eos
        if contentIds.count > maxContent {
            contentIds = Array(contentIds.prefix(maxContent))
        }

        var ids: [Int32] = [Self.beginOfTextToken] + contentIds + [Self.endOfTextToken]
        let realLength = ids.count
        while ids.count < Self.sequenceLength {
            ids.append(Self.endOfTextToken)
        }

        var mask = [Int32](repeating: 0, count: Self.sequenceLength)
        for i in 0..<realLength { mask[i] = 1 }

        return Encoded(inputIds: ids, attentionMask: mask)
    }

    private func pretokenize(_ text: String) -> [String] {
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        var results: [String] = []
        pretokenizeRegex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match else { return }
            results.append(ns.substring(with: match.range))
        }
        return results
    }

    private mutating func bpe(_ word: String) -> [String] {
        if let cached = bpeCache[word] { return cached }

        let bytes = Array(word.utf8)
        guard !bytes.isEmpty else { return [] }

        var symbols = bytes.map { String(ByteLevelBPE.byteToUnicode[$0]!) }
        symbols[symbols.count - 1] += "</w>"

        while symbols.count > 1 {
            var bestRank = Int.max
            var bestIndex = -1
            for i in 0..<(symbols.count - 1) {
                let key = symbols[i] + " " + symbols[i + 1]
                if let rank = mergeRanks[key], rank < bestRank {
                    bestRank = rank
                    bestIndex = i
                }
            }
            guard bestIndex >= 0 else { break }

            let left = symbols[bestIndex]
            let right = symbols[bestIndex + 1]
            var merged: [String] = []
            var i = 0
            while i < symbols.count {
                if i < symbols.count - 1, symbols[i] == left, symbols[i + 1] == right {
                    merged.append(left + right)
                    i += 2
                } else {
                    merged.append(symbols[i])
                    i += 1
                }
            }
            symbols = merged
        }

        bpeCache[word] = symbols
        return symbols
    }
}
