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
    /// Increments on every completed refresh — use as task(id:) to force widget reloads
    var refreshToken: Int = 0

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

    // MARK: - Discovery refresh (all regions)

    func runDiscoveryRefresh() async {
        guard let creds = credentials else {
            print("[AppState] runDiscoveryRefresh: no credentials, aborting")
            return
        }
        print("[AppState] runDiscoveryRefresh: starting, home region = \(creds.region)")
        let ec2 = EC2Service()
        let s3  = S3Service()

        async let instanceTask = Task.detached(priority: .userInitiated) {
            try await ec2.describeInstancesAllRegions(credentials: creds)
        }.value
        async let bucketTask = Task.detached(priority: .userInitiated) {
            try await s3.listBuckets(credentials: creds)
        }.value

        let instances = try? await instanceTask
        let buckets   = try? await bucketTask

        print("[AppState] runDiscoveryRefresh: done — \(instances?.count ?? 0) instances, \(buckets?.count ?? 0) buckets")

        await MainActor.run {
            if let i = instances { discoveredInstances = i }
            if let b = buckets   { discoveredBuckets   = b }
            refreshToken += 1
        }
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
