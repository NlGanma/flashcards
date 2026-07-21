import SwiftUI

/// Central design tokens: a calm indigo/violet palette, rounded typography, soft
/// materials, and spring animations. Everything adapts to light and dark mode.
enum Palette {
    static let indigo = Color(red: 0.36, green: 0.40, blue: 0.93)
    static let indigoLight = Color(red: 0.66, green: 0.69, blue: 1.0)
    static let violet = Color(red: 0.56, green: 0.44, blue: 0.96)
    /// Deeper indigo for text/glyphs sitting on an indigo tint (better contrast).
    static let indigoDeep = Color(red: 0.28, green: 0.30, blue: 0.72)
    static let success = Color(red: 0.16, green: 0.72, blue: 0.52)
    static let successDeep = Color(red: 0.09, green: 0.60, blue: 0.44)
    /// Neutral slate-violet for "still learning" / un-mark / Almost Known — amber is
    /// reserved for warnings.
    static let learning = Color(red: 0.52, green: 0.53, blue: 0.68)
    static let learningDeep = Color(red: 0.40, green: 0.41, blue: 0.56)
    static let amber = Color(red: 0.98, green: 0.63, blue: 0.31)

    /// Slate is too pale to carry text on a light background — use the deeper variant
    /// there so a slate control never reads as disabled next to the green/indigo ones.
    static func learningTint(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? learning : learningDeep
    }

    static let accentGradient = LinearGradient(
        colors: [indigo, violet],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let successGradient = LinearGradient(
        colors: [Color(red: 0.07, green: 0.50, blue: 0.35),
                 Color(red: 0.04, green: 0.37, blue: 0.27)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let learningGradient = LinearGradient(
        colors: [Color(red: 0.36, green: 0.38, blue: 0.53),
                 Color(red: 0.26, green: 0.28, blue: 0.42)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

enum Metric {
    static let cardCorner: CGFloat = 30
    static let panelCorner: CGFloat = 20
    static let controlCorner: CGFloat = 13
    static let cardMaxWidth: CGFloat = 560
    static let cardHeight: CGFloat = 380
}

enum Motion {
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.78)
    static let gentleSpring = Animation.spring(response: 0.55, dampingFraction: 0.82)
    static let flip = Animation.spring(response: 0.55, dampingFraction: 0.85)
    static let quick = Animation.easeInOut(duration: 0.22)
    /// Springy overshoot for celebratory pops (the "known" flourish).
    static let pop = Animation.spring(response: 0.34, dampingFraction: 0.58)
}

extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension Color {
    /// Adaptive surface color for cards/panels.
    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.14, green: 0.15, blue: 0.20) : .white
    }
    static func subtleSurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 1, opacity: 0.06) : Color(red: 0.96, green: 0.97, blue: 1.0)
    }
    static func primaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.96) : Color(red: 0.12, green: 0.13, blue: 0.20)
    }
    static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.62) : Color(red: 0.42, green: 0.44, blue: 0.52)
    }
}

/// The ambient window background: a soft vertical gradient with two blurred accent
/// glows that give the app a calm, premium depth.
struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(red: 0.07, green: 0.08, blue: 0.12), Color(red: 0.10, green: 0.09, blue: 0.15)]
                    : [Color(red: 0.97, green: 0.975, blue: 1.0), Color(red: 0.93, green: 0.94, blue: 0.99)],
                startPoint: .top, endPoint: .bottom
            )
            Circle()
                .fill(Palette.violet.opacity(scheme == .dark ? 0.20 : 0.13))
                .frame(width: 440, height: 440)
                .blur(radius: 130)
                .offset(x: 180, y: -200)
            Circle()
                .fill(Palette.indigo.opacity(scheme == .dark ? 0.18 : 0.11))
                .frame(width: 380, height: 380)
                .blur(radius: 130)
                .offset(x: -180, y: 220)
        }
        .ignoresSafeArea()
    }
}

/// Soft elevated card/panel styling.
struct PanelBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var corner: CGFloat = Metric.panelCorner
    var elevated: Bool = true

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color.surface(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(scheme == .dark ? 0.08 : 0.05), lineWidth: 1)
            )
            .shadow(color: .black.opacity(elevated ? (scheme == .dark ? 0.45 : 0.10) : 0),
                    radius: elevated ? 22 : 0, x: 0, y: elevated ? 12 : 0)
    }
}

extension View {
    func panel(corner: CGFloat = Metric.panelCorner, elevated: Bool = true) -> some View {
        modifier(PanelBackground(corner: corner, elevated: elevated))
    }
}
