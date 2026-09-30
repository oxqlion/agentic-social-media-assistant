//
//  CoreAIModelLoader.swift
//  app-v1
//
//  Core AI counterpart to CoreMLModelLoader: loads `<name>.aimodel` from the
//  app bundle and returns its `main` inference function. Both loaders stay in
//  the codebase; `OS27Models.useCoreAI` picks which one a given encoder uses.
//

import CoreAI
import Foundation

enum CoreAIModelLoader {
    /// Loads `<name>.aimodel` (or its compiled `<name>.aimodelc`) from the
    /// app bundle and returns its `main` function. Timed under the same
    /// `model.load` signpost as the Core ML path so the two are comparable.
    nonisolated static func load(_ name: String, function functionName: String = "main") async throws -> InferenceFunction {
        guard let url = Bundle.main.url(forResource: name, withExtension: "aimodel")
            ?? Bundle.main.url(forResource: name, withExtension: "aimodelc")
        else {
            throw ModelLoadError.resourceNotFound(name)
        }

        let model = try await MLPerfLog.measure("model.load") {
            try await AIModel(contentsOf: url)
        }
        guard let function = try model.loadFunction(named: functionName) else {
            throw ModelLoadError.resourceNotFound("\(name).\(functionName)")
        }
        MLPerfLog.info("\(name) (Core AI) functions=\(model.functionNames)")
        return function
    }
}

extension NDArray {
    /// Copies a contiguous float16/float32 tensor into `[Float]`. Exports are
    /// fp16 by default (matching the Core ML models), so the runtime dtype is
    /// checked rather than assumed.
    func toFloatArray() -> [Float] {
        switch scalarType {
        case .float16:
            return view(as: Float16.self).withUnsafePointer { pointer, shape, _ in
                var count = 1
                for i in 0..<shape.count { count *= shape[i] }
                return UnsafeBufferPointer(start: pointer, count: count).map(Float.init)
            }
        default:
            return view(as: Float.self).withUnsafePointer { pointer, shape, _ in
                var count = 1
                for i in 0..<shape.count { count *= shape[i] }
                return Array(UnsafeBufferPointer(start: pointer, count: count))
            }
        }
    }
}

extension NDArray {
    /// Argmax over the last axis of a `[batch, sequence, vocab]` tensor at
    /// `rowIndex` of the sequence axis — Core AI counterpart to
    /// `MLMultiArray.argmaxOverLastAxis`, honoring the tensor's strides.
    func argmaxOverLastAxis(rowIndex: Int) -> (token: Int, logit: Float) {
        func scan<Element>(_ view: NDArray.View<Element>, _ toFloat: (Element) -> Float) -> (Int, Float) {
            view.withUnsafePointer { pointer, shape, strides in
                precondition(shape.count == 3, "expected a [batch, sequence, vocab] tensor")
                let vocab = shape[2], rowOffset = rowIndex * strides[1], step = strides[2]
                var bestIndex = 0
                var bestValue = -Float.greatestFiniteMagnitude
                for v in 0..<vocab {
                    let value = toFloat(pointer[rowOffset + v * step])
                    if value > bestValue { bestValue = value; bestIndex = v }
                }
                return (bestIndex, bestValue)
            }
        }
        let result = scalarType == .float16
            ? scan(view(as: Float16.self)) { Float($0) }
            : scan(view(as: Float.self)) { $0 }
        return (token: result.0, logit: result.1)
    }
}
