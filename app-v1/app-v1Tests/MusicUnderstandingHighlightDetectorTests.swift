//
//  MusicUnderstandingHighlightDetectorTests.swift
//  app-v1Tests
//
//  Covers the pure section-selection logic (highest-pace section, clamped to
//  10–30s) without needing the MusicUnderstanding framework or real audio.
//

import Testing
import Foundation
@testable import app_v1

@Suite struct MusicUnderstandingHighlightDetectorTests {
    typealias Detector = MusicUnderstandingHighlightDetector
    private func span(_ s: Double, _ e: Double) -> Detector.Span { .init(start: s, end: e) }

    @Test func picksTheHighestPaceSection() throws {
        let sections = [span(0, 20), span(20, 50), span(50, 80)]
        let pace = [
            Detector.PacedSpan(span: span(0, 20), pace: 0.2),
            Detector.PacedSpan(span: span(20, 50), pace: 0.9),
            Detector.PacedSpan(span: span(50, 80), pace: 0.5)
        ]
        let range = try Detector.pickHighlight(sections: sections, pace: pace)
        #expect(range == 20...50)
    }

    @Test func clampsLongSectionsToMaxAndKeepsStart() throws {
        let range = try Detector.pickHighlight(sections: [span(10, 100)], pace: [])
        #expect(range == 10...40)
    }

    @Test func extendsShortSectionsToTheMinimum() throws {
        let range = try Detector.pickHighlight(sections: [span(5, 8)], pace: [])
        #expect(range == 5...15)
    }

    @Test func fallsBackToLongestSectionWithoutPaceData() throws {
        let range = try Detector.pickHighlight(sections: [span(0, 12), span(12, 40)], pace: [])
        #expect(range == 12...40)
    }

    @Test func throwsWhenThereAreNoSections() {
        #expect(throws: MusicUnderstandingHighlightDetectorError.self) {
            try Detector.pickHighlight(sections: [], pace: [])
        }
    }
}
