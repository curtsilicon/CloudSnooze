// CloudWatchService.swift
// Wraps Amazon CloudWatch metric APIs.

import Foundation

final class CloudWatchService {

    private let client = AWSClient.shared

    // MARK: - GetMetricStatistics

    /// Retrieves CPU utilisation (or any standard metric) for the past N hours.
    func getCPUUtilization(instanceId: String,
                           hours: Int = 3,
                           credentials: AWSCredentials) async throws -> [MetricDatapoint] {
        return try await getMetricStatistics(
            namespace:  "AWS/EC2",
            metricName: "CPUUtilization",
            dimensions: [("InstanceId", instanceId)],
            statistics: ["Average"],
            period:     300,   // 5-minute granularity (144 points over 12 hours)
            hours:      hours,
            credentials: credentials
        )
    }

    func getMetricStatistics(namespace: String,
                             metricName: String,
                             dimensions: [(name: String, value: String)],
                             statistics: [String],
                             period: Int,
                             hours: Int,
                             credentials: AWSCredentials) async throws -> [MetricDatapoint] {
        let host = "monitoring.\(credentials.region).amazonaws.com"
        let endTime   = Date()
        let startTime = endTime.addingTimeInterval(TimeInterval(-hours * 3600))

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var params: [String] = [
            "Action=GetMetricStatistics",
            "Version=2010-08-01",
            "Namespace=\(namespace)",
            "MetricName=\(metricName)",
            "Period=\(period)",
            "StartTime=\(iso.string(from: startTime))",
            "EndTime=\(iso.string(from: endTime))"
        ]

        for (i, stat) in statistics.enumerated() {
            params.append("Statistics.member.\(i + 1)=\(stat)")
        }
        for (i, dim) in dimensions.enumerated() {
            params.append("Dimensions.member.\(i + 1).Name=\(dim.name)")
            params.append("Dimensions.member.\(i + 1).Value=\(dim.value)")
        }

        let query = params.joined(separator: "&")
        let req   = client.signedRequest(
            method:      "GET",
            service:     "monitoring",
            region:      credentials.region,
            host:        host,
            path:        "/",
            query:       query,
            credentials: credentials
        )
        let data = try await client.execute(req)
        return try parseMetricStatistics(data: data)
    }

    // MARK: - XML parsing

    private func parseMetricStatistics(data: Data) throws -> [MetricDatapoint] {
        let parser = CloudWatchXMLParser(data: data)
        return try parser.parse()
    }
}

// MARK: - CloudWatch XML Parser

/// SAX parser for CloudWatch GetMetricStatistics XML.
/// CloudWatch XML structure (with shouldProcessNamespaces = true, elementName = local name):
///   GetMetricStatisticsResponse
///     GetMetricStatisticsResult
///       Datapoints
///         member          <-- one per datapoint
///           Timestamp
///           Average (or Sum / Maximum)
///           Unit
private final class CloudWatchXMLParser: NSObject, XMLParserDelegate {

    private let data: Data
    private var datapoints:  [MetricDatapoint] = []
    private var stack:       [String] = []
    private var depth        = 0
    private var memberDepth: Int? = nil
    private var current:     [String: String] = [:]
    private var currentText  = ""
    private var parseError:  Error?

    init(data: Data) { self.data = data }

    func parse() throws -> [MetricDatapoint] {
        let p = XMLParser(data: data)
        p.delegate = self
        p.shouldProcessNamespaces = true
        p.parse()
        if let e = parseError { throw e }

        return datapoints.sorted { $0.timestamp < $1.timestamp }
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName: String?,
                attributes: [String: String] = [:]) {
        depth += 1
        stack.append(elementName)
        currentText = ""

        let parent = stack.count >= 2 ? stack[stack.count - 2] : ""
        // A datapoint member: <member> whose parent is <Datapoints>
        if elementName == "member", parent == "Datapoints" {
            memberDepth = depth
            current = [:]
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if let mDepth = memberDepth {
            // Capture direct scalar children of the member element
            if depth == mDepth + 1, !text.isEmpty {
                current[elementName] = text
            }

            // End of member — flush datapoint
            if elementName == "member", depth == mDepth {
                flushDatapoint()
                memberDepth = nil
            }
        }

        stack.removeLast()
        currentText = ""
        depth -= 1
    }

    private func flushDatapoint() {
        guard
            let tsStr  = current["Timestamp"],
            let ts     = parseTimestamp(tsStr),
            let valStr = current["Average"] ?? current["Sum"] ?? current["Maximum"] ?? current["SampleCount"],
            let value  = Double(valStr)
        else {
                return
        }
        let unit = current["Unit"] ?? "None"
        datapoints.append(MetricDatapoint(timestamp: ts, value: value, unit: unit))
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }

    /// Parses ISO8601 timestamps with or without fractional seconds.
    private func parseTimestamp(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: string) { return d }

        let withoutFraction = ISO8601DateFormatter()
        withoutFraction.formatOptions = [.withInternetDateTime]
        return withoutFraction.date(from: string)
    }
}
