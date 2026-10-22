import SwiftUI
import UniformTypeIdentifiers

// MARK: - Button styles

/// Filled capsule with the accent (or a custom) gradient — the primary call to action.
struct FilledButtonStyle: ButtonStyle {
    var gradient: LinearGradient = Palette.accentGradient
    var glow: Color = Palette.indigo
    /// A filled button that ignores `.disabled()` looks fully live and just swallows
    /// clicks, which is worse than no affordance at all — so the style reads it directly.
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rounded(15, .semibold))
            .foregroundStyle(isEnabled ? AnyShapeStyle(.white)
                                       : AnyShapeStyle(Color.secondaryText(scheme)))
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .background(
                Capsule().fill(isEnabled
                               ? AnyShapeStyle(gradient)
                               : AnyShapeStyle(Color.primary.opacity(scheme == .dark ? 0.12 : 0.07)))
            )
            .shadow(color: isEnabled ? glow.opacity(configuration.isPressed ? 0.15 : 0.35) : .clear,
                    radius: configuration.isPressed ? 5 : 12, y: 6)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.96 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Soft tinted capsule for secondary actions.
struct SoftButtonStyle: ButtonStyle {
    var tint: Color = Palette.indigo
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rounded(15, .semibold))
            .foregroundStyle(tint)
            .padding(.vertical, 12)
            .padding(.horizontal, 22)
            .background(Capsule().fill(tint.opacity(scheme == .dark ? 0.20 : 0.12)))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Shared style for every "Almost Known" action. Slate is desaturated, so a plain soft
/// fill reads as disabled next to the green and indigo buttons — an outline gives the off
/// state presence without competing with the primary action. The on state fills in, and
/// both states are the same size, so toggling never reflows the row.
struct AlmostButtonStyle: ButtonStyle {
    var isOn: Bool = false
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        let off = Palette.learningTint(scheme)
        return configuration.label
            .font(.rounded(15, .semibold))
            .foregroundStyle(isOn ? AnyShapeStyle(Color.white) : AnyShapeStyle(off))
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(
                Capsule().fill(isOn
                               ? AnyShapeStyle(Palette.learningGradient)
                               : AnyShapeStyle(off.opacity(scheme == .dark ? 0.22 : 0.14)))
            )
            .overlay(
                Capsule().strokeBorder(off.opacity(isOn ? 0 : (scheme == .dark ? 0.35 : 0.28)),
                                       lineWidth: 1)
            )
            .shadow(color: Palette.learning.opacity(isOn ? (configuration.isPressed ? 0.15 : 0.35) : 0),
                    radius: configuration.isPressed ? 5 : 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
            .animation(Motion.quick, value: isOn)
            .contentShape(Capsule())
    }
}

/// Minimal text/icon button.
struct GhostButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rounded(14, .medium))
            .foregroundStyle(Color.secondaryText(scheme))
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.08 : 0)))
            .contentShape(Capsule())
    }
}

// MARK: - Progress bar

struct ProgressBar: View {
    var fraction: Double
    var height: CGFloat = 8
    var tint: LinearGradient = Palette.accentGradient
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(scheme == .dark ? 0.14 : 0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: max(fraction <= 0 ? 0 : height,
                                      geo.size.width * max(0, min(1, fraction))))
            }
        }
        .frame(height: height)
        .animation(Motion.spring, value: fraction)
    }
}

// MARK: - Drag & drop zone

/// Wraps content, highlights on hover, and reports a dropped .xlsx file URL.
struct FileDropZone<Content: View>: View {
    @Binding var isTargeted: Bool
    let onDrop: (URL) -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .onDrop(of: [.fileURL], isTargeted: $isTargeted.animation(Motion.quick)) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { onDrop(url) }
                }
                return true
            }
    }
}

// MARK: - Message banner

struct MessageBanner: View {
    enum Kind { case error, info }
    let kind: Kind
    let text: String
    var onDismiss: (() -> Void)?
    @Environment(\.colorScheme) private var scheme

    private var tint: Color { kind == .error ? Palette.amber : Palette.indigo }
    private var icon: String { kind == .error ? "exclamationmark.triangle.fill" : "info.circle.fill" }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.system(size: 15, weight: .semibold))
            Text(text)
                .font(.rounded(13, .medium))
                .foregroundStyle(Color.primaryText(scheme))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.secondaryText(scheme))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(scheme == .dark ? 0.16 : 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.3), lineWidth: 1)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
