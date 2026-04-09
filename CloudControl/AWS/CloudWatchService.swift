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
            period:     300,   // 5-minute granularity
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
            "Namespace=\(namespace.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? namespace)",
            "MetricName=\(metricName)",
            "Period=\(period)",
            "StartTime=\(iso.string(from: startTime).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")",
            "EndTime=\(iso.string(from: endTime).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
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

private final class CloudWatchXMLParser: NSObject, XMLParserDelegate {

    private let data: Data
    private var datapoints: [MetricDatapoint] = []
    private var current: [String: String] = [:]
    private var insideMember = false
    private var currentElement = ""
    private var parseError: Error?

    init(data: Data) { self.data = data }

    func parse() throws -> [MetricDatapoint] {
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
        if let e = parseError { throw e }
        return datapoints.sorted { $0.timestamp < $1.timestamp }
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "member" {
            insideMember = true
            current = [:]
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, insideMember else { return }
        current[currentElement] = (current[currentElement] ?? "") + s
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName: String?) {
        guard elementName == "member", insideMember else { return }
        insideMember = false

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard
            let tsStr = current["Timestamp"],
            let ts    = iso.date(from: tsStr),
            let valStr = current["Average"] ?? current["Sum"] ?? current["Maximum"],
            let value  = Double(valStr)
        else { return }

        let unit = current["Unit"] ?? "None"
        datapoints.append(MetricDatapoint(timestamp: ts, value: value, unit: unit))
    }
}
