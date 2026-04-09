// CPUChartWidget.swift
// Renders a CloudWatch CPUUtilization line chart using Swift Charts.

import SwiftUI
import Charts

// MARK: - ViewModel

@Observable
final class CPUChartViewModel {

    var datapoints: [MetricDatapoint] = []
    var instances:  [EC2Instance]     = []
    var selectedInstanceId: String?
    var isLoading   = false
    var lastError:  String?

    private let cw  = CloudWatchService()
    private let ec2 = EC2Service()

    @MainActor
    func load(credentials: AWSCredentials) async {
        guard instances.isEmpty else {
            if let id = selectedInstanceId { await fetchMetrics(instanceId: id, credentials: credentials) }
            return
        }
        isLoading = true
        do {
            instances = try await ec2.describeInstances(credentials: credentials)
            if selectedInstanceId == nil {
                selectedInstanceId = instances.first?.id
            }
            if let id = selectedInstanceId {
                await fetchMetrics(instanceId: id, credentials: credentials)
            }
        } catch {
            lastError = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    func fetchMetrics(instanceId: String, credentials: AWSCredentials) async {
        isLoading = true
        lastError = nil
        do {
            datapoints = try await cw.getCPUUtilization(instanceId: instanceId,
                                                         credentials: credentials)
        } catch {
            lastError = error.localizedDescription
        }
        isLoading = false
    }

    var currentCPU: Double? {
        datapoints.last?.value
    }

    var averageCPU: Double? {
        guard !datapoints.isEmpty else { return nil }
        return datapoints.map(\.value).reduce(0, +) / Double(datapoints.count)
    }

    var maxCPU: Double? {
        datapoints.map(\.value).max()
    }
}

// MARK: - CloudWidget conformance

struct CPUChartWidgetView: View, CloudWidget {
    static let type = WidgetTypeKey.cpuChart

    private let config: [String: String]

    @Environment(AppState.self) private var appState
    @State private var vm = CPUChartViewModel()

    init(config: [String: String]) {
        self.config = config
    }

    func render() -> AnyView { AnyView(self) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(title: "CPU Utilization", icon: "cpu")
                Spacer()
                if !vm.instances.isEmpty {
                    instancePicker
                }
            }

            if vm.isLoading && vm.datapoints.isEmpty {
                LoadingView(message: "Loading metrics…").frame(height: 120)
            } else if let err = vm.lastError {
                ErrorBanner(message: err) { vm.lastError = nil }
            } else if vm.datapoints.isEmpty {
                emptyChart
            } else {
                cpuChart
                statRow
            }
        }
        .padding()
        .cloudCard()
        .task {
            if let creds = appState.credentials { await vm.load(credentials: creds) }
        }
        .onChange(of: vm.selectedInstanceId) { _, id in
            Task {
                if let id, let creds = appState.credentials {
                    await vm.fetchMetrics(instanceId: id, credentials: creds)
                }
            }
        }
    }

    // MARK: Sub-views

    private var instancePicker: some View {
        Menu {
            ForEach(vm.instances) { inst in
                Button(inst.name) { vm.selectedInstanceId = inst.id }
            }
        } label: {
            HStack(spacing: 4) {
                Text(vm.instances.first(where: { $0.id == vm.selectedInstanceId })?.name ?? "Select")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.deepSkyBlue)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.deepSkyBlue)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.deepSkyBlue.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var cpuChart: some View {
        Chart(vm.datapoints) { dp in
            AreaMark(
                x: .value("Time",  dp.timestamp),
                y: .value("CPU %", dp.value)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [.deepSkyBlue.opacity(0.4), .deepSkyBlue.opacity(0.0)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            LineMark(
                x: .value("Time",  dp.timestamp),
                y: .value("CPU %", dp.value)
            )
            .foregroundStyle(Color.deepSkyBlue)
            .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartYScale(domain: 0...max(100, (vm.datapoints.map(\.value).max() ?? 100) * 1.1))
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.2))
                AxisValueLabel(format: .dateTime.hour())
                    .foregroundStyle(Color.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { val in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.2))
                AxisValueLabel {
                    if let v = val.as(Double.self) {
                        Text("\(Int(v))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .frame(height: 140)
    }

    private var statRow: some View {
        HStack(spacing: 0) {
            cpuStat(label: "Now",  value: vm.currentCPU)
            Divider().frame(height: 30)
            cpuStat(label: "Avg",  value: vm.averageCPU)
            Divider().frame(height: 30)
            cpuStat(label: "Peak", value: vm.maxCPU)
        }
        .frame(maxWidth: .infinity)
    }

    private func cpuStat(label: String, value: Double?) -> some View {
        VStack(spacing: 2) {
            Text(value.map { String(format: "%.1f%%", $0) } ?? "--")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.deepSkyBlue)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyChart: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.largeTitle)
                .foregroundColor(.secondary.opacity(0.4))
            Text("No metric data available")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        CPUChartWidgetView(config: [:])
            .padding()
    }
    .environment(AppState.preview)
    .background(Color.cloudWhite)
}
