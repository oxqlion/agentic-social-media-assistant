//
//  ImagePreprocessor.swift
//  app-v1
//
//  UIImage -> CVPixelBuffer, sized and formatted from the model's own
//  `MLImageConstraint` (never a hardcoded width/height/pixel format).
//  Mean/std normalization is baked into the Core ML models themselves, so
//  no normalization happens here — only resizing and pixel format.
//

import CoreGraphics
import CoreML
import CoreVideo
import UIKit

enum ImagePreprocessMode {
    /// Resize the shortest edge to fit, then center-crop to the target
    /// size. Matches CLIP's preprocessing.
    case aspectFillCenterCrop
    /// Resize to the exact target size, ignoring aspect ratio. Matches
    /// Florence's preprocessing (its processor has `do_center_crop: false`).
    case squash
}

enum ImagePreprocessError: Error {
    case cgImageUnavailable
    case pixelBufferCreationFailed(CVReturn)
    case contextCreationFailed
    case unsupportedPixelFormat(OSType)
}

enum ImagePreprocessor {
    nonisolated static func makePixelBuffer(
        from image: UIImage,
        constraint: MLImageConstraint,
        mode: ImagePreprocessMode
    ) throws -> CVPixelBuffer {
        try MLPerfLog.measure("preprocess") {
            guard let cgImage = image.cgImage else {
                throw ImagePreprocessError.cgImageUnavailable
            }

            let targetWidth = constraint.pixelsWide
            let targetHeight = constraint.pixelsHigh
            let pixelFormat = constraint.pixelFormatType

            var pixelBufferOut: CVPixelBuffer?
            let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault, targetWidth, targetHeight, pixelFormat, attrs as CFDictionary, &pixelBufferOut
            )
            guard status == kCVReturnSuccess, let pixelBuffer = pixelBufferOut else {
                throw ImagePreprocessError.pixelBufferCreationFailed(status)
            }

            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

            let bitmapInfo = try cgBitmapInfo(for: pixelFormat)
            guard let context = CGContext(
                data: CVPixelBufferGetBaseAddress(pixelBuffer),
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo
            ) else {
                throw ImagePreprocessError.contextCreationFailed
            }

            let sourceSize = CGSize(width: cgImage.width, height: cgImage.height)
            let targetSize = CGSize(width: targetWidth, height: targetHeight)
            context.interpolationQuality = .high
            context.draw(cgImage, in: drawRect(mode: mode, sourceSize: sourceSize, targetSize: targetSize))

            return pixelBuffer
        }
    }

    /// CVPixelBufferCreate zero-fills new buffers, so an aspect-fill draw
    /// that lands partly off-canvas leaves the rest correctly transparent;
    /// CGContext.draw clips to the context bounds automatically.
    static func drawRect(mode: ImagePreprocessMode, sourceSize: CGSize, targetSize: CGSize) -> CGRect {
        switch mode {
        case .squash:
            return CGRect(origin: .zero, size: targetSize)
        case .aspectFillCenterCrop:
            let scale = max(targetSize.width / sourceSize.width, targetSize.height / sourceSize.height)
            let scaledSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
            let origin = CGPoint(
                x: (targetSize.width - scaledSize.width) / 2,
                y: (targetSize.height - scaledSize.height) / 2
            )
            return CGRect(origin: origin, size: scaledSize)
        }
    }

    private static func cgBitmapInfo(for pixelFormat: OSType) throws -> UInt32 {
        switch pixelFormat {
        case kCVPixelFormatType_32BGRA:
            return CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        case kCVPixelFormatType_32ARGB:
            return CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        default:
            throw ImagePreprocessError.unsupportedPixelFormat(pixelFormat)
        }
    }
}
