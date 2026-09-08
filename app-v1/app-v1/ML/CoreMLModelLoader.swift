//
//  CoreMLModelLoader.swift
//  app-v1
//
//  Loads compiled Core ML models from the app bundle. Deliberately avoids
//  Xcode's auto-generated model classes so the real input/output interface
//  (names, shapes, types) is inspected from `MLModelDescription` at load
//  time and logged, rather than assumed at compile time.
//

import CoreML
import Foundation

enum ModelLoadError: Error {
    case resourceNotFound(String)
}

enum CoreMLModelLoader {
    /// Loads `<name>.mlmodelc` from the app bundle with Neural Engine/GPU
    /// acceleration enabled, and logs its real input/output interface.
    nonisolated static func load(_ name: String) async throws -> MLModel {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else {
            throw ModelLoadError.resourceNotFound(name)
        }

        let configuration = MLModelConfiguration()
        // Not `.all`: on the iOS Simulator, the GPU compute path for these
        // fp16 ml-program models silently returns an all-zero output
        // (verified empirically — CPU and CPU+Neural Engine both compute
        // correctly, GPU alone does not). `.cpuAndNeuralEngine` still gets
        // Neural Engine acceleration on real devices and is unaffected by
        // this Simulator-only GPU bug.
        configuration.computeUnits = .cpuAndNeuralEngine

        let model = try await MLPerfLog.measure("model.load") {
            try await MLModel.load(contentsOf: url, configuration: configuration)
        }

        logInterface(name: name, model: model)
        return model
    }

    private static func logInterface(name: String, model: MLModel) {
        let description = model.modelDescription
        for (featureName, constraint) in description.inputDescriptionsByName {
            MLPerfLog.info("\(name) IN  \(featureName): \(describe(constraint))")
        }
        for (featureName, constraint) in description.outputDescriptionsByName {
            MLPerfLog.info("\(name) OUT \(featureName): \(describe(constraint))")
        }
    }

    private static func describe(_ constraint: MLFeatureDescription) -> String {
        switch constraint.type {
        case .image:
            guard let imageConstraint = constraint.imageConstraint else { return "image" }
            return "image \(imageConstraint.pixelsWide)x\(imageConstraint.pixelsHigh)"
        case .multiArray:
            guard let arrayConstraint = constraint.multiArrayConstraint else { return "multiArray" }
            let shape = arrayConstraint.shape.map(\.stringValue).joined(separator: "x")
            return "multiArray[\(shape)] \(arrayConstraint.dataType)"
        default:
            return "\(constraint.type)"
        }
    }
}
