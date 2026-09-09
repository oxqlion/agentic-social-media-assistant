//
//  PendingPromptRouter.swift
//  app-v1
//
//  Hand-off point between NewPostIntent (runs in-process, possibly before
//  any SwiftUI view exists yet) and ContentView. The intent writes here;
//  ContentView reads it once on appear (cold launch) and again on every
//  change (warm launch, app already in the foreground) and clears it after
//  consuming — so a stale prompt never re-fires on an unrelated relaunch.
//

import Foundation

@Observable
final class PendingPromptRouter {
    static let shared = PendingPromptRouter()

    private init() {}

    var pendingPrompt: String?
}
