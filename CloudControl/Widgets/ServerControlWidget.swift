// ServerControlWidget.swift
// Provides Start / Stop / Reboot buttons for EC2 instances.

import SwiftUI

// MARK: - CloudWidget conformance

struct ServerControlWidgetView: View, CloudWidget {
    static let type = WidgetTypeKey.serverControls

    private let config: [String: String]

    @Environment(AppState.self) private var appState
    @State private var actionInProgress: String?   // instance ID currently being actioned
    @State private var actionError:      String?
    @State private var showStopAlert  = false
    @State private var pendingStop:    EC2Instance?

    private let ec2 = EC2Service()

    init(config: [String: String]) {
        self.config = config
    }

    func render() -> AnyView { AnyView(self) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Instance Controls", icon: "switch.2")

            if let err = actionError {
                ErrorBanner(message: err) { actionError = nil }
            } else if appState.discoveredInstances.isEmpty {
                emptyState
            } else {
                ForEach(appState.discoveredInstances) { instance in
                    InstanceControlRow(
                        instance:    instance,
                        isActioning: actionInProgress == instance.id,
                        onStart:  { triggerAction(.start,  instance: instance) },
                        onStop:   {
                            pendingStop   = instance
                            showStopAlert = true
                        },
                        onReboot: { triggerAction(.reboot, instance: instance) }
                    )
                    if instance.id != appState.discoveredInstances.last?.id {
                        Divider().padding(.leading, 4)
                    }
                }
            }
        }
        .padding()
        .cloudCard()
        .alert("Stop Instance?", isPresented: $showStopAlert, presenting: pendingStop) { inst in
            Button("Stop", role: .destructive) {
                triggerAction(.stop, instance: inst)
            }
            Button("Cancel", role: .cancel) {}
        } message: { inst in
            Text("Stopping \"\(inst.name)\" will shut it down. Continue?")
        }
    }

    // MARK: - Actions

    private enum InstanceAction { case start, stop, reboot }

    private func triggerAction(_ action: InstanceAction, instance: EC2Instance) {
        guard let creds = appState.credentials else { return }
        Task {
            actionInProgress = instance.id
            actionError = nil
            do {
                let regionalCreds = AWSCredentials(
                    accessKeyId:     creds.accessKeyId,
                    secretAccessKey: creds.secretAccessKey,
                    region:          instance.region
                )
                switch action {
                case .start:  try await ec2.startInstances(instanceIds: [instance.id],  credentials: regionalCreds)
                case .stop:   try await ec2.stopInstances(instanceIds: [instance.id],   credentials: regionalCreds)
                case .reboot: try await ec2.rebootInstances(instanceIds: [instance.id], credentials: regionalCreds)
                }
                // Poll this instance's region until state stabilises, updating appState directly
                try await pollUntilStable(instanceId: instance.id, credentials: regionalCreds)
            } catch {
                actionError = error.localizedDescription
            }
            actionInProgress = nil
        }
    }

    /// Polls DescribeInstances every 5 s until the target instance leaves a transient state.
    private func pollUntilStable(instanceId: String, credentials: AWSCredentials) async throws {
        for attempt in 1...24 {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            let fresh = try await ec2.describeInstances(credentials: credentials)
            // Merge fresh results into appState.discoveredInstances (same region only)
            await MainActor.run {
                var updated = appState.discoveredInstances
                for freshInstance in fresh {
                    if let idx = updated.firstIndex(where: { $0.id == freshInstance.id }) {
                        updated[idx] = freshInstance
                    }
                }
                appState.discoveredInstances = updated
            }
            if let target = fresh.first(where: { $0.id == instanceId }) {
                print("[EC2Control] poll \(attempt): \(instanceId) state=\(target.state.rawValue)")
                if !target.state.isTransient { break }
            } else {
                break
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "switch.2")
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

// MARK: - Instance control row

private struct InstanceControlRow: View {
    let instance:    EC2Instance
    let isActioning: Bool
    let onStart:  () -> Void
    let onStop:   () -> Void
    let onReboot: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(instance.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(instance.id)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(instance.region)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                Spacer()
                if isActioning {
                    ProgressView().scaleEffect(0.8).tint(.deepSkyBlue)
                } else {
                    StatusBadge(status: instance.state.displayName)
                }
            }

            HStack(spacing: 10) {
                ControlButton(
                    title:    "Start",
                    icon:     "play.fill",
                    color:    .statusRunning,
                    disabled: instance.state.isRunning || instance.state.isTransient || isActioning,
                    action:   onStart
                )
                ControlButton(
                    title:    "Stop",
                    icon:     "stop.fill",
                    color:    .statusStopped,
                    disabled: instance.state.isStopped || instance.state.isTransient || isActioning,
                    action:   onStop
                )
                ControlButton(
                    title:    "Reboot",
                    icon:     "arrow.clockwise",
                    color:    .deepSkyBlue,
                    disabled: !instance.state.isRunning || isActioning,
                    action:   onReboot
                )
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Control button

private struct ControlButton: View {
    let title:    String
    let icon:     String
    let color:    Color
    let disabled: Bool
    let action:   () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(disabled ? .secondary : color)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    (disabled ? Color.secondary : color).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10)
                )
        }
        .disabled(disabled)
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        ServerControlWidgetView(config: [:])
            .padding()
    }
    .environment(AppState.preview)
    .background(Color.cloudWhite)
}
