import PulseCore
import SwiftUI

/// Settings of the companion: greeting, tone, sleep need, nudges, place for the weather and the alarm.
/// Changes are kept in a draft and stored on "Sichern".
struct CompanionSettingsView: View {
    let store: CompanionStore
    @Environment(ProfileStore.self) private var profile
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CompanionPreferences
    @State private var alarmEnabled: Bool
    @State private var alarmTime: Date
    @State private var weekdays: Set<Int>
    @State private var query = ""
    @State private var results: [GeoPlace] = []
    @State private var searching = false
    @State private var searched = false
    @State private var saving = false
    @State private var prefilled = false

    init(store: CompanionStore) {
        self.store = store
        _draft = State(initialValue: store.preferences)
        _alarmEnabled = State(initialValue: store.settings.alarmEnabled)
        let time = Calendar.current.date(bySettingHour: store.settings.alarmHour, minute: store.settings.alarmMinute,
                                         second: 0, of: Date.now) ?? Date.now
        _alarmTime = State(initialValue: time)
        _weekdays = State(initialValue: Set(store.settings.weekdays))
    }

    var body: some View {
        Form {
            greetingSection
            daySection
            placeSection
            alarmSection
        }
        .scrollContentBackground(.hidden)
        .background(ScreenBackground())
        .navigationTitle("Begleiter einstellen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") { save() }
                    .disabled(saving)
                    .accessibilityIdentifier("companion.settings.save")
            }
        }
        .onAppear {
            guard !prefilled else { return }
            prefilled = true
            if draft.firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.firstName = profile.profile.displayName
            }
        }
    }

    private var greetingSection: some View {
        Section {
            TextField("Vorname", text: $draft.firstName)
                .textContentType(.givenName)
                .accessibilityIdentifier("companion.settings.firstName")
            Picker("Tonfall", selection: $draft.tone) {
                ForEach(CompanionPreferences.Tone.allCases, id: \.self) { tone in
                    Text(tone.title).tag(tone)
                }
            }
            Toggle("Morgenbericht vorlesen", isOn: $draft.speaksBriefing)
        } header: {
            Text("Begrüßung")
        } footer: {
            Text("Die Stimme ist die deutsche Sprachausgabe des iPhones und läuft lokal.")
        }
    }

    private var daySection: some View {
        Section {
            Stepper("Schlafbedarf: \(CompanionUI.hoursText(draft.sleepNeedHours))",
                    value: $draft.sleepNeedHours, in: 6...10, step: 0.25)
            Stepper("Höchstens \(draft.maxNudgesPerDay) Hinweise am Tag", value: $draft.maxNudgesPerDay, in: 1...CompanionPreferences.nudgeCap)
            Toggle("Tipps rund um Kaffee", isOn: $draft.allowsCaffeineTips)
            Toggle("Kraft-Schritte (z. B. Liegestütze)", isOn: $draft.allowsStrengthTips)
        } header: {
            Text("Tag")
        } footer: {
            Text("Hinweise kommen als Mitteilung, vorab geplant. Zwischen \(draft.quietStartHour) und \(draft.quietEndHour) Uhr kommt nur die Erinnerung an die Schlafenszeit.")
        }
    }

    private var placeSection: some View {
        Section {
            if let place = store.place {
                LabeledContent("Ort", value: place.name)
                Button("Ort entfernen") { store.clearPlace() }
            }
            TextField("Ort suchen, z. B. München", text: $query)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { search() }
                .accessibilityIdentifier("companion.settings.placeQuery")
            Button(searching ? "Suche läuft …" : "Suchen") { search() }
                .disabled(searching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ForEach(results) { place in
                Button(CompanionUI.placeTitle(place)) { choose(place) }
            }
            if searched && results.isEmpty && !searching {
                Text(store.lastError ?? "Keine Treffer. Versuch es mit einem anderen Ortsnamen.")
                    .foregroundStyle(Palette.inkMuted)
            }
        } header: {
            Text("Ort für das Wetter")
        } footer: {
            Text("Für das Wetter wird nur der Ort auf etwa 1 km gerundet an Open-Meteo gesendet, keine Gesundheitsdaten.")
        }
    }

    private var alarmSection: some View {
        Section {
            Toggle("Wecker an", isOn: $alarmEnabled)
                .accessibilityIdentifier("companion.settings.alarm")
            DatePicker("Weckzeit", selection: $alarmTime, displayedComponents: .hourAndMinute)
            ForEach(CompanionWeekday.all) { day in
                Toggle(day.name, isOn: weekdayBinding(day.number))
            }
        } header: {
            Text("Wecker „Morgenquelle“")
        } footer: {
            Text(store.isAlarmKitAvailable
                 ? "Der Wecker klingelt wie der System-Wecker, auch im Stumm-Modus. Ohne Wochentag klingelt er einmal."
                 : "Auf diesem iPhone kommt der Wecker als Mitteilung mit Ton; Stumm-Modus und Fokus können ihn leise schalten. Ab iOS 26 klingelt er wie ein echter Wecker.")
        }
    }

    private func weekdayBinding(_ number: Int) -> Binding<Bool> {
        Binding(get: { weekdays.contains(number) },
                set: { isOn in
                    if isOn { weekdays.insert(number) } else { weekdays.remove(number) }
                })
    }

    private func search() {
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !searching else { return }
        searching = true
        Task {
            results = await store.searchPlaces(name)
            searched = true
            searching = false
        }
    }

    private func choose(_ place: GeoPlace) {
        store.setPlace(place)
        results = []
        query = ""
        searched = false
    }

    private func save() {
        saving = true
        var preferences = draft
        preferences.firstName = preferences.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        store.preferences = preferences
        let parts = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
        let days = CompanionWeekday.ordered(weekdays)
        let enabled = alarmEnabled
        Task {
            _ = await NudgeScheduler.requestAuthorization()
            await store.saveAlarm(enabled: enabled, hour: parts.hour ?? 7, minute: parts.minute ?? 0, weekdays: days)
            saving = false
            if store.lastError == nil { dismiss() }
        }
    }
}
