//
//  ByteLevelBPE.swift
//  app-v1
//
//  The GPT-2/CLIP byte<->unicode mapping shared by both tokenizers' BPE
//  vocabularies. Maps each of the 256 byte values to a printable unicode
//  scalar so that BPE merges (and vocab/merges.txt files) can operate on
//  plain strings instead of raw bytes.
//

import Foundation

enum ByteLevelBPE {
    /// byte value -> unicode scalar used in vocab/merges files.
    static let byteToUnicode: [UInt8: Unicode.Scalar] = buildByteToUnicode()
    /// inverse of `byteToUnicode`, used when decoding token strings back to bytes.
    static let unicodeToByte: [Unicode.Scalar: UInt8] = Dictionary(
        uniqueKeysWithValues: byteToUnicode.map { ($1, $0) }
    )

    private static func buildByteToUnicode() -> [UInt8: Unicode.Scalar] {
        var bytes: [UInt8] = []
        bytes.append(contentsOf: UInt8(33)...UInt8(126))
        bytes.append(contentsOf: UInt8(161)...UInt8(172))
        bytes.append(contentsOf: UInt8(174)...UInt8(255))

        var mapping: [UInt8: Unicode.Scalar] = [:]
        for b in bytes {
            mapping[b] = Unicode.Scalar(UInt32(b))!
        }

        var nextCode: UInt32 = 256
        for b in 0...255 {
            let byte = UInt8(b)
            if mapping[byte] == nil {
                mapping[byte] = Unicode.Scalar(nextCode)!
                nextCode += 1
            }
        }
        return mapping
    }

    /// Encodes raw UTF-8 bytes as a string of byte-level unicode characters.
    static func encode(bytes: [UInt8]) -> String {
        var scalars = String.UnicodeScalarView()
        for byte in bytes {
            scalars.append(byteToUnicode[byte]!)
        }
        return String(scalars)
    }

    /// Decodes a byte-level unicode string back to the original UTF-8 text.
    /// Unknown scalars (should not occur for well-formed vocab tokens) are
    /// dropped rather than crashing.
    static func decode(_ token: String) -> [UInt8] {
        token.unicodeScalars.compactMap { unicodeToByte[$0] }
    }
}
