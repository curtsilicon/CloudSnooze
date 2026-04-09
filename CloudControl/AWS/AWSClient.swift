// AWSClient.swift
// Central AWS HTTP client with Signature Version 4 request signing.
// All communication goes directly to AWS endpoints from the device.

import Foundation
import CryptoKit

// MARK: - AWSClient

final class AWSClient {

    static let shared = AWSClient()
    private init() {}

    // MARK: - Signed request builder

    /// Build and sign an AWS API request.
    func signedRequest(method: String,
                       service: String,
                       region: String,
                       host: String,
                       path: String = "/",
                       query: String = "",
                       body: Data = Data(),
                       extraHeaders: [String: String] = [:],
                       credentials: AWSCredentials) -> URLRequest {
        let now = Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withTime,
                                        .withDashSeparatorInDate,
                                        .withColonSeparatorInTime]
        let amzDate  = amzDateString(from: now)
        let dateStamp = dateStampString(from: now)

        var urlComponents = URLComponents()
        urlComponents.scheme = "https"
        urlComponents.host   = host
        urlComponents.path   = path
        if !query.isEmpty { urlComponents.percentEncodedQuery = query }
        let url = urlComponents.url!

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody   = body.isEmpty ? nil : body

        // Required headers
        request.setValue(host,    forHTTPHeaderField: "host")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        if !body.isEmpty {
            request.setValue(sha256Hex(body), forHTTPHeaderField: "x-amz-content-sha256")
        } else {
            request.setValue(sha256Hex(Data()), forHTTPHeaderField: "x-amz-content-sha256")
        }
        for (k, v) in extraHeaders { request.setValue(v, forHTTPHeaderField: k) }

        // Canonical request
        let bodyHash = sha256Hex(body.isEmpty ? Data() : body)
        let sortedHeaders = request.allHTTPHeaderFields?
            .sorted { $0.key.lowercased() < $1.key.lowercased() } ?? []
        let canonicalHeaders = sortedHeaders
            .map { "\($0.key.lowercased()):\($0.value.trimmingCharacters(in: .whitespaces))\n" }
            .joined()
        let signedHeaders = sortedHeaders
            .map { $0.key.lowercased() }.joined(separator: ";")

        let canonicalRequest = [
            method,
            path.isEmpty ? "/" : path,
            query,
            canonicalHeaders,
            signedHeaders,
            bodyHash
        ].joined(separator: "\n")

        // String to sign
        let credScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let strToSign = "AWS4-HMAC-SHA256\n\(amzDate)\n\(credScope)\n\(sha256Hex(Data(canonicalRequest.utf8)))"

        // Signing key  (HMAC-SHA256 chain)
        let signingKey = derivedSigningKey(secret: credentials.secretAccessKey,
                                           dateStamp: dateStamp,
                                           region: region,
                                           service: service)
        let signature = hmacHex(key: signingKey, data: Data(strToSign.utf8))

        // Authorization header
        let auth = "AWS4-HMAC-SHA256 Credential=\(credentials.accessKeyId)/\(credScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        request.setValue(auth, forHTTPHeaderField: "Authorization")

        return request
    }

    // MARK: - Execute request

    func execute(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
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

    private func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func hmac(key: Data, data: Data) -> Data {
        let sym = SymmetricKey(data: key)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: sym)
        return Data(mac)
    }

    private func hmacHex(key: Data, data: Data) -> String {
        hmac(key: key, data: data)
            .compactMap { String(format: "%02x", $0) }.joined()
    }

    private func derivedSigningKey(secret: String,
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

    private func amzDateString(from date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        fmt.timeZone   = TimeZone(identifier: "UTC")
        return fmt.string(from: date)
    }

    private func dateStampString(from date: Date) -> String {
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
            // Extract <Message> from AWS XML error if present
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
