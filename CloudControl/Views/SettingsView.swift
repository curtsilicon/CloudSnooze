// SettingsView.swift
// App settings: account info, manual rescan, credential management.

import SwiftUI

struct SettingsView: View {

    @Environment(AppState.self) private var appState
    @State private var showDisconnectAlert   = false
    @State private var isRescanning          = false
    @State private var rescanComplete        = false
    @State private var showAddResourceSheet  = false
    @State private var arnInput              = ""
    @State private var arnError:   String?   = nil

    var body: some View {
        NavigationStack {
            List {
                accountSection
                resourcesSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .listStyle(.insetGrouped)
            .alert("Disconnect Account?", isPresented: $showDisconnectAlert) {
                Button("Disconnect", role: .destructive) {
                    appState.disconnect()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove your stored credentials from the device. You will need to reconnect to use CloudRemote.")
            }
            .sheet(isPresented: $showAddResourceSheet) {
                AddResourceSheet(arnInput: $arnInput, arnError: $arnError) {
                    addResource()
                }
            }
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section {
            if let creds = appState.credentials {
                LabeledContent("Region") {
                    Text(creds.region)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                LabeledContent("Access Key") {
                    Text(maskedKey(creds.accessKeyId))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            Button(role: .destructive) {
                showDisconnectAlert = true
            } label: {
                Label("Disconnect Account", systemImage: "power.circle")
            }
        } header: {
            Text("Account")
        } footer: {
            Text("Credentials are stored in the iOS Keychain and never leave this device except when calling cloud APIs.")
        }
    }

    private var resourcesSection: some View {
        Section {
            // Manual rescan
            Button {
                Task { await rescan() }
            } label: {
                HStack {
                    Label("Refresh Cloud Resources", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundColor(.primary)
                    Spacer()
                    if isRescanning {
                        ProgressView().tint(.deepSkyBlue)
                    } else if rescanComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.statusRunning)
                    }
                }
            }
            .disabled(isRescanning)

            // Add resource by ARN
            Button {
                arnInput = ""
                arnError = nil
                showAddResourceSheet = true
            } label: {
                Label("Add Resource by ARN", systemImage: "plus.circle")
                    .foregroundColor(.primary)
            }

            // Discovered instances
            if !appState.discoveredInstances.isEmpty {
                DisclosureGroup {
                    ForEach(appState.discoveredInstances) { inst in
                        HStack {
                            Image(systemName: "server.rack")
                                .foregroundColor(.deepSkyBlue)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(inst.name).font(.subheadline)
                                Text(inst.id)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            StatusBadge(status: inst.state.displayName)
                        }
                        .padding(.vertical, 4)
                    }
                } label: {
                    Label("EC2 Instances (\(appState.discoveredInstances.count))",
                          systemImage: "server.rack")
                }
            }

            // Discovered buckets
            if !appState.discoveredBuckets.isEmpty {
                DisclosureGroup {
                    ForEach(appState.discoveredBuckets) { bucket in
                        HStack {
                            Image(systemName: "externaldrive.connected.to.line.below")
                                .foregroundColor(.cloudIndigo)
                                .frame(width: 24)
                            Text(bucket.name)
                                .font(.subheadline)
                        }
                        .padding(.vertical, 4)
                    }
                } label: {
                    Label("S3 Buckets (\(appState.discoveredBuckets.count))",
                          systemImage: "externaldrive.connected.to.line.below")
                }
            }

        } header: {
            Text("Resources")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("App", value: "CloudRemote")
            LabeledContent("Version", value: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            LabeledContent("Build", value: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")

            Link(destination: URL(string: "https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html")!) {
                Label("IAM Credentials Guide", systemImage: "link")
            }
            .tint(.deepSkyBlue)
        }
    }

    // MARK: - Actions

    private func rescan() async {
        isRescanning  = true
        rescanComplete = false
        await appState.runDiscoveryRefresh()
        isRescanning   = false
        rescanComplete = true
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        rescanComplete = false
    }

    private func addResource() {
        arnError = nil
        guard ARNParser.isValid(arnInput) else {
            arnError = "Invalid ARN format. Expected: arn:partition:service:region:account:resource"
            return
        }
        // Resource is valid – close sheet (further verification could be added here)
        showAddResourceSheet = false
    }

    // MARK: - Helpers

    private func maskedKey(_ key: String) -> String {
        guard key.count > 4 else { return "****" }
        return String(key.prefix(4)) + String(repeating: "•", count: 12)
    }
}

// MARK: - Add Resource Sheet

private struct AddResourceSheet: View {
    @Binding var arnInput: String
    @Binding var arnError: String?
    let onAdd: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("arn:aws:ec2:us-east-1:123456789012:instance/i-abc123",
                              text: $arnInput, axis: .vertical)
                        .lineLimit(2...4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Resource ARN")
                } footer: {
                    if let err = arnError {
                        Text(err)
                            .foregroundColor(.statusStopped)
                    } else {
                        Text("Paste the full ARN of the resource you want to add to your dashboard.")
                    }
                }
            }
            .navigationTitle("Add Resource")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { onAdd() }
                        .disabled(arnInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environment(AppState.preview)
}
