//
//  MLMultiArrayNumericTests.swift
//  app-v1Tests
//
//  Synthetic, model-free checks of the raw-pointer MLMultiArray readers
//  used by CLIPEncoder/FlorenceCaptioner, isolating them from Core ML
//  inference so a wrong-value bug can't hide behind "did the model run".
//

import CoreML
import Testing
@testable import app_v1

@Suite struct MLMultiArrayNumericTests {
    @Test func toFloatArrayFloat32RowMajor() throws {
        let array = try MLMultiArray(shape: [2, 3], dataType: .float32)
        for i in 0..<6 { array[i] = NSNumber(value: Float(i)) }
        #expect(array.toFloatArray() == [0, 1, 2, 3, 4, 5])
    }

    @Test func toFloatArrayFloat16RowMajor() throws {
        let array = try MLMultiArray(shape: [1, 4], dataType: .float16)
        for i in 0..<4 { array[i] = NSNumber(value: Float(i) * 1.5) }
        #expect(array.toFloatArray() == [0, 1.5, 3, 4.5])
    }

    @Test func argmaxOverLastAxisFindsCorrectRowAndIndex() throws {
        // shape [1, 3, 5]; row 1 = [5...9], max at index 4 (value 9)
        let array = try MLMultiArray(shape: [1, 3, 5], dataType: .float32)
        var v: Float = 0
        for b in 0..<1 {
            for s in 0..<3 {
                for vocab in 0..<5 {
                    array[[b, s, vocab] as [NSNumber]] = NSNumber(value: v)
                    v += 1
                }
            }
        }
        let (token, logit) = array.argmaxOverLastAxis(rowIndex: 1)
        #expect(token == 4)
        #expect(logit == 9)
    }

    @Test func int32BuilderRoundTrips() throws {
        let values: [Int32] = [1, 2, 3, 4, 5, 6]
        let array = try MLMultiArray.int32(shape: [2, 3], values: values)
        #expect(array.dataType == .int32)
        for i in 0..<6 {
            #expect(array[i].int32Value == values[i])
        }
    }
}
