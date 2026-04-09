// CloudResource.swift
// Represents any observable cloud resource. Resources are identified by ARN.

import Foundation

// MARK: - CloudResource

struct CloudResource: Identifiable, Codable, Hashable {
    let id: UUID
    var arn:         String
    var service:     CloudService
    var region:      String
    var resourceId:  String
    var displayName: String
    var addedAt:     Date

    init(id: UUID = .init(),
         arn: String,
         service: CloudService,
         region: String,
         resourceId: String,
         displayName: String,
         addedAt: Date = .now) {
        self.id          = id
        self.arn         = arn
        self.service     = service
        self.region      = region
        self.resourceId  = resourceId
        self.displayName = displayName
        self.addedAt     = addedAt
    }
}

// MARK: - CloudService

enum CloudService: String, Codable, CaseIterable {
    case ec2  = "ec2"
    case s3   = "s3"
    case cloudwatch = "cloudwatch"
    case costExplorer = "ce"
    case unknown = "unknown"

    var displayName: String {
        switch self {
        case .ec2:          return "EC2"
        case .s3:           return "S3"
        case .cloudwatch:   return "CloudWatch"
        case .costExplorer: return "Cost Explorer"
        case .unknown:      return "Unknown"
        }
    }

    var systemImage: String {
        switch self {
        case .ec2:          return "server.rack"
        case .s3:           return "externaldrive.connected.to.line.below"
        case .cloudwatch:   return "chart.line.uptrend.xyaxis"
        case .costExplorer: return "dollarsign.circle"
        case .unknown:      return "questionmark.circle"
        }
    }
}

// MARK: - ARN Parser

struct ARNParser {

    /// Parses a standard AWS ARN into a `CloudResource`.
    /// Format: arn:partition:service:region:account-id:resource
    static func parse(_ arn: String, displayName: String? = nil) -> CloudResource? {
        let parts = arn.split(separator: ":", maxSplits: 5, omittingEmptySubsequences: false)
            .map(String.init)

        guard parts.count >= 6,
              parts[0] == "arn"
        else { return nil }

        let serviceStr  = parts[2]
        let region      = parts[3]
        let resourceStr = parts[5]  // e.g. "instance/i-123456"  or  "my-bucket"

        let service = CloudService(rawValue: serviceStr) ?? .unknown
        let resourceId = extractResourceId(from: resourceStr, service: service)
        let name = displayName ?? resourceId

        return CloudResource(
            arn:         arn,
            service:     service,
            region:      region,
            resourceId:  resourceId,
            displayName: name
        )
    }

    /// Validates the basic structural shape of an ARN string.
    static func isValid(_ arn: String) -> Bool {
        let parts = arn.split(separator: ":",
                              maxSplits: 5,
                              omittingEmptySubsequences: false)
        guard parts.count >= 6, parts[0] == "arn" else { return false }
        let serviceStr = String(parts[2])
        return !serviceStr.isEmpty
    }

    // MARK: Private helpers

    private static func extractResourceId(from resource: String,
                                          service: CloudService) -> String {
        // resource may be "type/id" – e.g. "instance/i-0abc123"
        if let slashIdx = resource.lastIndex(of: "/") {
            return String(resource[resource.index(after: slashIdx)...])
        }
        return resource
    }
}

// MARK: - EC2 Instance

struct EC2Instance: Identifiable, Codable, Equatable {
    let id:           String   // instance-id
    let arn:          String
    var name:         String
    var instanceType: String
    var state:        EC2InstanceState
    var region:       String
    var publicIp:     String?
    var privateIp:    String?
    var launchTime:   Date?
    var tags:         [String: String]

    init(id: String,
         arn: String,
         name: String,
         instanceType: String,
         state: EC2InstanceState,
         region: String,
         publicIp: String? = nil,
         privateIp: String? = nil,
         launchTime: Date? = nil,
         tags: [String: String] = [:]) {
        self.id           = id
        self.arn          = arn
        self.name         = name
        self.instanceType = instanceType
        self.state        = state
        self.region       = region
        self.publicIp     = publicIp
        self.privateIp    = privateIp
        self.launchTime   = launchTime
        self.tags         = tags
    }
}

enum EC2InstanceState: String, Codable {
    case pending, running, stopping, stopped, terminated, shutting_down, unknown

    var displayName: String {
        switch self {
        case .shutting_down: return "shutting-down"
        default: return rawValue
        }
    }

    var isRunning: Bool  { self == .running }
    var isStopped: Bool  { self == .stopped }
    var isTransient: Bool { self == .pending || self == .stopping || self == .shutting_down }
}

// MARK: - S3 Bucket

struct S3Bucket: Identifiable, Codable {
    let id:           String   // bucket name
    var name:         String
    var region:       String
    var creationDate: Date?
}

// MARK: - CloudWatch Datapoint

struct MetricDatapoint: Codable, Identifiable {
    let id:        UUID
    let timestamp: Date
    let value:     Double
    let unit:      String

    init(id: UUID = .init(), timestamp: Date, value: Double, unit: String) {
        self.id        = id
        self.timestamp = timestamp
        self.value     = value
        self.unit      = unit
    }
}
