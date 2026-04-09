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
        VStack(alignment: .leading, spacing: 8) {
            // Top row: type chip + name + status badge
            HStack(alignment: .center, spacing: 10) {
                Text(instance.instanceType)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.deepSkyBlue)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.deepSkyBlue.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 1) {
                    Text(instance.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(instance.id)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(instance.region)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }

                Spacer()

                StatusBadge(status: instance.state.displayName)
            }

            // IP rows — full width below the header
            if instance.publicIp != nil || instance.privateIp != nil {
                VStack(spacing: 4) {
                    if let ip = instance.publicIp  { IPRow(label: "Public",  ip: ip) }
                    if let ip = instance.privateIp { IPRow(label: "Private", ip: ip) }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - IP Row

private struct IPRow: View {
    let label: String
    let ip:    String

    @State private var copied = false

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 38, alignment: .leading)

            Text(ip)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary)

            Spacer()

            Button {
                UIPasteboard.general.string = ip
                withAnimation(.easeInOut(duration: 0.15)) { copied = true }
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    withAnimation { copied = false }
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(copied ? .statusRunning : .secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(.tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 7))
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
