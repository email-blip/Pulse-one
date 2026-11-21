import SwiftUI

/// Shared building blocks for every tab (DESIGN-SYSTEM-5.0 §4). Views use these instead of raw styling.

/// Calm dark page background used behind every screen.
struct ScreenBackground: View {
    var body: some View {
        LinearGradient(colors: [Palette.obsidian, Palette.surfaceRaised.opacity(0.6), Palette.obsidian],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

/// Small caps section title.
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(Typography.motto)
            .tracking(1.5)
            .foregroundStyle(Palette.inkMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .wraps()
            .accessibilityAddTraits(.isHeader)
    }
}

/// "Testansicht" label shown on every screen of a UI-test scenario.
struct TestBanner: View {
    var body: some View {
        Label("Testansicht für Screenshots – keine echten Messwerte", systemImage: "testtube.2")
            .font(Typography.caption)
            .foregroundStyle(Palette.obsidian)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.iceWhite))
            .accessibilityIdentifier("testBanner")
    }
}

/// Honest empty state: what is missing and what to do next.
struct EmptyState: View {
    let title: String
    let message: String
    var systemImage = "tray"
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        Card {
            Label(title, systemImage: systemImage)
                .font(Typography.label)
                .foregroundStyle(Palette.ink)
                .wraps()
            Text(message)
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

/// One measured or computed value with unit, time, source and its place in the personal band.
struct MetricCard: View {
    let title: String
    let systemImage: String
    let value: String
    let unit: String
    /// e.g. "heute 07:12 · Ring R03"
    let detail: String
    /// e.g. "im üblichen Bereich" or "Noch 3 Tage bis zu deinem persönlichen Bereich"
    var bandText: String?
    var tint: Color = Palette.bioCyan
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 34

    var body: some View {
        Card {
            Label(title, systemImage: systemImage)
                .font(Typography.label)
                .foregroundStyle(tint)
                .wraps()
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                Text(value)
                    .font(Typography.vital(size: valueSize))
                    .foregroundStyle(Palette.ink)
                Text(unit)
                    .font(Typography.label)
                    .foregroundStyle(Palette.inkMuted)
            }
            Text(detail)
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
            if let bandText {
                Text(bandText)
                    .font(Typography.caption.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .wraps()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Visible statement types (DESIGN-SYSTEM-5.0 §6): measured, computed, observed, Claude's reading, suggestion, see a doctor.
enum StatementKind: CaseIterable {
    case measured, computed, observed, interpretation, suggestion, medicalCheck

    var title: String {
        switch self {
        case .measured: "gemessen"
        case .computed: "berechnet"
        case .observed: "beobachtet"
        case .interpretation: "Deutung von Claude"
        case .suggestion: "Vorschlag"
        case .medicalCheck: "ärztlich abklären"
        }
    }

    var systemImage: String {
        switch self {
        case .measured: "waveform.path.ecg"
        case .computed: "function"
        case .observed: "eye"
        case .interpretation: "sparkles"
        case .suggestion: "arrow.forward.circle"
        case .medicalCheck: "stethoscope"
        }
    }

    var tint: Color {
        switch self {
        case .measured: Palette.bioCyan
        case .computed, .observed: Palette.inkMuted
        case .interpretation, .suggestion: Palette.neuralViolet
        case .medicalCheck: Palette.ink
        }
    }
}

struct StatementBadge: View {
    let kind: StatementKind
    var body: some View {
        Label(kind.title, systemImage: kind.systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(kind.tint)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .background(Capsule().fill(Palette.surfaceButton))
    }
}

extension EnvironmentValues {
    /// Opens the profile sheet (profile, devices, ring, settings). Every tab puts `ProfileButton()` in its toolbar.
    @Entry var openProfile: @MainActor @Sendable () -> Void = {}
}

/// Profile button for the top right of every tab: `.toolbar { ToolbarItem(placement: .topBarTrailing) { ProfileButton() } }`.
struct ProfileButton: View {
    @Environment(\.openProfile) private var openProfile
    var body: some View {
        Button { openProfile() } label: {
            Image(systemName: "person.crop.circle")
                .font(.title3)
                .foregroundStyle(Palette.ink)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Profil und Geräte")
        .accessibilityIdentifier("openProfile")
    }
}

extension View {
    /// Marks the root of a test-scenario screen (`screen.<name>`) only while that scenario runs,
    /// so UI tests find exactly one screen identifier.
    @ViewBuilder
    func screenIdentifier(_ scenario: String) -> some View {
        if LaunchOptions.current.scenario == scenario {
            accessibilityElement(children: .contain).accessibilityIdentifier("screen.\(scenario)")
        } else {
            self
        }
    }

    /// Standard toolbar of a tab: profile button top right.
    func profileToolbar() -> some View {
        toolbar { ToolbarItem(placement: .topBarTrailing) { ProfileButton() } }
    }
}
