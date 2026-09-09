//
//  SelfSimilarityNoveltyTests.swift
//  app-v1Tests
//
//  Pure-math tests for the Foote novelty / repetition-scoring pipeline —
//  no audio decoding involved, so these run against synthetic
//  self-similarity matrices and chroma frames instead of real files.
//

import Foundation
import Testing
@testable import app_v1

@Suite struct SelfSimilarityNoveltyTests {
    // MARK: - checkerboardKernel

    @Test func checkerboardKernelIsSymmetricWithAPositiveCenter() {
        let kernel = SelfSimilarityNovelty.checkerboardKernel(size: 2)
        #expect(kernel.count == 5)
        #expect(kernel[0].count == 5)
        #expect(abs(kernel[2][2] - 1.0) < 1e-6) // center: sign(0)*sign(0)*gauss(0)*gauss(0)

        for i in 0..<5 {
            for j in 0..<5 {
                #expect(abs(kernel[i][j] - kernel[j][i]) < 1e-6)
            }
        }

        // Same-side quadrants are positive, opposite-side quadrants negative --
        // the actual "checkerboard" signature the novelty method depends on.
        #expect(kernel[0][0] > 0)
        #expect(kernel[4][4] > 0)
        #expect(kernel[0][4] < 0)
        #expect(kernel[4][0] < 0)
    }

    // MARK: - noveltyCurve / boundaryIndices

    /// A block-diagonal SSM: two "sections" that are internally similar but
    /// dissimilar to each other, transitioning at index 20 -- the simplest
    /// synthetic stand-in for a verse-to-chorus boundary.
    private func twoSectionSSM(size: Int, boundary: Int) -> [[Float]] {
        var ssm = [[Float]](repeating: [Float](repeating: 0, count: size), count: size)
        for i in 0..<size {
            for j in 0..<size {
                ssm[i][j] = (i < boundary) == (j < boundary) ? 0.9 : 0.1
            }
        }
        return ssm
    }

    @Test func noveltyCurvePeaksNearASectionBoundary() {
        let ssm = twoSectionSSM(size: 40, boundary: 20)
        let novelty = SelfSimilarityNovelty.noveltyCurve(ssm: ssm, kernelSize: 5)

        let peakIndex = novelty.indices.max { novelty[$0] < novelty[$1] }
        #expect(peakIndex != nil)
        if let peakIndex {
            #expect(abs(peakIndex - 20) <= 2, "expected the novelty peak near index 20, got \(peakIndex)")
        }
    }

    @Test func boundaryIndicesAlwaysIncludeTheEdges() {
        let ssm = twoSectionSSM(size: 40, boundary: 20)
        let bounds = SelfSimilarityNovelty.boundaryIndices(ssm: ssm, kernelRadius: 5, minGapSteps: 5)
        #expect(bounds.first == 0)
        #expect(bounds.last == 39)
    }

    @Test func boundaryIndicesFindsNoBoundaryAtTheMiddleOfAUniformTrack() {
        // No real structure to find. (The novelty curve's un-analyzed edge
        // padding can still create a boundary near the very start/end --
        // see noveltyCurve's doc comment -- but a genuine midpoint switch
        // should never fire for a track that's uniformly self-similar.)
        let ssm = [[Float]](repeating: [Float](repeating: 1, count: 40), count: 40)
        let bounds = SelfSimilarityNovelty.boundaryIndices(ssm: ssm, kernelRadius: 5, minGapSteps: 5)
        #expect(!bounds.contains(20))
    }

    // MARK: - pickPeaks

    @Test func pickPeaksFindsASingleClearSpike() {
        let x: [Float] = [0, 0, 0, 1, 0, 0, 0]
        let peaks = SelfSimilarityNovelty.pickPeaks(x, preMax: 2, postMax: 2, preAvg: 2, postAvg: 2, delta: 0.1, wait: 1)
        #expect(peaks == [3])
    }

    @Test func pickPeaksEnforcesMinimumWaitBetweenPeaks() {
        let x: [Float] = [0, 1, 0, 1, 0]
        let peaks = SelfSimilarityNovelty.pickPeaks(x, preMax: 1, postMax: 1, preAvg: 1, postAvg: 1, delta: 0.1, wait: 3)
        #expect(peaks == [1]) // the second spike at index 3 is within `wait` of the first
    }

    @Test func pickPeaksReturnsNothingForAFlatCurve() {
        let x = [Float](repeating: 0, count: 10)
        let peaks = SelfSimilarityNovelty.pickPeaks(x, preMax: 2, postMax: 2, preAvg: 2, postAvg: 2, delta: 0.02, wait: 2)
        #expect(peaks.isEmpty)
    }

    // MARK: - pickHighlight (full pipeline on synthetic chroma)

    /// 30 one-second frames: a unique, quiet "verse" (0-10s) followed by a
    /// distinct pattern repeated twice as a loud "chorus" (10-20s, 20-30s).
    /// The highlight should land in chorus territory, not the verse.
    private func verseChorusFrames() -> ChromaFrames {
        func unitVector(hot index: Int) -> [Float] {
            var v = [Float](repeating: 0, count: 12)
            v[index] = 1
            return v
        }
        let verse = unitVector(hot: 0)
        let chorus = unitVector(hot: 6)

        var chroma: [[Float]] = []
        var rms: [Float] = []
        var frameTimes: [Double] = []
        for t in 0..<30 {
            frameTimes.append(Double(t))
            if t < 10 {
                chroma.append(verse)
                rms.append(0.1)
            } else {
                chroma.append(chorus)
                rms.append(1.0)
            }
        }
        return ChromaFrames(chroma: chroma, rms: rms, frameTimes: frameTimes)
    }

    @Test func pickHighlightPrefersTheRepeatedHighEnergySection() {
        let frames = verseChorusFrames()
        let range = SelfSimilarityNovelty.pickHighlight(
            frames: frames, trackDuration: 30,
            noveltyRadiusSeconds: 3, minBoundaryGapSeconds: 5,
            minDur: 5, maxDur: 15, targetDur: 8
        )
        #expect(range.lowerBound >= 9, "expected the highlight in chorus territory (>=9s), got \(range)")
        #expect(range.upperBound <= 30)
    }

    @Test func pickHighlightTrimsAnOverlongSegmentToTargetDuration() {
        let frames = verseChorusFrames()
        let range = SelfSimilarityNovelty.pickHighlight(
            frames: frames, trackDuration: 30,
            noveltyRadiusSeconds: 3, minBoundaryGapSeconds: 5,
            minDur: 5, maxDur: 8, targetDur: 6
        )
        #expect(range.upperBound - range.lowerBound <= 6 + 1e-6)
    }

    @Test func pickHighlightHandlesATrackShorterThanOneFrame() {
        let frames = ChromaFrames(chroma: [], rms: [], frameTimes: [])
        let range = SelfSimilarityNovelty.pickHighlight(
            frames: frames, trackDuration: 5,
            noveltyRadiusSeconds: 8, minBoundaryGapSeconds: 10,
            minDur: 10, maxDur: 30, targetDur: 30
        )
        #expect(range.lowerBound == 0)
        #expect(range.upperBound <= 5)
    }
}
