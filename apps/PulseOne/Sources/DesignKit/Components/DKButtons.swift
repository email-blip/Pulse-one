import SwiftUI

/// Primary action ("Meine Einheit starten ↗"): Bio Cyan fill, Obsidian text. One per screen.
struct DKPrimaryButtonStyle: ButtonStyle {
    /// Stretch to the available width (stacked layouts, XXXL) or hug the label (mockup).
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration) {
            configuration.label
                .font(DKFont.bodyEmphasis)
                .foregroundStyle(DKColor.onAccent)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DKSpace.xl)
                .padding(.vertical, DKSpace.m)
                .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: DKSize.buttonHeight)
                .background(RoundedRectangle(cornerRadius: DKRadius.control, style: .continuous).fill(DKColor.accent))
                .contentShape(RoundedRectangle(cornerRadius: DKRadius.control, style: .continuous))
        }
    }
}

/// Secondary action ("Warum?"): quiet outline on a raised surface, text carries the meaning.
struct DKSecondaryButtonStyle: ButtonStyle {
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration) {
            configuration.label
                .font(DKFont.label)
                .foregroundStyle(DKColor.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DKSpace.l)
                .padding(.vertical, DKSpace.m)
                .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: DKSize.buttonHeight)
                .background(
                    RoundedRectangle(cornerRadius: DKRadius.control, style: .continuous)
                        .fill(configuration.isPressed ? DKColor.surfaceSelected : DKColor.surfaceRaised)
                        .overlay(RoundedRectangle(cornerRadius: DKRadius.control, style: .continuous)
                            .strokeBorder(DKColor.lineStrong, lineWidth: 1))
                )
                .contentShape(RoundedRectangle(cornerRadius: DKRadius.control, style: .continuous))
        }
    }
}

/// Small capsule button ("Vorlesen", "Kacheln anordnen" as a button).
struct DKPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration) {
            configuration.label
                .font(DKFont.label)
                .foregroundStyle(DKColor.textPrimary)
                .padding(.horizontal, DKSpace.l)
                .frame(minHeight: DKSize.minTouch)
                .background(
                    Capsule().fill(configuration.isPressed ? DKColor.surfaceSelected : DKColor.surfaceRaised)
                        .overlay(Capsule().strokeBorder(DKColor.lineStrong, lineWidth: 1))
                )
                .contentShape(Capsule())
        }
    }
}

/// Text-only action in a section head ("Kacheln anordnen").
struct DKTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DKFont.label)
            .foregroundStyle(DKColor.accent)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .frame(minHeight: DKSize.minTouch)
            .contentShape(Rectangle())
    }
}

/// Shared press feedback: slight scale (none under Reduce Motion) and dimming, curve from `MotionEvent.press`.
private struct PressableLabel<Content: View>: View {
    let configuration: ButtonStyleConfiguration
    @ViewBuilder var content: Content
    @Environment(\.reduceMotionEffective) private var reduceMotion
    @Environment(\.freezeAnimations) private var frozen
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        content
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.88 : 1) : 0.45)
            .animation(MotionEvent.press.resolvedAnimation(reduceMotion: reduceMotion, frozen: frozen), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == DKPrimaryButtonStyle {
    static var dkPrimary: DKPrimaryButtonStyle { DKPrimaryButtonStyle() }
}

extension ButtonStyle where Self == DKSecondaryButtonStyle {
    static var dkSecondary: DKSecondaryButtonStyle { DKSecondaryButtonStyle() }
}
