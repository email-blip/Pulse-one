import PulseCore
import SwiftUI

/// "Aktivierung" on the companion screen: today's sessions with time, summary and status, a start button each,
/// the movement-snack hint after quiet hours, and the way to the settings.
struct ActivationSection: View {
    let store: ActivationStore
    /// Companion alarm ("Morgenquelle"), shown as the morning time when it is on.
    let alarm: (hour: Int, minute: Int)?
    let onStart: (ActivationPlan) -> Void

    var body: some View {
        let now = CompanionUI.now
        SectionHeader(title: "Aktivierung")
        if store.settings.isEnabled {
            Card {
                CompanionCardTitle(title: "Heute bewegen", systemImage: "figure.strengthtraining.functional")
                Text("Kurze Einheiten mit eigenem Körpergewicht, passend zu deiner Nacht und deinem Tag.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
                ForEach(store.plans) { plan in
                    ActivationPlanRow(plan: plan, timeText: timeText(plan.slot, now: now),
                                      isDone: store.isDone(plan.slot), onStart: { onStart(plan) })
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("activation.section")
            if let hint = store.snackHint(now: now) {
                ActivationSnackCard(hint: hint, onStart: { onStart(store.plan(for: .snack, now: now)) })
            }
        } else {
            Card {
                CompanionCardTitle(title: "Aktivierung ist aus", systemImage: "figure.strengthtraining.functional")
                Text("Kurze Einheiten mit Liegestützen, Zug- und Rumpfübungen morgens, mittags und abends. In den Einstellungen einschalten.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("activation.section")
        }
        NavigationLink {
            ActivationSettingsView(store: store)
        } label: {
            Label("Aktivierung einstellen", systemImage: "slider.horizontal.3")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityIdentifier("activation.settings")
    }

    private func timeText(_ slot: ActivationSlot, now: Date) -> String {
        if let time = store.time(of: slot, now: now) { return CompanionUI.time(time) }
        if slot == .morning, let alarm { return "nach dem Wecken, \(CompanionUI.clock(hour: alarm.hour, minute: alarm.minute))" }
        return "nach dem Aufstehen"
    }
}

/// One session of the day: slot, time, summary, status and its start button.
private struct ActivationPlanRow: View {
    let plan: ActivationPlan
    let timeText: String
    let isDone: Bool
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label(plan.slot.title, systemImage: plan.slot.symbol)
                    .font(Typography.label)
                    .foregroundStyle(Palette.ink)
                    .wraps()
                Text("\(timeText) · \(isDone ? "erledigt" : "offen")")
                    .font(Typography.caption.weight(.semibold))
                    .foregroundStyle(isDone ? Palette.bioCyan : Palette.inkMuted)
                    .wraps()
                Text(plan.summary)
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                    .wraps()
            }
            .accessibilityElement(children: .combine)
            Button(action: onStart) {
                Label(isDone ? "Noch einmal" : "Starten", systemImage: isDone ? "arrow.counterclockwise" : "play.fill")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityLabel(isDone ? "\(plan.slot.title) noch einmal" : "\(plan.slot.title) starten")
            .accessibilityIdentifier("activation.start.\(plan.slot.rawValue)")
        }
        .padding(.top, Spacing.xs)
    }
}

/// Hint after quiet hours with a 2–3 minute snack.
private struct ActivationSnackCard: View {
    let hint: String
    let onStart: () -> Void

    var body: some View {
        Card {
            CompanionCardTitle(title: ActivationSlot.snack.title, systemImage: ActivationSlot.snack.symbol)
            Text(hint)
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
                .wraps()
            StatementBadge(kind: .observed)
            Button(action: onStart) {
                Label("Snack starten", systemImage: "play.fill")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("activation.snack")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activation.snackCard")
    }
}
