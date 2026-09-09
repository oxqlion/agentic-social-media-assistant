//
//  SelfSimilarityNovelty.swift
//  app-v1
//
//  Foote's checkerboard-kernel novelty method for structural segmentation,
//  plus the repetition/energy scoring that turns segments into a single
//  highlight pick. Direct port of the `score_and_pick_segment` /
//  `boundary_indices_from_ssm` helpers validated in
//  trial_models/music_highlight_comparison/compare_music_highlight_models.ipynb
//  — see that notebook for why this scores a chorus as "the segment that's
//  both most repeated elsewhere and highest-energy".
//
//  Pure math: no I/O, no audio decoding, so it's cheap to unit test against
//  synthetic feature matrices.
//

import Foundation

enum SelfSimilarityNovelty {
    /// Gaussian-tapered checkerboard kernel of shape `(2*size+1) x (2*size+1)`.
    static func checkerboardKernel(size: Int, sigmaRatio: Float = 0.4) -> [[Float]] {
        let axis = Array(-size...size).map { Float($0) }
        let sigma = Float(size) * sigmaRatio
        let gauss = axis.map { exp(-($0 * $0) / (2 * sigma * sigma)) }
        let sign = axis.map { $0 >= 0 ? Float(1) : Float(-1) } // sign(0) := +1, matching the Python prototype's +1e-9 nudge

        var kernel = [[Float]](repeating: [Float](repeating: 0, count: axis.count), count: axis.count)
        for i in 0..<axis.count {
            for j in 0..<axis.count {
                kernel[i][j] = sign[i] * sign[j] * gauss[i] * gauss[j]
            }
        }
        return kernel
    }

    /// Convolves `ssm`'s diagonal with a checkerboard kernel: high where the
    /// self-similarity structure changes abruptly (a section boundary).
    /// Note: only `[kernelSize, n - kernelSize)` gets a real value — the
    /// unanalyzed edges stay at their `0` initial value, and since the
    /// final normalization takes the min/max over the *whole* array, a
    /// track with genuinely uniform self-similarity can show an artificial
    /// step right at those edges (untouched `0` butting up against a
    /// nonzero interior). Harmless in practice — a real track is never
    /// uniformly self-similar everywhere — but worth knowing before reading
    /// too much into a boundary that lands suspiciously close to `kernelSize`.
    static func noveltyCurve(ssm: [[Float]], kernelSize: Int) -> [Float] {
        let kernel = checkerboardKernel(size: kernelSize)
        let n = ssm.count
        var novelty = [Float](repeating: 0, count: n)

        guard n > 2 * kernelSize else { return novelty }
        for t in kernelSize..<(n - kernelSize) {
            var sum: Float = 0
            for di in -kernelSize...kernelSize {
                let row = ssm[t + di]
                let kernelRow = kernel[di + kernelSize]
                for dj in -kernelSize...kernelSize {
                    sum += row[t + dj] * kernelRow[dj + kernelSize]
                }
            }
            novelty[t] = sum
        }

        let minValue = novelty.min() ?? 0
        for i in 0..<n { novelty[i] -= minValue }
        let maxValue = novelty.max() ?? 0
        if maxValue > 0 {
            for i in 0..<n { novelty[i] /= maxValue }
        }
        return novelty
    }

    /// librosa.util.peak_pick, ported: a sample is a peak if it's the local
    /// max within its pre/post window, exceeds its local average by
    /// `delta`, and is at least `wait` steps past the last accepted peak.
    static func pickPeaks(
        _ x: [Float], preMax: Int, postMax: Int, preAvg: Int, postAvg: Int, delta: Float, wait: Int
    ) -> [Int] {
        guard !x.isEmpty else { return [] }
        var peaks: [Int] = []
        var lastPeak = -wait - 1

        for i in 0..<x.count {
            let loMax = max(0, i - preMax)
            let hiMax = min(x.count - 1, i + postMax)
            guard x[i] == x[loMax...hiMax].max() else { continue }

            let loAvg = max(0, i - preAvg)
            let hiAvg = min(x.count - 1, i + postAvg)
            let avg = x[loAvg...hiAvg].reduce(0, +) / Float(hiAvg - loAvg + 1)
            guard x[i] >= avg + delta else { continue }

            guard i - lastPeak > wait else { continue }
            peaks.append(i)
            lastPeak = i
        }
        return peaks
    }

    /// Section-boundary frame indices (always including 0 and `n - 1`).
    static func boundaryIndices(ssm: [[Float]], kernelRadius: Int, minGapSteps: Int) -> [Int] {
        let n = ssm.count
        guard n > 1 else { return [0] }
        let radius = max(1, min(kernelRadius, (n - 1) / 2))
        guard n >= 2 * radius + 2 else { return [0, n - 1] }

        let novelty = noveltyCurve(ssm: ssm, kernelSize: radius)
        let gap = max(1, minGapSteps)
        let peaks = pickPeaks(novelty, preMax: gap, postMax: gap, preAvg: gap, postAvg: gap, delta: 0.02, wait: gap)

        var bounds = Set(peaks)
        bounds.insert(0)
        bounds.insert(n - 1)
        return bounds.sorted()
    }

    /// Full pipeline: chroma self-similarity -> novelty boundaries -> pick
    /// the segment that's both most repeated elsewhere and highest-energy.
    static func pickHighlight(
        frames: ChromaFrames,
        trackDuration: TimeInterval,
        noveltyRadiusSeconds: Double,
        minBoundaryGapSeconds: Double,
        minDur: TimeInterval,
        maxDur: TimeInterval,
        targetDur: TimeInterval
    ) -> ClosedRange<TimeInterval> {
        let chroma = frames.chroma
        let n = chroma.count
        guard n > 0 else { return 0...min(trackDuration, targetDur) }
        guard n > 1 else { return 0...min(trackDuration, maxDur) }

        let hopSeconds = frames.frameTimes.count > 1 ? frames.frameTimes[1] - frames.frameTimes[0] : 1
        let kernelRadius = max(2, Int((noveltyRadiusSeconds / hopSeconds).rounded()))
        let minGapSteps = max(1, Int((minBoundaryGapSeconds / hopSeconds).rounded()))

        var ssm = [[Float]](repeating: [Float](repeating: 0, count: n), count: n)
        for i in 0..<n {
            ssm[i][i] = 1
            for j in (i + 1)..<n {
                let sim = dot(chroma[i], chroma[j])
                ssm[i][j] = sim
                ssm[j][i] = sim
            }
        }

        let boundaries = boundaryIndices(ssm: ssm, kernelRadius: kernelRadius, minGapSteps: minGapSteps)
        return scoreAndPickSegment(
            boundaries: boundaries, chroma: chroma, rms: frames.rms, frameTimes: frames.frameTimes,
            trackDuration: trackDuration, minDur: minDur, maxDur: maxDur, targetDur: targetDur
        )
    }

    private struct Segment {
        let t0: TimeInterval
        let t1: TimeInterval
        let feature: [Float]
        let rms: Float
    }

    private static func scoreAndPickSegment(
        boundaries: [Int], chroma: [[Float]], rms: [Float], frameTimes: [Double],
        trackDuration: TimeInterval, minDur: TimeInterval, maxDur: TimeInterval, targetDur: TimeInterval
    ) -> ClosedRange<TimeInterval> {
        var segments: [Segment] = []
        for i in 0..<(boundaries.count - 1) {
            let f0 = boundaries[i], f1 = boundaries[i + 1]
            guard f1 > f0 else { continue }
            let t0 = frameTimes[f0]
            let t1 = (i == boundaries.count - 2) ? trackDuration : frameTimes[f1]

            var mean = [Float](repeating: 0, count: chroma[f0].count)
            for f in f0..<f1 {
                for c in 0..<mean.count { mean[c] += chroma[f][c] }
            }
            let count = Float(f1 - f0)
            for c in 0..<mean.count { mean[c] /= count }
            let meanRMS = (f0..<f1).reduce(Float(0)) { $0 + rms[$1] } / count

            segments.append(Segment(t0: t0, t1: t1, feature: mean, rms: meanRMS))
        }
        guard !segments.isEmpty else { return 0...min(trackDuration, targetDur) }

        let rmsValues = segments.map(\.rms)
        let rmsMin = rmsValues.min() ?? 0
        let rmsRange = max((rmsValues.max() ?? 0) - rmsMin, 1e-9)

        var best: (t0: TimeInterval, t1: TimeInterval, score: Float)?
        var longest: (t0: TimeInterval, t1: TimeInterval, dur: TimeInterval)?

        for (i, segment) in segments.enumerated() {
            var repetition: Float = 0
            if segments.count > 1 {
                for (j, other) in segments.enumerated() where j != i {
                    repetition = max(repetition, cosineSimilarity(segment.feature, other.feature))
                }
            }
            let energy = (segment.rms - rmsMin) / rmsRange
            let score = repetition * (0.5 + 0.5 * energy)
            let dur = segment.t1 - segment.t0

            if dur >= minDur, best == nil || score > best!.score {
                best = (segment.t0, segment.t1, score)
            }
            if longest == nil || dur > longest!.dur {
                longest = (segment.t0, segment.t1, dur)
            }
        }

        let picked = best ?? (longest!.t0, longest!.t1, 0)
        var t0 = picked.t0, t1 = picked.t1
        if t1 - t0 > maxDur { t1 = t0 + targetDur }
        return t0...t1
    }

    private static func dot(_ a: [Float], _ b: [Float]) -> Float {
        var result: Float = 0
        for i in 0..<a.count { result += a[i] * b[i] }
        return result
    }
}
