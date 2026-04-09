// CostService.swift
// Wraps AWS Cost Explorer APIs.
// Note: Cost Explorer endpoint is always us-east-1.

import Foundation

final class CostService {

    private let client = AWSClient.shared
    // Cost Explorer has a fixed global endpoint
    private let ceHost   = "ce.us-east-1.amazonaws.com"
    private let ceRegion = "us-east-1"

    // MARK: - GetCostAndUsage (current month)

    struct MonthlyCost {
        let start:       String
        let end:         String
        let amount:      Double
        let unit:        String
        let serviceCosts: [ServiceCost]
    }

    struct ServiceCost: Identifiable {
        let id = UUID()
        let serviceName: String
        let amount:      Double
        let unit:        String
    }

    func getCurrentMonthCost(credentials: AWSCredentials) async throws -> MonthlyCost {
        let (start, end) = currentMonthDateRange()
        let body = """
        {
          "TimePeriod": {"Start": "\(start)", "End": "\(end)"},
          "Granularity": "MONTHLY",
          "GroupBy": [{"Type": "DIMENSION", "Key": "SERVICE"}],
          "Metrics": ["UnblendedCost"]
        }
        """
        let bodyData = Data(body.utf8)
        var req = client.signedRequest(
            method:  "POST",
            service: "ce",
            region:  ceRegion,
            host:    ceHost,
            path:    "/",
            body:    bodyData,
            extraHeaders: [
                "Content-Type": "application/x-amz-json-1.1",
                "X-Amz-Target": "AWSInsightsIndexService.GetCostAndUsage"
            ],
            credentials: credentials
        )
        let data = try await client.execute(req)
        return try parseMonthlyCost(data: data, start: start, end: end)
    }

    // MARK: - GetCostForecast

    struct CostForecast {
        let amount: Double
        let unit:   String
        let period: String
    }

    func getMonthForecast(credentials: AWSCredentials) async throws -> CostForecast {
        let today    = Date()
        let calendar = Calendar.current
        guard let lastDay = calendar.date(
            byAdding: .month, value: 1,
            to: calendar.startOfDay(
                for: calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
            )
        ).map({ calendar.date(byAdding: .day, value: -1, to: $0)! }) else {
            throw AWSError.parseError("Could not compute month end date")
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let startStr = fmt.string(from: today)
        let endStr   = fmt.string(from: lastDay)

        let body = """
        {
          "TimePeriod": {"Start": "\(startStr)", "End": "\(endStr)"},
          "Granularity": "MONTHLY",
          "Metric": "UNBLENDED_COST"
        }
        """
        let bodyData = Data(body.utf8)
        let req = client.signedRequest(
            method:  "POST",
            service: "ce",
            region:  ceRegion,
            host:    ceHost,
            path:    "/",
            body:    bodyData,
            extraHeaders: [
                "Content-Type": "application/x-amz-json-1.1",
                "X-Amz-Target": "AWSInsightsIndexService.GetCostForecast"
            ],
            credentials: credentials
        )
        let data = try await client.execute(req)
        return try parseForecast(data: data)
    }

    // MARK: - Parsing helpers

    private func parseMonthlyCost(data: Data,
                                  start: String,
                                  end: String) throws -> MonthlyCost {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["ResultsByTime"] as? [[String: Any]],
              let first = results.first
        else { throw AWSError.parseError("Could not read ResultsByTime") }

        var total  = 0.0
        var unit   = "USD"
        var services: [ServiceCost] = []

        if let groups = first["Groups"] as? [[String: Any]] {
            for group in groups {
                guard
                    let keys    = group["Keys"] as? [String],
                    let metrics = group["Metrics"] as? [String: Any],
                    let cost    = metrics["UnblendedCost"] as? [String: Any],
                    let amt     = (cost["Amount"] as? String).flatMap(Double.init),
                    let u       = cost["Unit"] as? String
                else { continue }
                let name = keys.first ?? "Other"
                services.append(ServiceCost(serviceName: name, amount: amt, unit: u))
                total += amt
                unit   = u
            }
        }

        services.sort { $0.amount > $1.amount }

        return MonthlyCost(start: start, end: end,
                           amount: total, unit: unit,
                           serviceCosts: services)
    }

    private func parseForecast(data: Data) throws -> CostForecast {
        guard
            let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let total = json["Total"] as? [String: Any],
            let amt   = (total["Amount"] as? String).flatMap(Double.init),
            let unit  = total["Unit"] as? String
        else { throw AWSError.parseError("Could not parse cost forecast") }
        return CostForecast(amount: amt, unit: unit, period: "Month")
    }

    private func currentMonthDateRange() -> (start: String, end: String) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar.current
        let now = Date()
        let comps = calendar.dateComponents([.year, .month], from: now)
        let startOfMonth = calendar.date(from: comps)!
        // end must be today (exclusive upper bound for Cost Explorer)
        return (fmt.string(from: startOfMonth), fmt.string(from: now))
    }
}
