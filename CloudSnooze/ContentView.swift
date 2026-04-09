//
//  ContentView.swift
//  CloudSnooze
//
//  Created by dev on 3/13/26.
//

// RootView.swift
// Routes to onboarding or the main tab bar based on connection state.

import SwiftUI

struct ContentView: View {
    var body: some View {
        RootView()
    }
}

struct RootView: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.isConnected {
                MainTabView()
                    .transition(.opacity)
            } else {
                ConnectAWSView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.isConnected)
    }
}

// MARK: - Main Tab Bar

struct MainTabView: View {

    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "square.grid.2x2.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(.deepSkyBlue)
        .task {
            // Auto-discover on every fresh appearance (launch or after connect).
            // Skips if data is already populated to avoid double-fetching.
            if appState.discoveredInstances.isEmpty && appState.discoveredBuckets.isEmpty {
                await appState.runDiscoveryRefresh()
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AppState.preview)
}

