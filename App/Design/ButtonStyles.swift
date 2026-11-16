import SwiftUI

/// tvOS focus for large content (the newest frame): slight lift, light border, shadow.
/// Teal is never used for focus.
struct LiftButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = Theme.radius
    var scale: CGFloat = 1.02

    func makeBody(configuration: Configuration) -> some View {
        FocusBody(configuration: configuration, cornerRadius: cornerRadius, scale: scale)
    }

    private struct FocusBody: View {
        let configuration: Configuration
        let cornerRadius: CGFloat
        let scale: CGFloat
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Theme.focus, lineWidth: focused ? 3 : 0))
                .scaleEffect(focused ? (configuration.isPressed ? 1 : scale) : 1)
                .shadow(color: .black.opacity(focused ? 0.45 : 0), radius: 24, y: 12)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

/// Round icon button in the header; inverts when focused.
struct GearButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FocusBody(configuration: configuration)
    }

    private struct FocusBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(focused ? Theme.bg : Theme.text2)
                .frame(width: 64, height: 64)
                .background(focused ? Theme.focus : Theme.surface, in: .circle)
                .scaleEffect(focused ? 1.12 : 1)
                .shadow(color: .black.opacity(focused ? 0.45 : 0), radius: 16, y: 8)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}
