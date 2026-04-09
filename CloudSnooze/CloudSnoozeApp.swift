//
//  CloudSnoozeApp.swift
//  CloudSnooze
//
//  Created by dev on 3/13/26.
//

// CloudSnoozeApp.swift
// App entry point. Injects AppState and routes to onboarding or dashboard.

import SwiftUI

@main
struct CloudSnoozeApp: App {

    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }
    }
}

