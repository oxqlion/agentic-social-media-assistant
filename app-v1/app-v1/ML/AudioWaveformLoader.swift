//
//  AudioWaveformLoader.swift
//  app-v1
//
//  Decodes a local audio file to the fixed-size mono waveform CLAPEncoder
//  expects: exactly 10.0s at 48kHz. Reads/converts only that one window
//  (seeking into the file first) rather than decoding a whole track, since
//  a personal-library song can be several minutes long.
//

import AVFoundation
import Foundation

enum AudioWaveformLoaderError: Error {
    case unreadableAsset
    case conversionUnavailable
}

enum AudioWaveformLoader {
    /// Fraction into the track where the analyzed window starts, chosen to
    /// land past a likely silent/quiet intro without needing to actually
    /// detect one -- a deliberately simple heuristic for a local demo.
    private static let startFraction = 0.25

    /// Decodes one `CLAPEncoder.waveformSampleCount`-sample mono window
    /// from `url` at `CLAPEncoder.sampleRate`Hz, silence-padded if the
    /// source is shorter. Returns the samples plus the `[start, end]`
    /// second range they came from, so callers can show which part of the
    /// track was actually analyzed.
    static func loadWindow(from url: URL) throws -> (samples: [Float], range: ClosedRange<TimeInterval>) {
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        let sourceSampleRate = sourceFormat.sampleRate
        let windowSeconds = Double(CLAPEncoder.waveformSampleCount) / Double(CLAPEncoder.sampleRate)

        let totalDuration = Double(file.length) / sourceSampleRate
        let startSeconds = totalDuration > windowSeconds
            ? min(totalDuration * Self.startFraction, totalDuration - windowSeconds)
            : 0
        let startFrame = AVAudioFramePosition(startSeconds * sourceSampleRate)
        file.framePosition = max(0, startFrame)

        let framesToRead = AVAudioFrameCount(windowSeconds * sourceSampleRate)
        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: framesToRead) else {
            throw AudioWaveformLoaderError.unreadableAsset
        }
        try file.read(into: sourceBuffer, frameCount: framesToRead)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: Double(CLAPEncoder.sampleRate), channels: 1, interleaved: false
        ) else {
            throw AudioWaveformLoaderError.conversionUnavailable
        }
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw AudioWaveformLoaderError.conversionUnavailable
        }
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(CLAPEncoder.waveformSampleCount)
        ) else {
            throw AudioWaveformLoaderError.unreadableAsset
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
            throw AudioWaveformLoaderError.unreadableAsset
        }
        let decodedCount = Int(outputBuffer.frameLength)
        var samples = [Float](repeating: 0, count: CLAPEncoder.waveformSampleCount)
        let copyCount = min(decodedCount, CLAPEncoder.waveformSampleCount)
        samples.withUnsafeMutableBufferPointer { destination in
            destination.baseAddress!.update(from: channelData[0], count: copyCount)
        }
        // Shorter-than-copyCount reads (very short tracks, or a converter
        // that returned less than requested) leave the rest as the zero
        // padding `samples` was already initialized with.

        return (samples, startSeconds...(startSeconds + windowSeconds))
    }
}
