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
                    HStack(spacing: DKSpace.xs) {
                        Text("Was machst du gern?")
                        DKInfoButton(title: "Was machst du gern?", text: "Ohne Auswahl plant der Coach Alltagsbewegung, Beweglichkeit und Erholung.",
                                     identifier: "coachSetup.sports.info")
                    }
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
                    HStack(spacing: DKSpace.xs) {
                        Text("Einschränkungen")
                        DKInfoButton(title: "Einschränkungen", text: "Übungen, die diese Bereiche belasten, plant der Coach nicht ein.",
                                     identifier: "coachSetup.limits.info")
                    }
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
