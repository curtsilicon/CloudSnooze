// WidgetRegistry.swift
// Maps widget type strings to their SwiftUI view factory closures.

import SwiftUI

// MARK: - CloudWidget Protocol

/// Every widget must implement this protocol and also conform to View.
protocol CloudWidget: View {
    /// Stable string identifier (matches DashboardWidget.type).
    static var type: String { get }
    /// Initialise from a key/value config bag.
    init(config: [String: String])
    /// Return the rendered view as AnyView.
    func render() -> AnyView
}

// MARK: - WidgetRegistry

final class WidgetRegistry {

    static let shared = WidgetRegistry()

    private typealias Factory = ([String: String]) -> AnyView

    private var factories: [String: Factory] = [:]

    private init() {
        registerDefaults()
    }

    // MARK: - Registration

    /// Register a widget type. Safe to call multiple times (overwrites).
    func register<W: CloudWidget>(_ widgetType: W.Type) {
        factories[W.type] = { config in
            AnyView(WidgetContainerView(widget: W(config: config)))
        }
    }

    /// Build a view for the given widget definition.
    /// Returns a placeholder card if the type is unknown.
    func view(for widget: DashboardWidget) -> AnyView {
        if let factory = factories[widget.type] {
            return factory(widget.config)
        }
        return AnyView(UnknownWidgetView(typeName: widget.type))
    }

    // MARK: - Default registrations

    private func registerDefaults() {
        register(ServerStatusWidgetView.self)
        register(ServerControlWidgetView.self)
        register(CostWidgetView.self)
    }
}

// MARK: - Widget container (applies the card chrome)

private struct WidgetContainerView<W: CloudWidget & View>: View {
    let widget: W
    var body: some View { widget }
}

// MARK: - Unknown widget placeholder

struct UnknownWidgetView: View {
    let typeName: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "questionmark.circle")
                .font(.title2)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Unknown Widget")
                    .font(.headline)
                Text(typeName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .cloudCard()
    }
}
