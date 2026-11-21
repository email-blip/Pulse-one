import PulseCore
import SwiftUI

/// Coach setup (spec §2). Every field is optional and can be changed later; nothing is preselected
/// as a sport (SPORT-UND-ALLTAG §1). Health questions are our own wording, not the PAR-Q+ text.
struct CoachSetupView: View {
    let onSave: (CoachPreferences) -> Void
    @State private var p: CoachPreferences
    @State private var showMoreModules: Bool
    @State private var answers: [Bool]
    @Environment(\.dismiss) private var dismiss

    static let healthQuestions = [
        "Hat dir eine Ärztin oder ein Arzt gesagt, dass du nur eingeschränkt Sport treiben sollst?",
        "Hast du bei Belastung Schmerzen oder Druck in der Brust?",
        "Wird dir bei Belastung schwindelig, oder bist du schon einmal ohnmächtig geworden?",
        "Hast du eine Herz-, Kreislauf- oder Lungenerkrankung, die beim Training beachtet werden muss?"
    ]

    init(initial: CoachPreferences, onSave: @escaping (CoachPreferences) -> Void) {
        self.onSave = onSave
        _p = State(initialValue: initial)
        _showMoreModules = State(initialValue: initial.sports.contains { $0.isOptionalModule })
        _answers = State(initialValue: Array(repeating: initial.needsMedicalClearance, count: Self.healthQuestions.count))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Sport.allCases.filter { !$0.isOptionalModule || showMoreModules }) { sport in
                        Toggle(isOn: binding(for: sport)) { Label(sport.title, systemImage: sport.symbol) }
                    }
                    Toggle("Weitere Module zeigen (z. B. Reiten)", isOn: $showMoreModules)
                } header: {
                    Text("Was machst du gern?")
                } footer: {
                    Text("Ohne Auswahl plant der Coach Alltagsbewegung, Beweglichkeit und Erholung.")
                }
                Section("Zeit") {
                    Stepper("Trainingstage pro Woche: \(p.trainingDaysPerWeek)", value: $p.trainingDaysPerWeek, in: 0...6)
                    Stepper("Höchstens \(p.minutesPerSession) Minuten pro Einheit", value: $p.minutesPerSession, in: 10...120, step: 5)
                }
                Section("Niveau und Ton") {
                    Picker("Fitnessniveau", selection: $p.level) {
                        ForEach(FitnessLevel.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Coaching", selection: $p.style) {
                        ForEach(CoachingStyle.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section("Ausrüstung") {
                    ForEach(Equipment.allCases) { item in
                        Toggle(item.title, isOn: setBinding(\.equipment, item))
                    }
                }
                Section {
                    ForEach(BodyRegion.allCases) { region in
                        Toggle(region.title, isOn: setBinding(\.limitations, region))
                    }
                } header: {
                    Text("Einschränkungen")
                } footer: {
                    Text("Übungen, die diese Bereiche belasten, plant der Coach nicht ein.")
                }
                Section("Bausteine deines Tages") {
                    ForEach(DayBlockKind.allCases) { kind in
                        Toggle(isOn: setBinding(\.enabledBlocks, kind)) { Label(kind.title, systemImage: kind.symbol) }
                    }
                }
                Section {
                    ForEach(Self.healthQuestions.indices, id: \.self) { i in
                        Toggle(isOn: $answers[i]) { Text(Self.healthQuestions[i]) }
                    }
                } header: {
                    Text("Gesundheitsfragen")
                } footer: {
                    Text(answers.contains(true)
                         ? "Bitte sprich vor intensivem Training mit deiner Ärztin oder deinem Arzt. Bis dahin plant der Coach nur leichte Einheiten."
                         : "Wenn du eine Frage mit Ja beantwortest, plant der Coach nur leichte Einheiten.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(ScreenBackground())
            .navigationTitle("Coach einrichten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        var result = p
                        result.needsMedicalClearance = answers.contains(true)
                        if !showMoreModules { result.sports.removeAll { $0.isOptionalModule } }
                        onSave(result.sanitized)
                        dismiss()
                    }
                    .accessibilityIdentifier("coach.save")
                }
            }
        }
    }

    private func binding(for sport: Sport) -> Binding<Bool> {
        Binding(get: { p.sports.contains(sport) },
                set: { on in
                    if on { if !p.sports.contains(sport) { p.sports.append(sport) } } else { p.sports.removeAll { $0 == sport } }
                })
    }

    private func setBinding<T: Hashable>(_ path: WritableKeyPath<CoachPreferences, Set<T>>, _ item: T) -> Binding<Bool> {
        Binding(get: { p[keyPath: path].contains(item) },
                set: { on in
                    if on { p[keyPath: path].insert(item) } else { p[keyPath: path].remove(item) }
                })
    }
}

/// Evening review (spec §3): done?, effort CR-10, mood, soreness, pain, how you feel.
struct EveningReviewSheet: View {
    let day: Date
    let planned: PlannedSession?
    let onSave: (EveningReview) -> Void
    @State private var r: EveningReview
    @State private var hasRPE: Bool
    @Environment(\.dismiss) private var dismiss

    init(day: Date, existing: EveningReview?, planned: PlannedSession?, onSave: @escaping (EveningReview) -> Void) {
        self.day = day
        self.planned = planned
        self.onSave = onSave
        let start = Calendar.current.startOfDay(for: day)
        let fallback = EveningReview(day: start, completed: planned.map { $0.kind != .rest } ?? false, sport: planned?.sport,
                                     minutes: planned.map { $0.kind == .rest ? 0 : $0.minutes }, rpe: nil,
                                     plannedIntensity: planned.flatMap { session -> Intensity? in session.kind == .rest ? nil : session.intensity })
        _r = State(initialValue: existing ?? fallback)
        _hasRPE = State(initialValue: existing?.rpe != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Bewegung heute") {
                    Toggle("Einheit erledigt", isOn: $r.completed)
                    if r.completed {
                        Stepper("Dauer: \(r.minutes ?? 0) min", value: minutes, in: 0...300, step: 5)
                        Toggle("Anstrengung angeben", isOn: $hasRPE)
                        if hasRPE {
                            Stepper("Anstrengung: \(r.rpe ?? 5) von 10", value: rpe, in: 0...10)
                            Text(rpeHint(r.rpe ?? 5)).font(.footnote).foregroundStyle(Palette.inkMuted)
                        }
                    }
                }
                Section("Wie geht es dir?") {
                    Picker("Stimmung", selection: mood) {
                        Text("keine Angabe").tag(0)
                        ForEach(1...5, id: \.self) { Text("\($0) von 5").tag($0) }
                    }
                    Stepper("Muskelkater: \(r.check.soreness ?? 0) von 10", value: soreness, in: 0...10)
                    Toggle("Ich fühle mich krank", isOn: $r.check.feelsSick)
                    Toggle("Brustschmerz, Atemnot, Schwindel oder Ohnmacht bei Belastung", isOn: $r.check.alarmSymptoms)
                    if r.check.alarmSymptoms {
                        Text("Bitte lass das ärztlich abklären. Bei akuten Beschwerden sofort den Notruf 112 wählen.")
                            .font(.footnote.weight(.semibold))
                    }
                }
                Section("Schmerzen") {
                    ForEach(BodyRegion.allCases) { region in
                        Toggle(region.title, isOn: painBinding(region))
                    }
                }
                Section("Notiz") {
                    TextField("z. B. schlecht geschlafen, Knie gemerkt", text: $r.note, axis: .vertical)
                }
            }
            .scrollContentBackground(.hidden)
            .background(ScreenBackground())
            .navigationTitle("Abendrückblick")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        var result = r
                        if !hasRPE || !result.completed {
                            result.rpe = nil
                        } else if result.rpe == nil {
                            // The stepper shows 5 until touched; saving keeps what the person saw.
                            result.rpe = 5
                        }
                        onSave(result)
                        dismiss()
                    }
                    .accessibilityIdentifier("coach.review.save")
                }
            }
        }
    }

    private var minutes: Binding<Int> { Binding(get: { r.minutes ?? 0 }, set: { r.minutes = $0 }) }
    private var rpe: Binding<Int> { Binding(get: { r.rpe ?? 5 }, set: { r.rpe = $0 }) }
    private var mood: Binding<Int> { Binding(get: { r.mood ?? 0 }, set: { r.mood = $0 == 0 ? nil : $0 }) }
    private var soreness: Binding<Int> { Binding(get: { r.check.soreness ?? 0 }, set: { r.check.soreness = $0 }) }

    private func painBinding(_ region: BodyRegion) -> Binding<Bool> {
        Binding(get: { r.check.painRegions.contains(region) },
                set: { on in if on { r.check.painRegions.insert(region) } else { r.check.painRegions.remove(region) } })
    }

    private func rpeHint(_ value: Int) -> String {
        switch value {
        case 0...2: "sehr leicht, mühelos unterhalten"
        case 3...4: "leicht, Unterhaltung geht gut"
        case 5...6: "mittel, nur kurze Sätze"
        case 7...8: "schwer, nur einzelne Worte"
        default: "maximal"
        }
    }
}
