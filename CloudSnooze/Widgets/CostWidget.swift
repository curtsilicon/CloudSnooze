// CostWidget.swift
// Displays current month cloud spend and a per-service breakdown.

import SwiftUI
import Charts

// MARK: - ViewModel

@Observable
final class CostViewModel {

    var monthlyCost:  CostService.MonthlyCost?
    var forecast:     CostService.CostForecast?
    var isLoading     = false
    var lastError:    String?
    var lastRefresh:  Date?

    private let ce = CostService()

    @MainActor
    func refresh(credentials: AWSCredentials) async {
        isLoading = true
        lastError = nil
        do {
            monthlyCost = try await ce.getCurrentMonthCost(credentials: credentials)
            lastRefresh = .now
        } catch {
            lastError = error.localizedDescription
        }
        // Forecast is best-effort — failure doesn't block the cost display
        forecast = try? await ce.getMonthForecast(credentials: credentials)
        isLoading = false
    }
}

// MARK: - CloudWidget conformance

struct CostWidgetView: View, CloudWidget {
    static let type = WidgetTypeKey.costMonth

    private let config: [String: String]

    @Environment(AppState.self) private var appState
    @State private var vm = CostViewModel()

    init(config: [String: String]) {
        self.config = config
    }

    func render() -> AnyView { AnyView(self) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Cloud Spend", icon: "dollarsign.circle")

            if vm.isLoading && vm.monthlyCost == nil {
                LoadingView(message: "Loading cost data…").frame(height: 100)
            } else if let err = vm.lastError {
                ErrorBanner(message: err) { vm.lastError = nil }
            } else if let cost = vm.monthlyCost {
                costSummary(cost: cost)
                if !cost.serviceCosts.isEmpty {
                    Divider()
                    serviceBreakdown(costs: cost.serviceCosts)
                }
            } else {
                emptyState
            }

            if let ts = vm.lastRefresh {
                Text("Updated \(ts, formatter: relativeFormatter)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .cloudCard()
        .task {
            if let creds = appState.credentials { await vm.refresh(credentials: creds) }
        }
    }

    // MARK: Sub-views

    private func costSummary(cost: CostService.MonthlyCost) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("This Month")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(formatted(amount: cost.amount, unit: cost.unit))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient.primaryGradient)

                if let fc = vm.forecast {
                    Label(
                        "Forecast: \(formatted(amount: fc.amount, unit: fc.unit))",
                        systemImage: "arrow.up.right"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            Spacer()

            // Donut-style mini chart
            if cost.serviceCosts.count > 1 {
                costDonut(costs: cost.serviceCosts, total: cost.amount)
            }
        }
    }

    private func costDonut(costs: [CostService.ServiceCost], total: Double) -> some View {
        Chart(costs.prefix(5)) { svc in
            SectorMark(
                angle: .value("Cost", svc.amount / total * 100),
                innerRadius: .ratio(0.6),
                angularInset: 1
            )
            .foregroundStyle(by: .value("Service", svc.serviceName))
            .cornerRadius(3)
        }
        .chartLegend(.hidden)
        .frame(width: 70, height: 70)
    }

    private func serviceBreakdown(costs: [CostService.ServiceCost]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By Service")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            ForEach(costs.prefix(6)) { svc in
                HStack {
                    Text(cleanServiceName(svc.serviceName))
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(formatted(amount: svc.amount, unit: svc.unit))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.deepSkyBlue)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "dollarsign.circle")
                .font(.largeTitle)
                .foregroundColor(.secondary.opacity(0.4))
            Text("No cost data available")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Helpers

    private func formatted(amount: Double, unit: String) -> String {
        let symbol = unit == "USD" ? "$" : unit + " "
        if amount >= 1000 {
            return String(format: "\(symbol)%.2fK", amount / 1000)
        }
        return String(format: "\(symbol)%.2f", amount)
    }

    /// Strips lengthy AWS service name prefixes for compact display.
    private func cleanServiceName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "Amazon ", with: "")
            .replacingOccurrences(of: "AWS ", with: "")
    }
}

// MARK: - Helpers

private let relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .short
    return f
}()

// MARK: - Preview

#Preview {
    ScrollView {
        CostWidgetView(config: [:])
            .padding()
    }
    .environment(AppState.preview)
    .background(Color.cloudWhite)
}
