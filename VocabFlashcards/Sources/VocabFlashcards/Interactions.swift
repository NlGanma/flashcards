import SwiftUI
import AppKit

/// Native hover feedback: a subtle scale/lift plus the macOS pointing-hand cursor.
/// Cursor push/pop is balanced and cleaned up on disappear so it can't get stuck.
struct HoverEffect: ViewModifier {
    var scale: CGFloat = 1.02
    var cursor: Bool = true
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? scale : 1)
            .animation(Motion.quick, value: hovering)
            .onHover { hovering = $0 }
            .onChange(of: hovering) { isHovering in
                guard cursor else { return }
                if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onDisappear {
                if hovering {
                    if cursor { NSCursor.pop() }
                    hovering = false
                }
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
