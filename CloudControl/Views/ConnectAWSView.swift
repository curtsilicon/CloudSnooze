// ConnectAWSView.swift
// Onboarding screen – enter credentials, test connection, then connect.

import SwiftUI

// MARK: - ViewModel

@Observable
final class ConnectViewModel {

    var accessKey    = ""
    var secretKey    = ""
    var isTesting    = false
    var testResult:  TestResult?

    enum TestResult {
        case success
        case failure(String)
    }

    var canConnect: Bool {
        !accessKey.trimmingCharacters(in: .whitespaces).isEmpty &&
        !secretKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @MainActor
    func testConnection() async {
        isTesting  = true
        testResult = nil
        // Use DescribeRegions as a lightweight credential check — no region picker needed
        let creds = AWSCredentials(
            accessKeyId:     accessKey.trimmingCharacters(in: .whitespaces),
            secretAccessKey: secretKey.trimmingCharacters(in: .whitespaces),
            region:          "us-east-1"
        )
        do {
            let ec2 = EC2Service()
            _ = try await ec2.describeRegions(credentials: creds)
            testResult = .success
        } catch {
            testResult = .failure(error.localizedDescription)
        }
        isTesting = false
    }
}

// MARK: - View

struct ConnectAWSView: View {

    @Environment(AppState.self) private var appState

    @State private var vm = ConnectViewModel()
    @State private var showSecretKey = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    heroSection
                    credentialsCard
                    testResultBanner
                    actionButtons
                    securityNote
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Sub-views

    private var heroSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient.primaryGradient)
                    .frame(width: 80, height: 80)
                Image(systemName: "cloud.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(.white)
            }
            .shadow(color: Color.deepSkyBlue.opacity(0.4), radius: 16, y: 6)

            Text("CloudRemote")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("Connect your cloud account to start\nmonitoring and controlling infrastructure.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
    }

    private var credentialsCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Credentials")
                .font(.headline)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                // Access Key
                VStack(alignment: .leading, spacing: 6) {
                    Label("Access Key ID", systemImage: "key")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    TextField("AKIAIOSFODNN7EXAMPLE", text: $vm.accessKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                }
                .padding()

                Divider().padding(.leading)

                // Secret Key
                VStack(alignment: .leading, spacing: 6) {
                    Label("Secret Access Key", systemImage: "lock")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    HStack {
                        Group {
                            if showSecretKey {
                                TextField("wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
                                          text: $vm.secretKey)
                            } else {
                                SecureField("••••••••••••••••••••••••••••••••••••••••",
                                            text: $vm.secretKey)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))

                        Button {
                            showSecretKey.toggle()
                        } label: {
                            Image(systemName: showSecretKey ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private var testResultBanner: some View {
        if let result = vm.testResult {
            switch result {
            case .success:
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.statusRunning)
                    Text("Credentials verified — all regions will be scanned automatically.")
                        .font(.subheadline)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.statusRunning.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.statusRunning.opacity(0.3), lineWidth: 1)
                )
                .transition(.move(edge: .top).combined(with: .opacity))

            case .failure(let msg):
                ErrorBanner(message: msg) { vm.testResult = nil }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Test button
            Button {
                Task { await vm.testConnection() }
            } label: {
                HStack(spacing: 8) {
                    if vm.isTesting {
                        ProgressView().tint(.deepSkyBlue).scaleEffect(0.85)
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                    }
                    Text(vm.isTesting ? "Verifying…" : "Test Credentials")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.deepSkyBlue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.deepSkyBlue.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.deepSkyBlue.opacity(0.3), lineWidth: 1)
                )
            }
            .disabled(!vm.canConnect || vm.isTesting)

            // Connect button
            GradientButton(
                title:       "Connect",
                systemImage: "cloud.fill"
            ) {
                connectAction()
            }
            .disabled(!vm.canConnect)
        }
    }

    private var securityNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .foregroundColor(.cloudIndigo)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text("Your credentials are stored securely")
                    .font(.caption.weight(.semibold))
                Text("Credentials are saved in the iOS Keychain and are never transmitted to any server other than AWS endpoints.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.cloudIndigo.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Actions

    private func connectAction() {
        do {
            try appState.connect(
                accessKey: vm.accessKey.trimmingCharacters(in: .whitespaces),
                secretKey: vm.secretKey.trimmingCharacters(in: .whitespaces),
                region:    "us-east-1"
            )
        } catch {
            vm.testResult = .failure(error.localizedDescription)
        }
    }
}

// MARK: - Preview

#Preview {
    ConnectAWSView()
        .environment(AppState())
}
