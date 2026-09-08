//
//  MLMultiArray+Numeric.swift
//  app-v1
//
//  Small, dtype-agnostic helpers for building int32 inputs and reading
//  fp16/fp32 outputs, without assuming a particular model's shape beyond
//  what's passed in by the caller (which itself comes from the model's own
//  `MLMultiArrayConstraint`).
//

import CoreML

enum MLMultiArrayError: Error {
    case rankMismatch(expected: Int, actual: Int)
}

extension MLMultiArray {
    /// Builds an Int32 multi-array of the given shape from row-major values.
    static func int32(shape: [Int], values: [Int32]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: shape.map(NSNumber.init), dataType: .int32)
        let pointer = array.dataPointer.bindMemory(to: Int32.self, capacity: values.count)
        for i in 0..<values.count {
            pointer[i] = values[i]
        }
        return array
    }

    /// Flattens the full array to `[Float]` in row-major (logical) order.
    /// Intended for small tensors (embeddings) — not the right tool for a
    /// multi-million element tensor.
    func toFloatArray() -> [Float] {
        let count = self.count
        var result = [Float](repeating: 0, count: count)
        let strides = self.strides.map(\.intValue)
        let shape = self.shape.map(\.intValue)

        withUnsafeBytes { rawPointer in
            switch dataType {
            case .float16:
                let typed = rawPointer.bindMemory(to: Float16.self)
                forEachLogicalIndex(shape: shape, strides: strides) { logicalIndex, offset in
                    result[logicalIndex] = Float(typed[offset])
                }
            case .float32:
                let typed = rawPointer.bindMemory(to: Float.self)
                forEachLogicalIndex(shape: shape, strides: strides) { logicalIndex, offset in
                    result[logicalIndex] = typed[offset]
                }
            case .double:
                let typed = rawPointer.bindMemory(to: Double.self)
                forEachLogicalIndex(shape: shape, strides: strides) { logicalIndex, offset in
                    result[logicalIndex] = Float(typed[offset])
                }
            default:
                for i in 0..<count {
                    result[i] = self[i].floatValue
                }
            }
        }
        return result
    }

    /// Returns (tokenId, logit) for the argmax over the vocabulary axis at
    /// a given row of a `[batch, sequence, vocab]` fp16/fp32 tensor, using a
    /// raw-pointer scan (the vocab axis can be tens of thousands wide, so
    /// this avoids per-element `NSNumber` boxing).
    func argmaxOverLastAxis(rowIndex: Int) -> (token: Int, logit: Float) {
        let strides = self.strides.map(\.intValue)
        let shape = self.shape.map(\.intValue)
        precondition(shape.count == 3, "expected a [batch, sequence, vocab] tensor")
        let vocabSize = shape[2]
        let rowOffset = rowIndex * strides[1]
        let elementStride = strides[2]

        var bestIndex = 0
        var bestValue = -Float.greatestFiniteMagnitude

        withUnsafeBytes { rawPointer in
            switch dataType {
            case .float16:
                let typed = rawPointer.bindMemory(to: Float16.self)
                for v in 0..<vocabSize {
                    let value = Float(typed[rowOffset + v * elementStride])
                    if value > bestValue {
                        bestValue = value
                        bestIndex = v
                    }
                }
            case .float32:
                let typed = rawPointer.bindMemory(to: Float.self)
                for v in 0..<vocabSize {
                    let value = typed[rowOffset + v * elementStride]
                    if value > bestValue {
                        bestValue = value
                        bestIndex = v
                    }
                }
            default:
                for v in 0..<vocabSize {
                    let value = self[[0, rowIndex, v] as [NSNumber]].floatValue
                    if value > bestValue {
                        bestValue = value
                        bestIndex = v
                    }
                }
            }
        }
        return (bestIndex, bestValue)
    }

    /// Walks every logical (row-major) index of `shape` and calls `body`
    /// with the logical flat index and the corresponding physical offset
    /// (accounting for strides, so non-contiguous arrays are still correct).
    private func forEachLogicalIndex(shape: [Int], strides: [Int], _ body: (Int, Int) -> Void) {
        let rank = shape.count
        var indices = [Int](repeating: 0, count: rank)
        let total = shape.reduce(1, *)

        for logicalIndex in 0..<total {
            var offset = 0
            for d in 0..<rank {
                offset += indices[d] * strides[d]
            }
            body(logicalIndex, offset)

            var d = rank - 1
            while d >= 0 {
                indices[d] += 1
                if indices[d] < shape[d] { break }
                indices[d] = 0
                d -= 1
            }
        }
    }
}
