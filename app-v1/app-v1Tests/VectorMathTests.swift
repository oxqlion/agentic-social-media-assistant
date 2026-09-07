//
//  VectorMathTests.swift
//  app-v1Tests
//

import Testing
@testable import app_v1

@Suite struct VectorMathTests {
    @Test func identicalVectorsHaveSimilarityOne() {
        let vector: [Float] = [0.6, 0.8, 0, 0]
        #expect(abs(cosineSimilarity(vector, vector) - 1.0) < 0.0001)
    }

    @Test func orthogonalVectorsHaveSimilarityZero() {
        let a: [Float] = [1, 0]
        let b: [Float] = [0, 1]
        #expect(abs(cosineSimilarity(a, b)) < 0.0001)
    }

    @Test func oppositeVectorsHaveSimilarityNegativeOne() {
        let a: [Float] = [1, 0]
        let b: [Float] = [-1, 0]
        #expect(abs(cosineSimilarity(a, b) - (-1.0)) < 0.0001)
    }

    @Test func scaleInvariant() {
        let a: [Float] = [1, 2, 3]
        let b: [Float] = [2, 4, 6]
        let scaledB: [Float] = [200, 400, 600]
        #expect(abs(cosineSimilarity(a, b) - cosineSimilarity(a, scaledB)) < 0.0001)
    }
}
