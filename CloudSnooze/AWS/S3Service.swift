// S3Service.swift
// Wraps Amazon S3 list and object APIs.
// Write operations (PutObject) included; creation APIs (CreateBucket) are omitted.

import Foundation

final class S3Service {

    private let client = AWSClient.shared

    // MARK: - ListBuckets

    func listBuckets(credentials: AWSCredentials) async throws -> [S3Bucket] {
        // S3 ListBuckets is a global call (us-east-1 endpoint)
        let host   = "s3.amazonaws.com"
        let region = "us-east-1"
        let req = client.signedRequest(
            method:      "GET",
            service:     "s3",
            region:      region,
            host:        host,
            path:        "/",
            credentials: credentials
        )
        let data = try await client.execute(req)
        return try parseListBuckets(data: data)
    }

    // MARK: - ListObjects (ListBucket)

    struct S3Object: Identifiable {
        let id  = UUID()
        let key:          String
        let size:         Int64
        let lastModified: Date?
        let etag:         String
    }

    func listObjects(bucket: String,
                     prefix: String = "",
                     credentials: AWSCredentials) async throws -> [S3Object] {
        let host  = "\(bucket).s3.\(credentials.region).amazonaws.com"
        var query = "list-type=2"
        if !prefix.isEmpty {
            query += "&prefix=\(prefix.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? prefix)"
        }
        let req = client.signedRequest(
            method:      "GET",
            service:     "s3",
            region:      credentials.region,
            host:        host,
            path:        "/",
            query:       query,
            credentials: credentials
        )
        let data = try await client.execute(req)
        return try parseListObjects(data: data)
    }

    // MARK: - GetObject

    func getObject(bucket: String,
                   key: String,
                   credentials: AWSCredentials) async throws -> Data {
        let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        let host = "\(bucket).s3.\(credentials.region).amazonaws.com"
        let req  = client.signedRequest(
            method:      "GET",
            service:     "s3",
            region:      credentials.region,
            host:        host,
            path:        "/\(encodedKey)",
            credentials: credentials
        )
        return try await client.execute(req)
    }

    // MARK: - PutObject

    func putObject(bucket: String,
                   key: String,
                   body: Data,
                   contentType: String = "application/octet-stream",
                   credentials: AWSCredentials) async throws {
        let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        let host = "\(bucket).s3.\(credentials.region).amazonaws.com"
        let req  = client.signedRequest(
            method:      "PUT",
            service:     "s3",
            region:      credentials.region,
            host:        host,
            path:        "/\(encodedKey)",
            body:        body,
            extraHeaders: ["Content-Type": contentType],
            credentials: credentials
        )
        _ = try await client.execute(req)
    }

    // MARK: - XML Parsing

    private func parseListBuckets(data: Data) throws -> [S3Bucket] {
        let parser = S3BucketXMLParser(data: data)
        return try parser.parse()
    }

    private func parseListObjects(data: Data) throws -> [S3Object] {
        let parser = S3ObjectXMLParser(data: data)
        return try parser.parse()
    }
}

// MARK: - S3 Bucket XML Parser

private final class S3BucketXMLParser: NSObject, XMLParserDelegate {

    private let data: Data
    private var buckets: [S3Bucket] = []
    private var current: [String: String] = [:]
    private var insideBucket = false
    private var currentElement = ""
    private var parseError: Error?

    init(data: Data) { self.data = data }

    func parse() throws -> [S3Bucket] {
        let p = XMLParser(data: data)
        p.delegate = self
        p.shouldResolveExternalEntities = false
        p.parse()
        if let e = parseError { throw e }
        return buckets
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "Bucket" { insideBucket = true; current = [:] }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, insideBucket else { return }
        current[currentElement] = (current[currentElement] ?? "") + s
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName: String?) {
        guard elementName == "Bucket", insideBucket else { return }
        insideBucket = false
        guard let name = current["Name"] else { return }
        let fmt = ISO8601DateFormatter()
        let created = current["CreationDate"].flatMap { fmt.date(from: $0) }
        buckets.append(S3Bucket(id: name, name: name, region: "unknown", creationDate: created))
    }
}

// MARK: - S3 Object XML Parser

private final class S3ObjectXMLParser: NSObject, XMLParserDelegate {

    private let data: Data
    private var objects: [S3Service.S3Object] = []
    private var current: [String: String] = [:]
    private var insideContents = false
    private var currentElement = ""
    private var parseError: Error?

    init(data: Data) { self.data = data }

    func parse() throws -> [S3Service.S3Object] {
        let p = XMLParser(data: data)
        p.delegate = self
        p.shouldResolveExternalEntities = false
        p.parse()
        if let e = parseError { throw e }
        return objects
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "Contents" { insideContents = true; current = [:] }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, insideContents else { return }
        current[currentElement] = (current[currentElement] ?? "") + s
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName: String?) {
        guard elementName == "Contents", insideContents else { return }
        insideContents = false
        guard let key = current["Key"] else { return }
        let fmt  = ISO8601DateFormatter()
        let date = current["LastModified"].flatMap { fmt.date(from: $0) }
        let size = Int64(current["Size"] ?? "0") ?? 0
        let etag = (current["ETag"] ?? "").replacingOccurrences(of: "\"", with: "")
        objects.append(S3Service.S3Object(key: key, size: size, lastModified: date, etag: etag))
    }
}
