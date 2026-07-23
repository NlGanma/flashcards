import SwiftUI
import AppKit

/// Native hover feedback: a subtle scale/lift plus the macOS pointing-hand cursor.
///
/// `NSCursor`'s stack is process-global, so a push without its pop leaves the pointing
/// hand stuck over the whole app. `cursor` can flip while the pointer is still inside the
/// view — the Previous arrow becomes disabled the moment you click back to card 1 — so the
/// pop is driven by whether this modifier actually pushed, never by the current flag.
struct HoverEffect: ViewModifier {
    var scale: CGFloat = 1.02
    var cursor: Bool = true
    @State private var hovering = false
    @State private var didPush = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? scale : 1)
            .animation(Motion.quick, value: hovering)
            .onHover { hovering = $0 }
            .onChange(of: hovering) { isHovering in
                if isHovering {
                    guard cursor, !didPush else { return }
                    NSCursor.pointingHand.push()
                    didPush = true
                } else if didPush {
                    NSCursor.pop()
                    didPush = false
                }
            }
            .onDisappear {
                if didPush {
                    NSCursor.pop()
                    didPush = false
                }
                hovering = false
            }
    }
}

extension View {
    /// Adds a hover lift + pointing-hand cursor to a clickable element.
    /// (Named `hoverLift` to avoid colliding with SwiftUI's own `hoverEffect`.)
    func hoverLift(scale: CGFloat = 1.02, cursor: Bool = true) -> some View {
        modifier(HoverEffect(scale: scale, cursor: cursor))
    }

    /// Reports hover state (for bespoke hover styling) and manages the cursor.
    func hoverCursor(_ isHovering: Binding<Bool>) -> some View {
        onHover { hovering in
            isHovering.wrappedValue = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onDisappear {
            if isHovering.wrappedValue { NSCursor.pop(); isHovering.wrappedValue = false }
        }
    }
}

/// Light trackpad haptics for the core reward moments. No entitlement required and a
/// no-op on hardware without a Force Touch trackpad.
enum Haptics {
    static func mark() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
    static func light() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }
}
