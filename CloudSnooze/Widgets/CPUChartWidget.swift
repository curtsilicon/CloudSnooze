// CPUChartWidget.swift
// Renders a CloudWatch CPUUtilization line chart using Swift Charts.

import SwiftUI
import Charts

// MARK: - ViewModel

@Observable
final class CPUChartViewModel {

    var datapoints: [MetricDatapoint] = []
    var selectedInstanceId: String?
    var isLoading    = false
    var lastError:   String?
    /// True after a fetch completed with zero datapoints (instance was off during window)
    var fetchedEmpty = false

    private let cw = CloudWatchService()

    /// Seed the selected instance from the discovered list and fetch fresh metrics.
    @MainActor
    func load(instances: [EC2Instance], credentials: AWSCredentials) async {
        if selectedInstanceId == nil || !instances.contains(where: { $0.id == selectedInstanceId }) {
            selectedInstanceId = instances.first?.id
        }
        guard let id = selectedInstanceId else { return }
        let region = instances.first(where: { $0.id == id })?.region ?? credentials.region
        let regionalCreds = AWSCredentials(
            accessKeyId:     credentials.accessKeyId,
            secretAccessKey: credentials.secretAccessKey,
            region:          region
        )
        datapoints   = []
        fetchedEmpty = false
        await fetchMetrics(instanceId: id, credentials: regionalCreds)
    }

    @MainActor
    func fetchMetrics(instanceId: String, credentials: AWSCredentials) async {
        isLoading    = true
        lastError    = nil
        fetchedEmpty = false
        do {
            let result = try await cw.getCPUUtilization(instanceId: instanceId,
                                                         hours: 12,
                                                         credentials: credentials)
            datapoints   = result
            fetchedEmpty = result.isEmpty
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

    /// Splits datapoints into contiguous segments separated by gaps > 10 minutes.
    /// Swift Charts draws a line per series, so gaps between segments are left blank
    /// instead of being bridged with a misleading straight line.
    var segments: [[MetricDatapoint]] {
        guard !datapoints.isEmpty else { return [] }
        let gap: TimeInterval = 7 * 60   // > one 5-min period means a missing datapoint
        var result: [[MetricDatapoint]] = []
        var current: [MetricDatapoint] = [datapoints[0]]
        for i in 1..<datapoints.count {
            if datapoints[i].timestamp.timeIntervalSince(datapoints[i - 1].timestamp) > gap {
                result.append(current)
                current = []
            }
            current.append(datapoints[i])
        }
        result.append(current)
        return result
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
                if !appState.discoveredInstances.isEmpty {
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
        .task(id: appState.refreshToken) {
            guard !appState.discoveredInstances.isEmpty, let creds = appState.credentials else { return }
            await vm.load(instances: appState.discoveredInstances, credentials: creds)
        }
    }

    // MARK: Sub-views

    private var instancePicker: some View {
        Menu {
            ForEach(appState.discoveredInstances) { inst in
                Button(inst.name) {
                    vm.selectedInstanceId = inst.id
                    Task {
                        if let creds = appState.credentials {
                            let regionalCreds = AWSCredentials(
                                accessKeyId:     creds.accessKeyId,
                                secretAccessKey: creds.secretAccessKey,
                                region:          inst.region
                            )
                            await vm.fetchMetrics(instanceId: inst.id, credentials: regionalCreds)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(appState.discoveredInstances.first(where: { $0.id == vm.selectedInstanceId })?.name ?? "Select")
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
        let yMax    = max(5.0, (vm.datapoints.map(\.value).max() ?? 5.0) * 1.2)
        let xMin    = vm.datapoints.first?.timestamp ?? Date().addingTimeInterval(-3600)
        let xMax    = vm.datapoints.last?.timestamp  ?? Date()

        // Build gap intervals from segments for rendering as background bands
        let gaps: [(start: Date, end: Date)] = vm.segments.enumerated().compactMap { idx, segment in
            guard idx > 0,
                  let gapStart = vm.segments[safe: idx - 1]?.last?.timestamp,
                  let gapEnd   = segment.first?.timestamp
            else { return nil }
            return (gapStart, gapEnd)
        }

        return Chart {
            // Gap bands first (rendered behind the data lines)
            ForEach(Array(gaps.enumerated()), id: \.offset) { _, gap in
                RectangleMark(
                    xStart: .value("Gap Start", gap.start),
                    xEnd:   .value("Gap End",   gap.end),
                    yStart: .value("y0", 0),
                    yEnd:   .value("y1", yMax)
                )
                .foregroundStyle(Color.statusStopped.opacity(0.12))
            }

            // Data segments
            ForEach(Array(vm.segments.enumerated()), id: \.offset) { _, segment in
                ForEach(segment) { dp in
                    AreaMark(
                        x: .value("Time",  dp.timestamp),
                        y: .value("CPU %", dp.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.deepSkyBlue.opacity(0.35), .deepSkyBlue.opacity(0.0)],
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
                .interpolationMethod(.monotone)
            }
        }
        .chartXScale(domain: xMin...xMax)
        .chartYScale(domain: 0...yMax)
        .chartXAxis {
            // Stride every 30 min for a 12-hour window — readable without crowding
            AxisMarks(values: .stride(by: .minute, count: 30)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.2))
                AxisValueLabel(format: .dateTime.hour().minute())
                    .foregroundStyle(Color.secondary)
                    .font(.system(size: 9))
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

    private var selectedInstance: EC2Instance? {
        appState.discoveredInstances.first { $0.id == vm.selectedInstanceId }
    }

    private var emptyChart: some View {
        // If CloudWatch returned zero datapoints after a successful fetch, the instance
        // was not running during the metric window — inferred purely from polling AWS.
        // If it hasn't been fetched yet (fetchedEmpty = false, datapoints empty), show
        // a neutral "no data yet" message for newly started instances.
        let wasOff = vm.fetchedEmpty

        return VStack(spacing: 8) {
            Image(systemName: wasOff ? "power.circle" : "chart.line.uptrend.xyaxis")
                .font(.largeTitle)
                .foregroundColor(wasOff ? .statusStopped.opacity(0.5) : .secondary.opacity(0.4))
            Text(wasOff ? "No activity in the last 12 hours" : "No metric data yet")
                .font(.subheadline.weight(.medium))
                .foregroundColor(wasOff ? .statusStopped : .secondary)
            Text(wasOff
                 ? "CloudWatch reported no CPU datapoints — the instance was likely off during this window."
                 : "Metrics appear after the instance has been running for a few minutes.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .padding(.vertical, 8)
    }
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
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
