//
//  VectorMath.swift
//  app-v1
//
//  Generic embedding-ranking math. Has no idea what produced the vectors.
//

import Foundation

/// Cosine similarity between two vectors. Makes no normalization
/// assumption about its inputs — callers whose embeddings are already
/// L2-normalized (as CLIP's are) effectively get a plain dot product.
func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    precondition(a.count == b.count, "vectors must have matching dimensionality")
    var dot: Float = 0
    var normA: Float = 0
    var normB: Float = 0
    for i in 0..<a.count {
        dot += a[i] * b[i]
        normA += a[i] * a[i]
        normB += b[i] * b[i]
    }
    let denominator = normA.squareRoot() * normB.squareRoot()
    return denominator == 0 ? 0 : dot / denominator
}
