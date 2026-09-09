//
//  AppShortcuts.swift
//  app-v1
//
//  Surfaces NewPostIntent to Siri, Spotlight, and the Shortcuts app. No
//  Siri capability/entitlement needed — the AppIntents framework (unlike
//  the older SiriKit/Intents.framework path) exposes phrases automatically
//  from this provider.
//
//  `prompt` is a plain String, not an AppEntity/AppEnum, so this SDK's
//  App Intents validator won't allow it inside a phrase pattern (phrases
//  are statically parsed without running the app, so slots need a fixed
//  vocabulary). Free-form phrases only trigger the intent; Siri then
//  collects `prompt` itself via its `requestValueDialog` ("What's the post
//  about?"), which is the right shape anyway for open-ended dictation.
//

import AppIntents

struct AppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewPostIntent(),
            phrases: [
                "New post in \(.applicationName)",
                "Start a post in \(.applicationName)",
                "Create a post in \(.applicationName)"
            ],
            shortTitle: "New Post",
            systemImageName: "square.and.pencil"
        )
    }
}
