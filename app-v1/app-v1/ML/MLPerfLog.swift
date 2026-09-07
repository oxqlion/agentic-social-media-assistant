//
//  MLPerfLog.swift
//  app-v1
//
//  Development-time timing/logging for the on-device ML pipeline. Compiled
//  out of release builds entirely.
//

import Foundation
import os

enum MLPerfLog {
    static let logger = Logger(subsystem: "com.c3.app-v1", category: "ml")

#if DEBUG
    private static let signposter = OSSignposter(logger: logger)

    /// Measures and logs a synchronous stage, returning its result.
    static func measure<T>(_ stage: StaticString, _ work: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(stage)
        let start = DispatchTime.now()
        defer {
            signposter.endInterval(stage, state)
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            logger.debug("\(stage, privacy: .public): \(ms, format: .fixed(precision: 2))ms")
        }
        return try work()
    }

    /// Measures and logs an async stage, returning its result.
    static func measure<T>(_ stage: StaticString, _ work: () async throws -> T) async rethrows -> T {
        let state = signposter.beginInterval(stage)
        let start = DispatchTime.now()
        defer {
            signposter.endInterval(stage, state)
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            logger.debug("\(stage, privacy: .public): \(ms, format: .fixed(precision: 2))ms")
        }
        return try await work()
    }

    static func info(_ message: @autoclosure () -> String) {
        let resolved = message()
        logger.debug("\(resolved, privacy: .public)")
    }
#else
    @inline(__always)
    static func measure<T>(_ stage: StaticString, _ work: () throws -> T) rethrows -> T {
        try work()
    }

    @inline(__always)
    static func measure<T>(_ stage: StaticString, _ work: () async throws -> T) async rethrows -> T {
        try await work()
    }

    @inline(__always)
    static func info(_ message: @autoclosure () -> String) {}
#endif
}
