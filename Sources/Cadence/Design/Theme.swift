import SwiftUI
import AppKit

enum Theme {
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let base: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
    }

    static let musicAccent = Color(red: 0.972, green: 0.216, blue: 0.341)
    static let podcastAccent = Color(red: 0.557, green: 0.345, blue: 0.925)
    static let sidebarWidth: CGFloat = 228
    static let headerHeight: CGFloat = 54
    static let playerHeight: CGFloat = 78
    static let navStripHeight: CGFloat = 42

    static func accent(for source: PlaybackSource) -> Color {
        switch source {
        case .music: return musicAccent
        case .podcasts: return podcastAccent
        }
    }

    static func artworkGradient(for seed: String) -> LinearGradient {
        var hash: UInt64 = 1469598103934665603
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        let hue = Double(hash % 360) / 360.0
        let secondHue = (hue + 0.12).truncatingRemainder(dividingBy: 1)
        let c1 = Color(hue: hue, saturation: 0.38, brightness: 0.72)
        let c2 = Color(hue: secondHue, saturation: 0.48, brightness: 0.46)
        return LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum PlaybackSource: String, Codable, Sendable {
    case music
    case podcasts

    var title: String {
        switch self {
        case .music: return "Music"
        case .podcasts: return "Подкасты"
        }
    }

    var icon: String {
        switch self {
        case .music: return "music.note"
        case .podcasts: return "mic.fill"
        }
    }

    var accent: Color { Theme.accent(for: self) }
}

struct IconButton: View {
    let systemName: String
    var help: String? = nil
    var size: CGFloat = 28
    var accent: Color? = nil
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent ?? .primary)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hovering ? Color.primary.opacity(0.08) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help ?? "")
        .accessibilityLabel(help ?? systemName)
    }
}

struct PillButton: View {
    let title: String
    var systemImage: String? = nil
    var accent: Color = Theme.musicAccent
    var filled: Bool = true
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .frame(height: 30)
            .foregroundStyle(filled ? Color.white : Color.primary)
            .background {
                CapaBackground(accent: accent, filled: filled, hovering: hovering)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct CapaBackground: View {
    let accent: Color
    let filled: Bool
    let hovering: Bool

    var body: some View {
        if filled {
            Capsule()
                .fill(accent.opacity(hovering ? 0.88 : 1))
        } else {
            Capsule()
                .fill(hovering ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
        }
    }
}

struct SectionTitle: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

struct BannerView: View {
    enum Kind {
        case info
        case warning
        case error

        var icon: String {
            switch self {
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.octagon"
            }
        }

        var tint: Color {
            switch self {
            case .info: return .accentColor
            case .warning: return .orange
            case .error: return .red
            }
        }
    }

    let kind: Kind
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: kind.icon)
                .foregroundStyle(kind.tint)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderless)
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(kind.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .strokeBorder(kind.tint.opacity(0.16), lineWidth: 1)
        )
    }
}

extension View {
    func cardSurface(cornerRadius: CGFloat = Theme.Radius.medium) -> some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }

    func sidebarSurface() -> some View {
        background(.regularMaterial)
    }
}

extension NSImage {
    func jpegData(compressionQuality: CGFloat = 0.82) -> Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }
}
