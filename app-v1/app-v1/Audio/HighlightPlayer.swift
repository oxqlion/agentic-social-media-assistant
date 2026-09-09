//
//  HighlightPlayer.swift
//  app-v1
//
//  Plays just a track's detected highlight window (TrackHighlightDetecting's
//  output) instead of the whole song: seeks to the range's start, plays,
//  and auto-pauses back to the start when it reaches the range's end -- so
//  a second tap always replays the highlight from the top instead of
//  falling through into the rest of the track.
//
//  UI-only state (not part of AgentFlowModel, which holds what the agents
//  produced, not transient playback state) -- owned by whichever view shows
//  a play button, and MainActor-isolated by this app's default.
//

import AVFoundation
import Foundation

@Observable
final class HighlightPlayer {
    private(set) var isPlaying = false

    private var player: AVPlayer?
    private var boundaryObserver: Any?
    private var currentURL: URL?
    private var currentRange: ClosedRange<TimeInterval>?

    /// Tapping the currently-playing track/range pauses it; tapping it
    /// again resumes from where it left off; tapping a different
    /// track/range starts that one fresh from the beginning.
    func toggle(url: URL, range: ClosedRange<TimeInterval>) {
        guard currentURL == url, currentRange == range else {
            play(url: url, range: range)
            return
        }
        isPlaying ? pause() : resume()
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    /// Releases the player entirely -- call when navigating away so
    /// playback doesn't continue in the background unexpectedly.
    func stop() {
        pause()
        if let boundaryObserver {
            player?.removeTimeObserver(boundaryObserver)
        }
        boundaryObserver = nil
        player = nil
        currentURL = nil
        currentRange = nil
    }

    private func play(url: URL, range: ClosedRange<TimeInterval>) {
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let newPlayer = AVPlayer(playerItem: AVPlayerItem(url: url))
        player = newPlayer
        currentURL = url
        currentRange = range

        let endTime = CMTime(seconds: range.upperBound, preferredTimescale: 600)
        boundaryObserver = newPlayer.addBoundaryTimeObserver(forTimes: [NSValue(time: endTime)], queue: .main) { [weak self] in
            self?.pause()
            self?.seekToRangeStart()
        }

        seekToRangeStart()
        newPlayer.play()
        isPlaying = true
    }

    private func resume() {
        // A pause right at the boundary leaves currentTime sitting at (or
        // just past) the end -- resuming from there would play nothing, so
        // treat "resume while at the end" as "replay from the start".
        if let player, let currentRange, player.currentTime().seconds >= currentRange.upperBound - 0.05 {
            seekToRangeStart()
        }
        player?.play()
        isPlaying = true
    }

    private func seekToRangeStart() {
        guard let currentRange else { return }
        let startTime = CMTime(seconds: currentRange.lowerBound, preferredTimescale: 600)
        player?.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
