// AWSClient.swift
// Central AWS HTTP client with Signature Version 4 request signing.
// All communication goes directly to AWS endpoints from the device.

import Foundation
import CryptoKit

// MARK: - AWSClient

final class AWSClient: @unchecked Sendable {

    static let shared = AWSClient()
    private init() {}

    // MARK: - Signed request builder

    /// Build and sign an AWS API request using Signature Version 4.
    nonisolated func signedRequest(method: String,
                       service: String,
                       region: String,
                       host: String,
                       path: String = "/",
                       query: String = "",
                       body: Data = Data(),
                       extraHeaders: [String: String] = [:],
                       credentials: AWSCredentials) -> URLRequest {
        let now       = Date()
        let amzDate   = amzDateString(from: now)
        let dateStamp = dateStampString(from: now)
        let bodyHash  = sha256Hex(body)

        // Build the explicit header map we will sign.
        // Do NOT read back from URLRequest — it injects extra headers we don't control.
        var headersToSign: [String: String] = [
            "host":                  host,
            "x-amz-date":            amzDate,
            "x-amz-content-sha256":  bodyHash
        ]
        for (k, v) in extraHeaders {
            headersToSign[k.lowercased()] = v
        }

        // Canonical headers: sorted by lowercase key
        let sortedKeys     = headersToSign.keys.sorted()
        let canonicalHeaders = sortedKeys
            .map { "\($0):\(headersToSign[$0]!.trimmingCharacters(in: .whitespaces))\n" }
            .joined()
        let signedHeaders = sortedKeys.joined(separator: ";")

        // Canonical query string: sort params alphabetically, re-encode per SigV4 rules
        let canonicalQuery = canonicalQueryString(from: query)

        // Canonical request
        let canonicalPath    = path.isEmpty ? "/" : path
        let canonicalRequest = [
            method,
            canonicalPath,
            canonicalQuery,
            canonicalHeaders,
            signedHeaders,
            bodyHash
        ].joined(separator: "\n")

        // String to sign
        let credScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let strToSign = "AWS4-HMAC-SHA256\n\(amzDate)\n\(credScope)\n\(sha256Hex(Data(canonicalRequest.utf8)))"

        // Signing key (HMAC-SHA256 chain)
        let signingKey = derivedSigningKey(secret: credentials.secretAccessKey,
                                           dateStamp: dateStamp,
                                           region: region,
                                           service: service)
        let signature = hmacHex(key: signingKey, data: Data(strToSign.utf8))

        // Build URLRequest — set only our controlled headers, no auto-injected ones
        var urlComponents = URLComponents()
        urlComponents.scheme              = "https"
        urlComponents.host                = host
        urlComponents.path                = canonicalPath
        urlComponents.percentEncodedQuery = canonicalQuery.isEmpty ? nil : canonicalQuery
        let url = urlComponents.url!

        var request        = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody   = body.isEmpty ? nil : body

        for key in sortedKeys {
            request.setValue(headersToSign[key], forHTTPHeaderField: key)
        }
        let auth = "AWS4-HMAC-SHA256 Credential=\(credentials.accessKeyId)/\(credScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        request.setValue(auth, forHTTPHeaderField: "Authorization")

        return request
    }

    /// Parses a raw query string and returns a SigV4-canonical version:
    /// keys and values URI-encoded, pairs sorted by key then value.
    private nonisolated func canonicalQueryString(from raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        let pairs = raw.split(separator: "&", omittingEmptySubsequences: true)
        let encoded: [(String, String)] = pairs.map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1)
            let key   = sigV4Encode(String(parts[0]))
            let value = parts.count > 1 ? sigV4Encode(String(parts[1])) : ""
            return (key, value)
        }
        return encoded
            .sorted { $0.0 < $1.0 || ($0.0 == $1.0 && $0.1 < $1.1) }
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "&")
    }

    /// SigV4 URI encoding: unreserved chars only, space → %20 (not +).
    private nonisolated func sigV4Encode(_ string: String) -> String {
        // First decode any existing percent-encoding so we don't double-encode
        let decoded = string.removingPercentEncoding ?? string
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return decoded.addingPercentEncoding(withAllowedCharacters: allowed) ?? decoded
    }

    // MARK: - Dedicated session (explicit TLS floor, no shared cookie/credential storage)

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        config.tlsMaximumSupportedProtocolVersion = .TLSv13
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    // MARK: - Execute request

    nonisolated func execute(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await AWSClient.shared.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AWSError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            throw AWSError.httpError(statusCode: http.statusCode, body: body)
        }
        return data
    }

    // MARK: - Crypto helpers

    private nonisolated func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private nonisolated func hmac(key: Data, data: Data) -> Data {
        let sym = SymmetricKey(data: key)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: sym)
        return Data(mac)
    }

    private nonisolated func hmacHex(key: Data, data: Data) -> String {
        hmac(key: key, data: data)
            .compactMap { String(format: "%02x", $0) }.joined()
    }

    private nonisolated func derivedSigningKey(secret: String,
                                   dateStamp: String,
                                   region: String,
                                   service: String) -> Data {
        let kSecret  = Data(("AWS4" + secret).utf8)
        let kDate    = hmac(key: kSecret,  data: Data(dateStamp.utf8))
        let kRegion  = hmac(key: kDate,    data: Data(region.utf8))
        let kService = hmac(key: kRegion,  data: Data(service.utf8))
        let kSigning = hmac(key: kService, data: Data("aws4_request".utf8))
        return kSigning
    }

    private nonisolated func amzDateString(from date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        fmt.timeZone   = TimeZone(identifier: "UTC")
        return fmt.string(from: date)
    }

    private nonisolated func dateStampString(from date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd"
        fmt.timeZone   = TimeZone(identifier: "UTC")
        return fmt.string(from: date)
    }
}

// MARK: - AWSError

enum AWSError: LocalizedError {
    case noCredentials
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case parseError(String)
    case notImplemented

    var errorDescription: String? {
        switch self {
        case .noCredentials:
            return "No AWS credentials configured. Please connect your account in Settings."
        case .invalidResponse:
            return "Received an invalid response from the cloud API."
        case .httpError(let code, let body):
            // Try JSON error body first (e.g. Cost Explorer)
            if let data = body.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = json["message"] as? String ?? json["Message"] as? String {
                return "Cloud API error (\(code)): \(msg)"
            }
            // Fall back to XML <Message> tag (e.g. EC2, S3)
            if let range = body.range(of: "<Message>"),
               let endRange = body.range(of: "</Message>") {
                let msg = String(body[range.upperBound..<endRange.lowerBound])
                return "Cloud API error (\(code)): \(msg)"
            }
            return "Cloud API error (HTTP \(code))."
        case .parseError(let msg):
            return "Failed to parse API response: \(msg)"
        case .notImplemented:
            return "This operation is not supported."
        }
    }
}
