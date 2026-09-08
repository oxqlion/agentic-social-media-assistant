//
//  MusicEmbeddingStoreTests.swift
//  app-v1Tests
//
//  Round-trip persistence plus the diff/prune logic MusicIndexer relies on
//  to avoid re-encoding songs it's already cached, isolated to a temp
//  directory per test so this never touches the app's real on-device index.
//

import Foundation
import Testing
@testable import app_v1

@Suite struct MusicEmbeddingStoreTests {
    private func makeTempStore() -> MusicEmbeddingStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MusicEmbeddingStoreTests-\(UUID().uuidString)", isDirectory: true)
        return MusicEmbeddingStore(rootDirectory: root)
    }

    private func makeTrack(id: UInt64) -> IndexedTrack {
        IndexedTrack(
            persistentID: id, embedding: [Float(id)], title: "Song \(id)", artist: "Artist \(id)",
            duration: 180, analyzedRange: 45...55
        )
    }

    @Test func addAndRetrieve() async throws {
        let store = makeTempStore()
        try await store.add(makeTrack(id: 1))

        let all = try await store.allTracks()
        #expect(all.count == 1)
        #expect(all.first?.persistentID == 1)
        #expect(all.first?.title == "Song 1")
        #expect(try await store.count == 1)
    }

    @Test func persistsAcrossInstances() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MusicEmbeddingStoreTests-\(UUID().uuidString)", isDirectory: true)

        let first = MusicEmbeddingStore(rootDirectory: root)
        try await first.add(makeTrack(id: 42))

        let second = MusicEmbeddingStore(rootDirectory: root)
        let reloaded = try await second.allTracks()
        #expect(reloaded.count == 1)
        #expect(reloaded.first?.persistentID == 42)
    }

    @Test func cachedPersistentIDsReflectsWhatsStored() async throws {
        let store = makeTempStore()
        try await store.add(makeTrack(id: 1))
        try await store.add(makeTrack(id: 2))

        let ids = try await store.cachedPersistentIDs()
        #expect(ids == [1, 2])
    }

    @Test func pruneRemovesTracksNoLongerInLibrary() async throws {
        let store = makeTempStore()
        try await store.add(makeTrack(id: 1))
        try await store.add(makeTrack(id: 2))
        try await store.add(makeTrack(id: 3))

        // Simulates song 2 being deleted from the device between scans.
        try await store.pruneTracks(notIn: [1, 3])

        let remaining = try await store.allTracks()
        #expect(Set(remaining.map(\.persistentID)) == [1, 3])
    }

    @Test func addingSamePersistentIDReplacesEntry() async throws {
        let store = makeTempStore()
        try await store.add(makeTrack(id: 1))
        let updated = IndexedTrack(
            persistentID: 1, embedding: [9, 9], title: "Updated Title", artist: nil,
            duration: 200, analyzedRange: 10...20
        )
        try await store.add(updated)

        let all = try await store.allTracks()
        #expect(all.count == 1)
        #expect(all.first?.title == "Updated Title")
    }

    @Test func removeAllClearsStore() async throws {
        let store = makeTempStore()
        try await store.add(makeTrack(id: 1))
        try await store.removeAll()
        #expect(try await store.allTracks().isEmpty)
    }
}
