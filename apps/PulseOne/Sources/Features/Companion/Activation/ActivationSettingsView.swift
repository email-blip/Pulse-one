import PulseCore
import SwiftUI

/// Settings of the activation: on/off, session lengths, midday/evening times, activity reminders, and the current
/// level per movement family with a reset. Equipment and limitations come from the Coach settings.
/// Changes are kept in a draft and stored on "Sichern" (like the companion settings).
struct ActivationSettingsView: View {
    let store: ActivationStore
    @Environment(\.dismiss) private var dismiss
    /// Seeded once from the store when the screen opens.
    @State private var draft: ActivationSettings
    @State private var middayTime: Date
    @State private var eveningTime: Date
    @State private var saving = false

    init(store: ActivationStore) {
        self.store = store
        let settings = store.settings
        _draft = State(initialValue: settings)
        _middayTime = State(initialValue: Self.date(hour: settings.middayHour, minute: settings.middayMinute))
        _eveningTime = State(initialValue: Self.date(hour: settings.eveningHour, minute: settings.eveningMinute))
    }

    var body: some View {
        Form {
            generalSection
            timesSection
            ActivationLevelsSection(store: store)
            Section {
                Text("Geräte wie eine Klimmzugstange, Einschränkungen und dein Fitness-Stand kommen aus den Coach-Einstellungen. Ohne Stange gibt es Zug-Übungen am Tisch.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
            }
        }
        .scrollContentBackground(.hidden)
        .background(ScreenBackground())
        .navigationTitle("Aktivierung")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") { save() }
                    .disabled(saving)
                    .accessibilityIdentifier("activation.settings.save")
            }
        }
    }

    private var generalSection: some View {
        Section {
            Toggle("Aktivierung an", isOn: $draft.isEnabled)
                .accessibilityIdentifier("activation.settings.enabled")
            Stepper("Morgens \(draft.morningMinutes) Minuten", value: $draft.morningMinutes,
                    in: ActivationSettings.morningRange)
            Toggle("An Bewegung erinnern", isOn: $draft.activityReminders)
        } header: {
            Text("Allgemein")
        } footer: {
            Text("Die Morgen-Einheit startest du nach dem Guten-Morgen-Ablauf. Bei wenig Bewegung erinnert der Begleiter höchstens zweimal am Tag an einen kurzen Snack.")
        }
    }

    private var timesSection: some View {
        Section {
            Toggle("Mittags", isOn: $draft.middayEnabled)
            if draft.middayEnabled {
                DatePicker("Mittags um", selection: $middayTime, displayedComponents: .hourAndMinute)
            }
            Toggle("Abends", isOn: $draft.eveningEnabled)
            if draft.eveningEnabled {
                DatePicker("Abends um", selection: $eveningTime, displayedComponents: .hourAndMinute)
            }
            Stepper("Mittags und abends \(draft.shortMinutes) Minuten", value: $draft.shortMinutes,
                    in: ActivationSettings.shortRange)
        } header: {
            Text("Kurze Einheiten")
        } footer: {
            Text("Zur eingestellten Zeit kommt eine Mitteilung mit der genauen Vorgabe.")
        }
    }

    private static func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: min(max(hour, 0), 23), minute: min(max(minute, 0), 59), second: 0,
                              of: Date.now) ?? Date.now
    }

    private func save() {
        saving = true
        var settings = draft
        let calendar = Calendar.current
        let midday = calendar.dateComponents([.hour, .minute], from: middayTime)
        let evening = calendar.dateComponents([.hour, .minute], from: eveningTime)
        settings.middayHour = midday.hour ?? settings.middayHour
        settings.middayMinute = midday.minute ?? settings.middayMinute
        settings.eveningHour = evening.hour ?? settings.eveningHour
        settings.eveningMinute = evening.minute ?? settings.eveningMinute
        let now = CompanionUI.now
        store.save(settings: settings, now: now)
        Task {
            await store.scheduleReminders(now: now, dayType: store.dayType, infection: store.infectionLevel, wake: nil)
            saving = false
            dismiss()
        }
    }
}

/// Current level per movement family with a reset to the start level.
private struct ActivationLevelsSection: View {
    let store: ActivationStore

    private static let families: [ActivationFamily] = [.push, .pull, .core, .legs, .cardio]

    var body: some View {
        let now = CompanionUI.now
        Section {
            ForEach(Self.families, id: \.self) { family in
                ActivationLevelRow(family: family, level: store.level(family, now: now),
                                   isOwn: store.hasOwnLevel(family),
                                   onReset: { store.resetLevel(family, now: now) })
            }
        } header: {
            Text("Dein Stand")
        } footer: {
            Text("Der Stand steigt, wenn du die Vorgabe schaffst und sie sich passend oder zu leicht anfühlt. Zurücksetzen beginnt wieder bei der Startstufe.")
        }
    }
}

private struct ActivationLevelRow: View {
    let family: ActivationFamily
    let level: ActivationLevel
    let isOwn: Bool
    let onReset: () -> Void

    var body: some View {
        let name = ActivationLibrary.exercise(level.exerciseID)?.name ?? level.exerciseID
        let best = ActivationLibrary.isHold(level.exerciseID) ? "\(level.best) s" : "\(level.best)"
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(Self.title(family))
                .font(Typography.label)
                .foregroundStyle(Palette.ink)
                .wraps()
            Text(isOwn ? "\(name) · bester Satz \(best)" : "\(name) · Startstufe")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
            if isOwn {
                Button("Zurücksetzen", action: onReset)
                    .accessibilityLabel("\(Self.title(family)) zurücksetzen")
                    .accessibilityIdentifier("activation.settings.reset.\(family.rawValue)")
            }
        }
    }

    static func title(_ family: ActivationFamily) -> String {
        switch family {
        case .push: "Liegestütz"
        case .pull: "Zug"
        case .core: "Rumpf"
        case .legs: "Beine"
        case .cardio: "Kreislauf"
        case .mobility: "Beweglichkeit"
        }
    }
}

/// Entry from the companion settings, which have no activation store: creates one for the shared context.
struct ActivationSettingsEntry: View {
    @Environment(\.modelContext) private var modelContext
    @State private var store: ActivationStore?

    var body: some View {
        Group {
            if let store {
                ActivationSettingsView(store: store)
            } else {
                ProgressView()
                    .tint(Palette.bioCyan)
            }
        }
        .task {
            guard store == nil else { return }
            let created = ActivationStore(context: modelContext)
            created.refresh(now: CompanionUI.now, profileID: nil, day: nil)
            store = created
        }
    }
}
