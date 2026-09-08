//
//  ClapTokenizer.swift
//  app-v1
//
//  Re-implements RoBERTa's byte-level BPE tokenizer in Swift (GPT-2-style
//  pre-tokenize regex + byte<->unicode mapping + plain byte-pair merges, no
//  end-of-word marker), matching `laion/clap-htsat-unfused`'s tokenizer
//  exactly. Reuses `ByteLevelBPE`'s byte<->unicode mapping with CLIPTokenizer
//  (that mapping is the GPT-2 convention both tokenizers borrow), but the
//  pre-tokenize pattern and merge algorithm differ from CLIP's: RoBERTa
//  encodes leading spaces into a "Ġ" token-prefix instead of appending
//  `</w>` at word ends, and doesn't lowercase.
//  Verified against golden fixtures produced by the real HF tokenizer; see
//  app-v1Tests/ClapTokenizerTests.swift.
//

import Foundation

struct ClapTokenizer {
    static let sequenceLength = 64
    static let beginOfTextToken: Int32 = 0
    static let padToken: Int32 = 1
    static let endOfTextToken: Int32 = 2
    static let unknownToken: Int32 = 3

    struct Encoded {
        let inputIds: [Int32]
        let attentionMask: [Int32]
    }

    private let vocab: [String: Int32]
    private let mergeRanks: [String: Int]
    private let pretokenizeRegex: NSRegularExpression
    private var bpeCache: [String: [String]] = [:]

    // Standard GPT-2/RoBERTa byte-level pre-tokenizer pattern: contractions,
    // then an optional leading space plus a run of letters/numbers/other
    // symbols, then trailing-whitespace handling.
    private static let pattern =
        #"'s|'t|'re|'ve|'m|'ll|'d| ?\p{L}+| ?\p{N}+| ?[^\s\p{L}\p{N}]+|\s+(?!\S)|\s+"#

    init(vocab: [String: Int32], merges: [String]) {
        self.vocab = vocab
        var ranks: [String: Int] = [:]
        for (index, line) in merges.enumerated() {
            ranks[line] = index
        }
        self.mergeRanks = ranks
        self.pretokenizeRegex = try! NSRegularExpression(pattern: Self.pattern)
    }

    /// Loads `clap_vocab.json` / `clap_merges.txt` from the app bundle.
    init() throws {
        guard let vocabURL = Bundle.main.url(forResource: "clap_vocab", withExtension: "json") else {
            throw ModelLoadError.resourceNotFound("clap_vocab.json")
        }
        guard let mergesURL = Bundle.main.url(forResource: "clap_merges", withExtension: "txt") else {
            throw ModelLoadError.resourceNotFound("clap_merges.txt")
        }

        let vocabData = try Data(contentsOf: vocabURL)
        let vocab = try JSONDecoder().decode([String: Int32].self, from: vocabData)

        let mergesText = try String(contentsOf: mergesURL, encoding: .utf8)
        let lines = mergesText.split(separator: "\n").map(String.init)
        // First line is a version header comment ("#version: 0.2"); drop it.
        let merges = lines.first?.hasPrefix("#") == true ? Array(lines.dropFirst()) : lines

        self.init(vocab: vocab, merges: merges)
    }

    /// Tokenizes to exactly `sequenceLength` (64) ids, padded with
    /// `<pad>`, plus the matching attention mask.
    mutating func encode(_ text: String) -> Encoded {
        let pieces = pretokenize(text)

        var contentIds: [Int32] = []
        for piece in pieces {
            for token in bpe(piece) {
                contentIds.append(vocab[token] ?? Self.unknownToken)
            }
        }

        let maxContent = Self.sequenceLength - 2 // room for <s> + </s>
        if contentIds.count > maxContent {
            contentIds = Array(contentIds.prefix(maxContent))
        }

        var ids: [Int32] = [Self.beginOfTextToken] + contentIds + [Self.endOfTextToken]
        let realLength = ids.count
        while ids.count < Self.sequenceLength {
            ids.append(Self.padToken)
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

    /// Maps a pre-tokenized piece's raw UTF-8 bytes to the byte-level
    /// unicode alphabet BPE merges operate on (no `</w>` marker -- unlike
    /// CLIP, RoBERTa already captured the word boundary as a leading "Ġ"
    /// during pre-tokenization).
    private func byteLevelEncode(_ piece: String) -> String {
        var scalars = String.UnicodeScalarView()
        for byte in Array(piece.utf8) {
            scalars.append(ByteLevelBPE.byteToUnicode[byte]!)
        }
        return String(scalars)
    }

    private mutating func bpe(_ piece: String) -> [String] {
        if let cached = bpeCache[piece] { return cached }

        let mapped = byteLevelEncode(piece)
        guard !mapped.isEmpty else { return [] }

        var symbols = mapped.unicodeScalars.map { String($0) }

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

        bpeCache[piece] = symbols
        return symbols
    }
}
