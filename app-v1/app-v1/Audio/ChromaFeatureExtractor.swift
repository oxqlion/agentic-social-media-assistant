//
//  ChromaFeatureExtractor.swift
//  app-v1
//
//  STFT -> 12-bin chroma (pitch class energy), plus per-frame RMS on the
//  same time grid. On-device stand-in for `librosa.feature.chroma_cqt` +
//  `librosa.feature.rms` from trial_models/music_highlight_comparison:
//  a direct nearest-bin frequency->pitch-class mapping over an STFT
//  instead of a true Constant-Q filterbank, since a full CQT isn't worth
//  the implementation cost here — the self-similarity/novelty logic this
//  feeds only needs "does this frame sound like that frame", not
//  publication-grade chroma accuracy.
//

import Accelerate
import Foundation

struct ChromaFrames {
    /// [frame][pitchClass 0..<12], L2-normalized per frame. Empty if the
    /// track was shorter than one FFT window.
    let chroma: [[Float]]
    /// RMS energy per frame, same time grid as `chroma`.
    let rms: [Float]
    /// Start time (seconds) of each frame, i.e. `frameTimes[i] = i * hop / sampleRate`.
    let frameTimes: [Double]
}

enum ChromaFeatureExtractor {
    static let fftSize = 4096
    static let hopLength = 2048

    static func extract(samples: [Float], sampleRate: Double) -> ChromaFrames {
        let n = fftSize
        let hop = hopLength
        guard samples.count >= n else {
            return ChromaFrames(chroma: [], rms: [], frameTimes: [])
        }

        let log2n = vDSP_Length(log2(Double(n)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return ChromaFrames(chroma: [], rms: [], frameTimes: [])
        }
        defer { vDSP_destroy_fftsetup(setup) }

        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))

        // Bin -> nearest chroma pitch class (0 = C), precomputed once. Bin 0
        // (DC) is skipped: vDSP's packed real-FFT format mixes DC and
        // Nyquist into that single slot, and neither is musically meaningful.
        var binPitchClass = [Int](repeating: -1, count: n / 2)
        for k in 1..<(n / 2) {
            let freq = Double(k) * sampleRate / Double(n)
            guard freq > 20 else { continue }
            let midi = 69.0 + 12.0 * log2(freq / 440.0)
            binPitchClass[k] = ((Int(midi.rounded()) % 12) + 12) % 12
        }

        var chroma: [[Float]] = []
        var rms: [Float] = []
        var frameTimes: [Double] = []
        var frame = [Float](repeating: 0, count: n)
        var real = [Float](repeating: 0, count: n / 2)
        var imag = [Float](repeating: 0, count: n / 2)

        var start = 0
        while start + n <= samples.count {
            samples.withUnsafeBufferPointer { src in
                frame.withUnsafeMutableBufferPointer { dst in
                    vDSP_vmul(src.baseAddress! + start, 1, window, 1, dst.baseAddress!, 1, vDSP_Length(n))
                }
            }

            var frameRMS: Float = 0
            vDSP_rmsqv(frame, 1, &frameRMS, vDSP_Length(n))
            rms.append(frameRMS)
            frameTimes.append(Double(start) / sampleRate)
            chroma.append(chromaBins(of: frame, setup: setup, log2n: log2n, n: n, binPitchClass: binPitchClass, real: &real, imag: &imag))

            start += hop
        }

        return ChromaFrames(chroma: chroma, rms: rms, frameTimes: frameTimes)
    }

    private static func chromaBins(
        of frame: [Float], setup: FFTSetup, log2n: vDSP_Length, n: Int,
        binPitchClass: [Int], real: inout [Float], imag: inout [Float]
    ) -> [Float] {
        var bins = [Float](repeating: 0, count: 12)

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                frame.withUnsafeBufferPointer { framePtr in
                    framePtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(setup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))

                var magnitudes = [Float](repeating: 0, count: n / 2)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(n / 2))

                for k in 1..<(n / 2) {
                    let pitchClass = binPitchClass[k]
                    if pitchClass >= 0 {
                        bins[pitchClass] += magnitudes[k]
                    }
                }
            }
        }

        var normSquared: Float = 0
        vDSP_svesq(bins, 1, &normSquared, 12)
        let norm = normSquared.squareRoot()
        if norm > 1e-9 {
            var scale = 1 / norm
            vDSP_vsmul(bins, 1, &scale, &bins, 1, 12)
        }
        return bins
    }
}
