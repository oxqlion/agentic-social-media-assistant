//
//  ChromaFeatureExtractorTests.swift
//  app-v1Tests
//
//  Exercises the STFT/chroma-binning math directly on synthetic sine waves
//  (no real audio file needed) so a frequency->pitch-class mapping
//  regression shows up independently of decoding or model correctness.
//

import Foundation
import Testing
@testable import app_v1

@Suite struct ChromaFeatureExtractorTests {
    private let sampleRate: Double = 22_050

    private func sineWave(frequency: Double, seconds: Double) -> [Float] {
        let count = Int(seconds * sampleRate)
        return (0..<count).map { i in
            Float(sin(2 * Double.pi * frequency * Double(i) / sampleRate))
        }
    }

    @Test func shortTrackProducesNoFrames() {
        let samples = sineWave(frequency: 440, seconds: 0.05) // shorter than one FFT window
        let frames = ChromaFeatureExtractor.extract(samples: samples, sampleRate: sampleRate)
        #expect(frames.chroma.isEmpty)
        #expect(frames.rms.isEmpty)
    }

    @Test func aSineToneConcentratesEnergyInTheACromaBin() {
        // A4 = 440Hz = pitch class 9 (C=0, C#=1, ..., A=9).
        let samples = sineWave(frequency: 440, seconds: 2)
        let frames = ChromaFeatureExtractor.extract(samples: samples, sampleRate: sampleRate)
        #expect(!frames.chroma.isEmpty)

        for bins in frames.chroma {
            let aBin = 9
            let loudest = bins.indices.max { bins[$0] < bins[$1] }
            #expect(loudest == aBin, "expected pitch class \(aBin) (A) loudest, got \(loudest as Any): \(bins)")
        }
    }

    @Test func aHigherOctaveSineStillMapsToTheSamePitchClass() {
        // A5 = 880Hz -- one octave above A4, same pitch class (9).
        let samples = sineWave(frequency: 880, seconds: 2)
        let frames = ChromaFeatureExtractor.extract(samples: samples, sampleRate: sampleRate)
        #expect(!frames.chroma.isEmpty)

        let bins = frames.chroma[frames.chroma.count / 2]
        let loudest = bins.indices.max { bins[$0] < bins[$1] }
        #expect(loudest == 9)
    }

    @Test func chromaFramesAreL2Normalized() {
        let samples = sineWave(frequency: 440, seconds: 1)
        let frames = ChromaFeatureExtractor.extract(samples: samples, sampleRate: sampleRate)

        for bins in frames.chroma {
            let normSquared = bins.reduce(Float(0)) { $0 + $1 * $1 }
            #expect(abs(normSquared - 1.0) < 0.01)
        }
    }

    @Test func silenceProducesLowRMS() {
        let samples = [Float](repeating: 0, count: Int(sampleRate))
        let frames = ChromaFeatureExtractor.extract(samples: samples, sampleRate: sampleRate)
        #expect(frames.rms.allSatisfy { $0 < 0.0001 })
    }

    @Test func frameTimesAdvanceByHopLength() {
        let samples = sineWave(frequency: 440, seconds: 1)
        let frames = ChromaFeatureExtractor.extract(samples: samples, sampleRate: sampleRate)
        guard frames.frameTimes.count > 1 else {
            Issue.record("expected more than one frame")
            return
        }
        let expectedHop = Double(ChromaFeatureExtractor.hopLength) / sampleRate
        #expect(abs((frames.frameTimes[1] - frames.frameTimes[0]) - expectedHop) < 1e-9)
    }
}
