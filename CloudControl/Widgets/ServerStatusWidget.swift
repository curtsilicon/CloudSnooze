// ServerStatusWidget.swift
// Displays instance name, ID, type, state, and basic network info.

import SwiftUI

// MARK: - CloudWidget conformance

struct ServerStatusWidgetView: View, CloudWidget {
    static let type = WidgetTypeKey.serverStatus

    private let config: [String: String]

    @Environment(AppState.self) private var appState
    @State private var lastRefresh: Date?

    init(config: [String: String]) {
        self.config = config
    }

    func render() -> AnyView { AnyView(self) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Instance Status", icon: "server.rack")

            if appState.discoveredInstances.isEmpty {
                emptyState
            } else {
                ForEach(appState.discoveredInstances) { instance in
                    InstanceRow(instance: instance)
                    if instance.id != appState.discoveredInstances.last?.id {
                        Divider().padding(.leading, 4)
                    }
                }
            }

            if let ts = lastRefresh {
                Text("Updated \(ts, formatter: relativeFormatter)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .cloudCard()
        .onChange(of: appState.discoveredInstances) { _, _ in
            lastRefresh = .now
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "server.rack")
                .font(.largeTitle)
                .foregroundColor(.secondary.opacity(0.4))
            Text("No instances found")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Pull to refresh the dashboard")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Instance row

private struct InstanceRow: View {
    let instance: EC2Instance

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Instance type chip
            Text(instance.instanceType)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.deepSkyBlue)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.deepSkyBlue.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(instance.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(instance.id)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                Text(instance.region)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.8))

                HStack(spacing: 10) {
                    if let ip = instance.publicIp {
                        Label(ip, systemImage: "globe")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if let ip = instance.privateIp {
                        Label(ip, systemImage: "network")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            StatusBadge(status: instance.state.displayName)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Helpers

private let relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .short
    return f
}()

// MARK: - Preview

#Preview {
    ScrollView {
        ServerStatusWidgetView(config: [:])
            .padding()
    }
    .environment(AppState.preview)
    .background(Color.cloudWhite)
}
