//
//  ImagePreprocessorTests.swift
//  app-v1Tests
//
//  Exercises the ImagePreprocessor CGContext/CVPixelBuffer path (including
//  through a real MLImageConstraint from the compiled CLIPImageEncoder
//  model) without running any inference, so a preprocessing regression
//  (wrong channel order, a blank buffer) shows up independently of model
//  correctness.
//

import CoreML
import CoreVideo
import Testing
import UIKit
@testable import app_v1

@Suite struct ImagePreprocessorTests {
    private func makeSolidImage(color: (r: CGFloat, g: CGFloat, b: CGFloat), size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in
            UIColor(red: color.r, green: color.g, blue: color.b, alpha: 1).setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
        }
    }

    private func loadCLIPImageConstraint() async throws -> MLImageConstraint {
        let model = try await CoreMLModelLoader.load("CLIPImageEncoder")
        return try #require(model.modelDescription.inputDescriptionsByName["pixel_values"]?.imageConstraint)
    }

    @Test func rawCGContextIntoBGRABufferProducesRedPixels() throws {
        // Sanity-checks the CGContext/CVPixelBuffer recipe in isolation,
        // with no MLImageConstraint / Core ML involved at all.
        let width = 8, height = 8
        var pixelBufferOut: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &pixelBufferOut
        )
        #expect(status == kCVReturnSuccess)
        let pixelBuffer = try #require(pixelBufferOut)

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let context = try #require(CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ))

        let image = makeSolidImage(color: (1, 0, 0), size: CGSize(width: width, height: height))
        let cgImage = try #require(image.cgImage)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let base = CVPixelBufferGetBaseAddress(pixelBuffer)!.assumingMemoryBound(to: UInt8.self)
        let b = base[0], g = base[1], r = base[2]
        #expect(r > 200)
        #expect(g < 50)
        #expect(b < 50)
    }

    /// Exercises `ImagePreprocessor.makePixelBuffer` itself, through a real
    /// `MLImageConstraint`, on a solid red image.
    @Test func imagePreprocessorProducesRedPixelsForCLIPConstraint() async throws {
        let constraint = try await loadCLIPImageConstraint()
        let image = makeSolidImage(color: (1, 0, 0), size: CGSize(width: 300, height: 300))

        let pixelBuffer = try ImagePreprocessor.makePixelBuffer(
            from: image, constraint: constraint, mode: .aspectFillCenterCrop
        )

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let base = try #require(CVPixelBufferGetBaseAddress(pixelBuffer)).assumingMemoryBound(to: UInt8.self)

        // Sample the center pixel; report enough context to diagnose either
        // a wrong channel order or a genuinely blank buffer.
        let centerRow = height / 2
        let centerCol = width / 2
        let offset = centerRow * bytesPerRow + centerCol * 4
        let byte0 = base[offset], byte1 = base[offset + 1], byte2 = base[offset + 2], byte3 = base[offset + 3]

        #expect(
            format == kCVPixelFormatType_32BGRA || format == kCVPixelFormatType_32ARGB,
            "unexpected pixel format: \(format)"
        )
        #expect(
            [byte0, byte1, byte2, byte3].contains { $0 > 200 },
            "no channel is red-hot; buffer looks blank. bytes=\(byte0),\(byte1),\(byte2),\(byte3) format=\(format) size=\(width)x\(height)"
        )
    }
}
