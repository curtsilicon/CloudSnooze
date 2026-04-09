// EC2Service.swift
// Wraps Amazon EC2 API calls. Read-only discovery + start/stop/reboot.
// Creation APIs (RunInstances, etc.) are intentionally omitted.

import Foundation
import os

private nonisolated(unsafe) let log = Logger(subsystem: "ultara.cloud.CloudSnooze", category: "EC2")

@Observable
final class EC2Service {

    private let client = AWSClient.shared
    var instances: [EC2Instance] = []
    var isLoading  = false
    var lastError:  String?

    // MARK: - DescribeRegions

    /// Returns all enabled region names for this account.
    func describeRegions(credentials: AWSCredentials) async throws -> [String] {
        let host  = "ec2.\(credentials.region).amazonaws.com"
        // No filter — return all regions. Opt-in-only regions will fail DescribeInstances
        // gracefully in the task group, so no need to pre-filter here.
        let query = "Action=DescribeRegions&Version=2016-11-15"
        let req   = client.signedRequest(
            method:      "GET",
            service:     "ec2",
            region:      credentials.region,
            host:        host,
            path:        "/",
            query:       query,
            credentials: credentials
        )
        let data = try await client.execute(req)
        return try parseRegions(data: data)
    }

    // MARK: - DescribeInstances (single region)

    func describeInstances(credentials: AWSCredentials) async throws -> [EC2Instance] {
        let host = "ec2.\(credentials.region).amazonaws.com"
        let query = "Action=DescribeInstances&Version=2016-11-15"

        let req = client.signedRequest(
            method:      "GET",
            service:     "ec2",
            region:      credentials.region,
            host:        host,
            path:        "/",
            query:       query,
            credentials: credentials
        )
        let data = try await client.execute(req)
        return EC2Service.parseInstances(data: data, region: credentials.region)
    }

    // MARK: - DescribeInstances (all regions, parallel)

    /// All standard AWS regions. Used as fallback if DescribeRegions is not permitted.
    private static let knownRegions = [
        "us-east-1", "us-east-2", "us-west-1", "us-west-2",
        "ca-central-1", "ca-west-1",
        "eu-west-1", "eu-west-2", "eu-west-3",
        "eu-central-1", "eu-central-2",
        "eu-north-1", "eu-south-1", "eu-south-2",
        "ap-east-1", "ap-south-1", "ap-south-2",
        "ap-southeast-1", "ap-southeast-2", "ap-southeast-3", "ap-southeast-4",
        "ap-northeast-1", "ap-northeast-2", "ap-northeast-3",
        "sa-east-1",
        "me-south-1", "me-central-1",
        "af-south-1", "il-central-1"
    ]

    /// Queries every enabled region in parallel and merges results.
    func describeInstancesAllRegions(credentials: AWSCredentials) async throws -> [EC2Instance] {
        let regions: [String]
        do {
            regions = try await describeRegions(credentials: credentials)
            log.debug("DescribeRegions returned \(regions.count, privacy: .public) regions")
        } catch {
            log.info("DescribeRegions not permitted, falling back to known region list: \(error.localizedDescription, privacy: .public)")
            regions = Self.knownRegions
        }

        guard !regions.isEmpty else {
            log.debug("Region list is empty — falling back to home region only")
            return try await describeInstances(credentials: credentials)
        }

        let client = self.client
        return await withTaskGroup(of: [EC2Instance].self) { group in
            for region in regions {
                group.addTask {
                    let regionalCreds = AWSCredentials(
                        accessKeyId:     credentials.accessKeyId,
                        secretAccessKey: credentials.secretAccessKey,
                        region:          region
                    )
                    let host  = "ec2.\(region).amazonaws.com"
                    let query = "Action=DescribeInstances&Version=2016-11-15"
                    let req   = client.signedRequest(
                        method:      "GET",
                        service:     "ec2",
                        region:      region,
                        host:        host,
                        path:        "/",
                        query:       query,
                        credentials: regionalCreds
                    )
                    do {
                        let data      = try await client.execute(req)
                        let instances = await EC2Service.parseInstances(data: data, region: region)
                        if !instances.isEmpty {
                            log.debug("\(region, privacy: .public): found \(instances.count, privacy: .public) instance(s)")
                        }
                        return instances
                    } catch {
                        log.info("\(region, privacy: .public): fetch failed — \(error.localizedDescription, privacy: .public)")
                        return []
                    }
                }
            }

            var all: [EC2Instance] = []
            for await batch in group { all.append(contentsOf: batch) }
            log.debug("Total instances found across all regions: \(all.count, privacy: .public)")
            return all.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    // MARK: - StartInstances

    func startInstances(instanceIds: [String],
                        credentials: AWSCredentials) async throws {
        try await performInstanceAction(
            action:      "StartInstances",
            instanceIds: instanceIds,
            credentials: credentials
        )
    }

    // MARK: - StopInstances

    func stopInstances(instanceIds: [String],
                       credentials: AWSCredentials) async throws {
        try await performInstanceAction(
            action:      "StopInstances",
            instanceIds: instanceIds,
            credentials: credentials
        )
    }

    // MARK: - RebootInstances

    func rebootInstances(instanceIds: [String],
                         credentials: AWSCredentials) async throws {
        try await performInstanceAction(
            action:      "RebootInstances",
            instanceIds: instanceIds,
            credentials: credentials
        )
    }

    // MARK: - Refresh (updates @Observable state, all regions)

    func refresh(credentials: AWSCredentials) async {
        isLoading = true
        lastError = nil
        do {
            let fetched = try await describeInstancesAllRegions(credentials: credentials)
            instances = fetched
        } catch {
            lastError = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Private helpers

    private func performInstanceAction(action: String,
                                       instanceIds: [String],
                                       credentials: AWSCredentials) async throws {
        let host = "ec2.\(credentials.region).amazonaws.com"
        var queryParts = ["Action=\(action)", "Version=2016-11-15"]
        for (i, id) in instanceIds.enumerated() {
            queryParts.append("InstanceId.\(i + 1)=\(id)")
        }
        let query = queryParts.joined(separator: "&")
        let req = client.signedRequest(
            method:      "GET",
            service:     "ec2",
            region:      credentials.region,
            host:        host,
            path:        "/",
            query:       query,
            credentials: credentials
        )
        _ = try await client.execute(req)
    }

    // MARK: - XML Parsing

    @MainActor private static func parseInstances(data: Data, region: String) -> [EC2Instance] {
        let parser = EC2InstancesParser(region: region)
        return parser.parse(data: data)
    }

    private func parseRegions(data: Data) throws -> [String] {
        let parser = EC2RegionsParser()
        return parser.parse(data: data)
    }
}

// MARK: - EC2InstancesParser (SAX, namespace-aware)

/// SAX parser for EC2 DescribeInstances XML responses.
/// shouldProcessNamespaces = true means elementName == local name (no namespace prefix).
/// EC2 XML structure:
///   DescribeInstancesResponse
///     reservationSet
///       item (reservation)
///         instancesSet
///           item  <-- this is an instance item
///             instanceId, instanceType, ipAddress, ...
///             instanceState
///               name
///             tagSet
///               item
///                 key, value
@MainActor
private final class EC2InstancesParser: NSObject, XMLParserDelegate {

    private let region: String
    private var instances: [EC2Instance] = []

    // Element name stack and absolute depth counter
    private var stack: [String] = []
    private var depth = 0

    // Depth at which the current instance <item> was opened (nil when not inside one)
    private var instanceItemDepth: Int? = nil

    // Accumulated text for the current element
    private var currentText = ""

    // Flat key->value store for all scalar fields encountered in the instance item
    private var current: [String: String] = [:]

    // Tag parsing state
    private var inTagItem  = false
    private var tagKey:   String?
    private var tagValue: String?
    private var tags: [String: String] = [:]

    init(region: String) { self.region = region }

    func parse(data: Data) -> [EC2Instance] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        parser.parse()
        return instances
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        depth += 1
        stack.append(elementName)
        currentText = ""

        let parent = stack.count >= 2 ? stack[stack.count - 2] : ""

        // An instance item: direct child of instancesSet
        if elementName == "item", parent == "instancesSet" {
            instanceItemDepth = depth
            current = [:]
            tags    = [:]
            inTagItem = false
            return
        }

        // A tag item: direct child of tagSet, while we are inside an instance item
        if elementName == "item", parent == "tagSet", instanceItemDepth != nil {
            inTagItem = true
            tagKey   = nil
            tagValue = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        let text   = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = stack.count >= 2 ? stack[stack.count - 2] : ""

        if let iDepth = instanceItemDepth {

            if inTagItem {
                // Collect tag key/value
                if elementName == "key"   { tagKey   = text }
                if elementName == "value" { tagValue = text }

                // End of tag <item>
                if elementName == "item", parent == "tagSet" {
                    if let k = tagKey, let v = tagValue { tags[k] = v }
                    inTagItem = false
                }

            } else if !text.isEmpty {
                // Capture any scalar field at depth iDepth+1 or iDepth+2.
                // iDepth+1 are direct children (instanceId, instanceType, ipAddress, launchTime …)
                // iDepth+2 captures sub-element text like instanceState/name, placement/availabilityZone
                // We store by elementName; for iDepth+2 "name" conflicts only with instanceState/name
                // which is exactly what we want (state).
                if depth == iDepth + 1 || depth == iDepth + 2 {
                    current[elementName] = text
                }
            }

            // End of the instance <item> itself — flush
            if elementName == "item", depth == iDepth {
                flushInstance()
                instanceItemDepth = nil
            }
        }

        stack.removeLast()
        currentText = ""
        depth -= 1
    }

    private func flushInstance() {
        guard let instanceId = current["instanceId"], !instanceId.isEmpty else {
    
            return
        }
        // instanceState/name ends up stored as "name" (from the iDepth+2 capture)
        let stateRaw = current["name"] ?? "unknown"
        let state = EC2InstanceState(rawValue: stateRaw.replacingOccurrences(of: "-", with: "_")) ?? .unknown
        let nameTag = tags["Name"] ?? instanceId
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let launchTime = current["launchTime"].flatMap { iso.date(from: $0) }
        let instance = EC2Instance(
            id:           instanceId,
            arn:          "arn:aws:ec2:\(region):unknown:instance/\(instanceId)",
            name:         nameTag,
            instanceType: current["instanceType"] ?? "unknown",
            state:        state,
            region:       region,
            publicIp:     current["ipAddress"].flatMap     { $0.isEmpty ? nil : $0 },
            privateIp:    current["privateIpAddress"].flatMap { $0.isEmpty ? nil : $0 },
            launchTime:   launchTime,
            tags:         tags
        )

        instances.append(instance)
    }
}

// MARK: - EC2RegionsParser (SAX, namespace-aware)

/// SAX parser for EC2 DescribeRegions XML responses.
private final class EC2RegionsParser: NSObject, XMLParserDelegate {

    private var regions:     [String] = []
    private var stack:       [String] = []
    private var currentText: String   = ""

    func parse(data: Data) -> [String] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = true
        parser.parse()
        let result = regions.filter { !$0.isEmpty }.sorted()
        log.debug("parseRegions found \(result.count, privacy: .public) regions")
        return result
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        stack.append(elementName)
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        let text   = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = stack.count >= 2 ? stack[stack.count - 2] : ""

        if elementName == "regionName", parent == "item", !text.isEmpty {
            regions.append(text)
        }

        stack.removeLast()
        currentText = ""
    }
}
