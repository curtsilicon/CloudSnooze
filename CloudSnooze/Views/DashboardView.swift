// DashboardView.swift
// Main dashboard: renders widget cards from the active dashboard definition.

import SwiftUI

struct DashboardView: View {

    @Environment(AppState.self) private var appState
    @State private var isRefreshing   = false
    @State private var showAddWidget  = false

    private let registry = WidgetRegistry.shared

    var dashboard: Dashboard {
        appState.dashboardStore.dashboards.first ?? Dashboard.makeDefault()
    }

    var sortedWidgets: [DashboardWidget] {
        dashboard.widgets.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Ambient gradient header backdrop
                headerBackdrop

                ScrollView {
                    LazyVStack(spacing: 14) {
                        if sortedWidgets.isEmpty {
                            emptyDashboard
                        } else {
                            ForEach(sortedWidgets) { widget in
                                registry.view(for: widget)
                                    .padding(.horizontal)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }

                        Color.clear.frame(height: 20)
                    }
                }
                .refreshable {
                    await performRefresh()
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: - Header backdrop

    private var headerBackdrop: some View {
        LinearGradient(
            colors: [Color.deepSkyBlue.opacity(0.15), Color.clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 200)
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                if isRefreshing {
                    ProgressView()
                        .tint(.deepSkyBlue)
                        .scaleEffect(0.85)
                }

                Button {
                    Task { await performRefresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                }
                .tint(.deepSkyBlue)
            }
        }
    }

    // MARK: - Empty state

    private var emptyDashboard: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 60)
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 52, weight: .thin))
                .foregroundStyle(LinearGradient.primaryGradient)

            Text("No Widgets")
                .font(.title2.bold())
            Text("Add widgets to start monitoring\nyour cloud infrastructure.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Refresh

    private func performRefresh() async {
        isRefreshing = true
        await appState.runDiscoveryRefresh()
        isRefreshing = false
    }
}

// MARK: - Preview

#Preview {
    DashboardView()
        .environment(AppState.preview)
}
