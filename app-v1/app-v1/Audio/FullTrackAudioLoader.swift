//
//  FullTrackAudioLoader.swift
//  app-v1
//
//  Decodes an *entire* local audio file to mono Float32 PCM at a target
//  sample rate. Unlike AudioWaveformLoader (which seeks to and reads only
//  one fixed-size window for CLAP), highlight detection needs the whole
//  track to find where its structure repeats.
//

import AVFoundation
import Foundation

enum FullTrackAudioLoaderError: Error {
    case emptyAsset
    case unreadableAsset
    case conversionUnavailable
}

enum FullTrackAudioLoader {
    /// Decodes `url` in full to mono at `targetSampleRate`Hz.
    static func load(from url: URL, targetSampleRate: Double) throws -> (samples: [Float], duration: TimeInterval) {
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        guard file.length > 0 else { throw FullTrackAudioLoaderError.emptyAsset }

        let sourceFrameCount = AVAudioFrameCount(file.length)
        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: sourceFrameCount) else {
            throw FullTrackAudioLoaderError.unreadableAsset
        }
        try file.read(into: sourceBuffer, frameCount: sourceFrameCount)
        guard sourceBuffer.frameLength > 0 else { throw FullTrackAudioLoaderError.emptyAsset }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: targetSampleRate, channels: 1, interleaved: false
        ) else {
            throw FullTrackAudioLoaderError.conversionUnavailable
        }
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw FullTrackAudioLoaderError.conversionUnavailable
        }

        let ratio = targetSampleRate / sourceFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount((Double(sourceBuffer.frameLength) * ratio).rounded(.up) + 1)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
            throw FullTrackAudioLoaderError.unreadableAsset
        }

        var suppliedInput = false
        var conversionError: NSError?
        converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            if suppliedInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return sourceBuffer
        }
        if let conversionError {
            throw conversionError
        }

        guard let channelData = outputBuffer.floatChannelData else {
            throw FullTrackAudioLoaderError.unreadableAsset
        }
        let count = Int(outputBuffer.frameLength)
        guard count > 0 else { throw FullTrackAudioLoaderError.emptyAsset }
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: count))
        return (samples, Double(count) / targetSampleRate)
    }
}
