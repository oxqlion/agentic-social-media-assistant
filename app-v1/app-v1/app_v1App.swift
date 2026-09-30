//
//  app_v1App.swift
//  app-v1
//
//  Created by Rafi Abhista on 07/09/26.
//

import SwiftUI

@main
struct app_v1App: App {
    init() {
        // OS27 case study test mode: every controlled benchmark trial
        // starts from identical, empty preference memory. See
        // CaseStudy/CaseStudyFixtures.swift.
        if CaseStudyFixtures.isEnabled {
            MemoryManager.shared.resetAll()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
