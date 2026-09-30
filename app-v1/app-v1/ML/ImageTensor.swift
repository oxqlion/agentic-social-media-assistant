//
//  ImageTensor.swift
//  app-v1
//
//  UIImage -> NDArray for the Core AI models. The Core ML models take a
//  `CVPixelBuffer` and have mean/std baked in via ImageType scale/bias; the
//  Core AI exports take a float32 [1, 3, S, S] RGB tensor in 0...255 and bake
//  the per-channel mean/std in as well, so this only resizes and re-lays-out.
//

import CoreAI
import CoreGraphics
import UIKit

extension ImagePreprocessor {
    /// Renders `image` into a `side` x `side` RGB bitmap (same crop/squash
    /// behaviour as `makePixelBuffer`) and returns planar float32
    /// `[1, 3, side, side]`, values 0...255.
    nonisolated static func makeRGBTensor(from image: UIImage, side: Int, mode: ImagePreprocessMode) throws -> NDArray {
        try MLPerfLog.measure("preprocess") {
            guard let cgImage = image.cgImage else { throw ImagePreprocessError.cgImageUnavailable }

            let bytesPerRow = side * 4
            var rgba = [UInt8](repeating: 0, count: bytesPerRow * side)
            let drawn: Bool = rgba.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(
                    data: buffer.baseAddress,
                    width: side,
                    height: side,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
                ) else { return false }
                let sourceSize = CGSize(width: cgImage.width, height: cgImage.height)
                let targetSize = CGSize(width: side, height: side)
                context.interpolationQuality = .high
                context.draw(cgImage, in: drawRect(mode: mode, sourceSize: sourceSize, targetSize: targetSize))
                return true
            }
            guard drawn else { throw ImagePreprocessError.contextCreationFailed }

            let plane = side * side
            var planar = [Float](repeating: 0, count: 3 * plane)
            for i in 0..<plane {
                planar[i] = Float(rgba[i * 4])
                planar[plane + i] = Float(rgba[i * 4 + 1])
                planar[2 * plane + i] = Float(rgba[i * 4 + 2])
            }
            return NDArray(scalars: planar, shape: [1, 3, side, side])
        }
    }
}
