// DesignSystem.swift
// CloudSnooze – color palette, typography, and shared UI helpers

import SwiftUI

// MARK: - Color Palette

extension Color {
    /// Deep Sky Blue  #3A8DFF
    static let deepSkyBlue   = Color(hex: "#3A8DFF")
    /// Cloud Indigo   #4C5BD4
    static let cloudIndigo   = Color(hex: "#4C5BD4")
    /// Soft Cyan      #6FE3FF
    static let softCyan      = Color(hex: "#6FE3FF")
    /// Cloud White    #F4F7FB
    static let cloudWhite    = Color(hex: "#F4F7FB")
    /// Storm Gray     #1F2633
    static let stormGray     = Color(hex: "#1F2633")

    // Semantic aliases
    static let crPrimary     = Color.deepSkyBlue
    static let crSecondary   = Color.cloudIndigo
    static let crAccent      = Color.softCyan
    static let crBackground  = Color.cloudWhite
    static let crDarkBG      = Color.stormGray

    /// Adaptive background: cloud-white in light, storm-gray in dark
    static let crAdaptiveBG  = Color("AdaptiveBackground")

    // Status colors
    static let statusRunning = Color(hex: "#30D158")   // green
    static let statusStopped = Color(hex: "#FF453A")   // red
    static let statusPending = Color(hex: "#FFD60A")   // yellow

    // MARK: hex initialiser
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double( int        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Gradient helpers

extension LinearGradient {
    static let primaryGradient = LinearGradient(
        colors: [.deepSkyBlue, .cloudIndigo],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let accentGradient = LinearGradient(
        colors: [.softCyan, .deepSkyBlue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let subtleCardGradient = LinearGradient(
        colors: [Color.white.opacity(0.05), Color.white.opacity(0.0)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Card modifier

struct CloudCard: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(colorScheme == .dark
                          ? Color(hex: "#28303F")
                          : Color.white)
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08),
                            radius: 12, x: 0, y: 4)
            )
    }
}

extension View {
    func cloudCard() -> some View { modifier(CloudCard()) }
}

// MARK: - Status badge

struct StatusBadge: View {
    let status: String

    private var color: Color {
        switch status.lowercased() {
        case "running":          return .statusRunning
        case "stopped":          return .statusStopped
        case "pending",
             "stopping",
             "starting":         return .statusPending
        default:                 return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.6), radius: 3)
            Text(status.capitalized)
                .font(.caption.weight(.semibold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LinearGradient.primaryGradient)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
            Spacer()
        }
    }
}

// MARK: - Gradient button

struct GradientButton: View {
    let title: String
    let systemImage: String?
    let gradient: LinearGradient
    let action: () -> Void

    init(title: String,
         systemImage: String? = nil,
         gradient: LinearGradient = .primaryGradient,
         action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.gradient = gradient
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let img = systemImage {
                    Image(systemName: img)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

// MARK: - Loading overlay

struct LoadingView: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.deepSkyBlue)
                .scaleEffect(1.2)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Error banner

struct ErrorBanner: View {
    let message: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.statusStopped)
            Text(message)
                .font(.caption)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
            Spacer()
            if let dismiss = onDismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color.statusStopped.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.statusStopped.opacity(0.3), lineWidth: 1)
        )
    }
}
