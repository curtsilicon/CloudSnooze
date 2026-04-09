// AppState.swift
// Central observable app state injected as an Environment value.

import Foundation

@Observable
final class AppState {

    // MARK: - Auth state
    var isConnected: Bool = false
    var credentials: AWSCredentials? = nil

    // MARK: - Discovery cache
    var discoveredInstances: [EC2Instance] = []
    var discoveredBuckets:   [S3Bucket]    = []

    // MARK: - Dashboard store
    var dashboardStore = DashboardStore()

    // MARK: - Init

    init() {
        if let creds = KeychainManager.shared.loadCredentials() {
            credentials  = creds
            isConnected  = true
        }
    }

    // MARK: - Connect

    func connect(accessKey: String, secretKey: String, region: String) throws {
        try KeychainManager.shared.saveCredentials(
            accessKey: accessKey,
            secretKey: secretKey,
            region:    region
        )
        credentials = AWSCredentials(
            accessKeyId:     accessKey,
            secretAccessKey: secretKey,
            region:          region
        )
        isConnected = true
    }

    // MARK: - Disconnect

    func disconnect() {
        try? KeychainManager.shared.deleteCredentials()
        credentials          = nil
        isConnected          = false
        discoveredInstances  = []
        discoveredBuckets    = []
    }

    // MARK: - Discovery refresh

    func runDiscoveryRefresh() async {
        guard let creds = credentials else { return }
        let ec2 = EC2Service()
        let s3  = S3Service()
        async let instances = ec2.describeInstances(credentials: creds)
        async let buckets   = s3.listBuckets(credentials: creds)
        if let i = try? await instances { discoveredInstances = i }
        if let b = try? await buckets   { discoveredBuckets   = b }
    }
}

// MARK: - Preview helper

extension AppState {
    /// A synthetic state with mock credentials for Xcode previews.
    static var preview: AppState {
        let s = AppState()
        // Previews don't call real AWS – credentials are fake stubs
        s.credentials = AWSCredentials(
            accessKeyId:     "PREVIEW",
            secretAccessKey: "PREVIEW",
            region:          "us-east-1"
        )
        s.isConnected = true
        return s
    }
}
