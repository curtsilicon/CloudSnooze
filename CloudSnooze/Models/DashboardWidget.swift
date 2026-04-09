// DashboardWidget.swift
// Persisted widget definition stored per-dashboard.

import Foundation
import SwiftUI

// MARK: - DashboardWidget

struct DashboardWidget: Identifiable, Codable {
    let id:         UUID
    var type:       String            // matches CloudWidget.type
    var config:     [String: String]  // widget-specific key/value config
    var sortOrder:  Int

    init(id: UUID = .init(),
         type: String,
         config: [String: String] = [:],
         sortOrder: Int = 0) {
        self.id        = id
        self.type      = type
        self.config    = config
        self.sortOrder = sortOrder
    }
}

// MARK: - Dashboard

struct Dashboard: Identifiable, Codable {
    let id:        UUID
    var name:      String
    var widgets:   [DashboardWidget]
    var createdAt: Date

    init(id: UUID = .init(),
         name: String = "My Dashboard",
         widgets: [DashboardWidget] = [],
         createdAt: Date = .now) {
        self.id        = id
        self.name      = name
        self.widgets   = widgets
        self.createdAt = createdAt
    }

    // Factory: default dashboard shown after first connect
    static func makeDefault() -> Dashboard {
        let costWidget = DashboardWidget(
            type: WidgetTypeKey.costMonth,
            config: [:],
            sortOrder: 0
        )
        let statusWidget = DashboardWidget(
            type: WidgetTypeKey.serverStatus,
            config: [:],
            sortOrder: 1
        )
        let controlWidget = DashboardWidget(
            type: WidgetTypeKey.serverControls,
            config: [:],
            sortOrder: 2
        )
        let cpuWidget = DashboardWidget(
            type: WidgetTypeKey.cpuChart,
            config: [:],
            sortOrder: 3
        )
        return Dashboard(
            name: "My Dashboard",
            widgets: [costWidget, statusWidget, controlWidget, cpuWidget]
        )
    }
}

// MARK: - Widget type string constants

enum WidgetTypeKey {
    static let serverStatus   = "server_status"
    static let serverControls = "server_controls"
    static let cpuChart       = "cpu_chart"
    static let costMonth      = "cost_month"
}

// MARK: - DashboardStore (local JSON persistence)

@Observable
final class DashboardStore {

    private static let storageKey = "cloudremote.dashboards"

    var dashboards: [Dashboard] = []

    init() { load() }

    func save() {
        guard let data = try? JSONEncoder().encode(dashboards) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.storageKey),
            let decoded = try? JSONDecoder().decode([Dashboard].self, from: data)
        else {
            dashboards = [Dashboard.makeDefault()]
            return
        }
        dashboards = decoded.isEmpty ? [Dashboard.makeDefault()] : decoded
    }

    func add(_ dashboard: Dashboard) {
        dashboards.append(dashboard)
        save()
    }

    func remove(at offsets: IndexSet) {
        dashboards.remove(atOffsets: offsets)
        save()
    }

    func update(_ dashboard: Dashboard) {
        if let idx = dashboards.firstIndex(where: { $0.id == dashboard.id }) {
            dashboards[idx] = dashboard
            save()
        }
    }
}
