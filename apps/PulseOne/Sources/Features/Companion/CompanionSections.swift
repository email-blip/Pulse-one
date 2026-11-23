import PulseCore
import SwiftUI

// Cards of the companion screen. Each card receives only the data it shows.

/// Evidence label (A–D) as a quiet capsule, e.g. "Etikett C · wackelig, Annäherung".
struct EvidenceTag: View {
    let label: EvidenceLabel

    var body: some View {
        Text("Etikett \(label.rawValue) · \(label.title)")
            .font(Typography.caption.weight(.semibold))
            .foregroundStyle(Palette.inkMuted)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .background(Capsule().fill(Palette.surfaceButton))
            .wraps()
    }
}

/// Card title in the module's style.
struct CompanionCardTitle: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(Typography.label)
            .foregroundStyle(Palette.bioCyan)
            .wraps()
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Alarm

struct AlarmCard: View {
    let store: CompanionStore
    @ScaledMetric(relativeTo: .largeTitle) private var timeSize: CGFloat = 40

    var body: some View {
        let settings = store.settings
        let days = Set(settings.weekdays)
        Card {
            CompanionCardTitle(title: "Wecker „Morgenquelle“", systemImage: "alarm")
            Text(CompanionUI.clock(hour: settings.alarmHour, minute: settings.alarmMinute))
                .font(Typography.vital(size: timeSize))
                .foregroundStyle(settings.alarmEnabled ? Palette.ink : Palette.inkMuted)
                .accessibilityLabel("Weckzeit \(CompanionUI.clock(hour: settings.alarmHour, minute: settings.alarmMinute))")
            Text(CompanionWeekday.summary(days))
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
            Toggle(isOn: Binding(get: { store.settings.alarmEnabled }, set: { save(enabled: $0, days: days) })) {
                Text("Wecker an")
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                    .wraps()
            }
            .tint(Palette.bioCyan)
            .accessibilityIdentifier("companion.alarmToggle")
            if !store.isAlarmKitAvailable {
                Label("Auf diesem iPhone kommt der Wecker als Mitteilung mit Ton; Stumm-Modus und Fokus können ihn leise schalten. Ab iOS 26 klingelt er wie ein echter Wecker.",
                      systemImage: "info.circle")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
            }
            if let error = store.lastError {
                Text(error)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.ink)
                    .wraps()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("companion.alarm")
    }

    private func save(enabled: Bool, days: Set<Int>) {
        let hour = store.settings.alarmHour
        let minute = store.settings.alarmMinute
        let weekdays = CompanionWeekday.ordered(days)
        Task {
            await store.saveAlarm(enabled: enabled, hour: hour, minute: minute, weekdays: weekdays)
        }
    }
}

// MARK: - Briefing

struct BriefingCard: View {
    let briefing: MorningBriefing
    let speaker: BriefingSpeaker
    @Binding var doneActions: Set<String>

    var body: some View {
        Card {
            Text(briefing.dayType.title.uppercased())
                .font(Typography.motto)
                .tracking(1)
                .foregroundStyle(Palette.bioCyan)
                .wraps()
            Text(briefing.headline)
                .font(Typography.title)
                .foregroundStyle(Palette.ink)
                .wraps()
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("companion.headline")
            SpeakButton(text: briefing.spokenScript, speaker: speaker)
            ForEach(briefing.sections) { section in
                BriefingSectionRow(section: section)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("companion.briefing")
        QuickActionChecklist(actions: briefing.actions, done: $doneActions)
    }
}

struct BriefingSectionRow: View {
    let section: BriefingSection

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(section.title)
                .font(Typography.label)
                .foregroundStyle(Palette.ink)
                .wraps()
            StatementBadge(kind: CompanionUI.statementKind(section.statement))
            Text(section.text)
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
                .wraps()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}

struct SpeakButton: View {
    let text: String
    let speaker: BriefingSpeaker

    var body: some View {
        Button {
            if speaker.isSpeaking {
                speaker.stop()
            } else {
                speaker.speak(text)
            }
        } label: {
            Label(speaker.isSpeaking ? "Vorlesen beenden" : "Vorlesen",
                  systemImage: speaker.isSpeaking ? "stop.circle" : "speaker.wave.2")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityIdentifier("companion.speak")
    }
}

/// The three "Jetzt tun" steps as a voluntary checklist.
struct QuickActionChecklist: View {
    let actions: [QuickAction]
    @Binding var done: Set<String>

    var body: some View {
        Card {
            CompanionCardTitle(title: "Jetzt tun", systemImage: "checklist")
            StatementBadge(kind: .suggestion)
            ForEach(actions) { action in
                QuickActionRow(action: action, isDone: done.contains(action.id)) {
                    if done.contains(action.id) {
                        done.remove(action.id)
                    } else {
                        done.insert(action.id)
                    }
                }
            }
            Text("Abhaken ist freiwillig. Jeder Schritt dauert höchstens ein paar Minuten.")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("companion.actions")
    }
}

struct QuickActionRow: View {
    let action: QuickAction
    let isDone: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: Spacing.m) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(Typography.title)
                    .foregroundStyle(isDone ? Palette.bioCyan : Palette.inkMuted)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Label(action.title, systemImage: action.symbol)
                        .font(Typography.label)
                        .foregroundStyle(Palette.ink)
                        .strikethrough(isDone, color: Palette.inkMuted)
                        .wraps()
                    Text(action.detail)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .wraps()
                    Text("\(action.minutes) min · Etikett \(action.label.rawValue)")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .wraps()
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isDone ? .isSelected : [])
        .accessibilityHint(isDone ? "Tippen, um den Haken zu entfernen" : "Tippen zum Abhaken")
        .accessibilityIdentifier("companion.action.\(action.id)")
        .sensoryFeedback(.selection, trigger: isDone)
    }
}

// MARK: - Day nudges

struct NudgeListCard: View {
    let nudges: [CompanionNudge]
    let now: Date

    var body: some View {
        Card {
            StatementBadge(kind: .suggestion)
            ForEach(nudges) { nudge in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(CompanionUI.time(nudge.time))
                        .font(Typography.label.monospacedDigit())
                        .foregroundStyle(nudge.time < now ? Palette.inkMuted : Palette.bioCyan)
                    Label(nudge.title, systemImage: nudge.kind.symbol)
                        .font(Typography.label)
                        .foregroundStyle(Palette.ink)
                        .wraps()
                    Text(nudge.body)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .wraps()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            Text("Die Hinweise kommen als Mitteilung, vorab geplant. Auf dem Sperrbildschirm stehen keine Gesundheitswerte.")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("companion.nudges")
    }
}

// MARK: - Forecast

struct ForecastLabCard: View {
    let next: MorningForecast?
    let outcome: ForecastOutcome?
    let hitRate: Double?

    var body: some View {
        Card {
            CompanionCardTitle(title: "Morgen-Tipp (experimentell)", systemImage: "scope")
            EvidenceTag(label: .c)
            if let next {
                Text("Für die Nacht auf \(Self.weekday(next.targetDay)): Ruhepuls nachts etwa \(Int(next.restingHeartRateLow.rounded())) bis \(Int(next.restingHeartRateHigh.rounded())) bpm.")
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                    .wraps()
                if let tendency = next.hrvTendency {
                    Text(Self.hrvText(tendency))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.ink)
                        .wraps()
                }
                Text("Geschätzt aus \(next.trainingDays) Tagen deiner eigenen Werte.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
            } else {
                Text("Noch kein Tipp: Dafür braucht es mindestens 14 Nächte mit Ringdaten.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
            }
            if let outcome {
                StatementBadge(kind: .computed)
                Text(outcome.sentence)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.ink)
                    .wraps()
            }
            Text(hitRate.map { "Trefferquote bisher: \(CompanionUI.percentText($0))" }
                 ?? "Noch keine Trefferquote: Sie erscheint, sobald Tipps mit gemessenen Nächten verglichen wurden.")
                .font(Typography.caption.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .wraps()
            Text("Ein Tipp ist eine Schätzung aus deinem Verlauf, keine Aussage über deine Gesundheit.")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("companion.forecast")
    }

    private static func weekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "de_DE")))
    }

    private static func hrvText(_ tendency: Int) -> String {
        if tendency < 0 { return "HRV eher unter deinem üblichen Wert." }
        if tendency > 0 { return "HRV eher über deinem üblichen Wert." }
        return "HRV etwa bei deinem üblichen Wert."
    }
}

struct BodyPaceCard: View {
    let result: BodyPaceResult

    var body: some View {
        Card {
            CompanionCardTitle(title: "Körper-Tempo (experimentell)", systemImage: "gauge.with.dots.needle.33percent")
            EvidenceTag(label: result.label)
            Text(result.sentence)
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
                .wraps()
            ForEach(result.components, id: \.name) { component in
                Text("\(component.name): \(Self.years(component.years)) Jahre · \(component.detail)")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
            }
            Text("Etikett C heißt: wackelig, eine grobe Annäherung aus deinem 4-Wochen-Trend von Ruhepuls, Schritten und Schlaf. Die Gewichte sind nicht wissenschaftlich geprüft. Keine medizinische Aussage.")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("companion.bodyPace")
    }

    private static func years(_ value: Double) -> String {
        let text = value.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "de_DE")))
        return value > 0 ? "+" + text : text
    }
}
