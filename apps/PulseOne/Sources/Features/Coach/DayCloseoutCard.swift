import PulseCore
import SwiftData
import SwiftUI

/// Today's stored closeout: the Coach review and the evening note (both optional).
@MainActor
struct DayCloseoutRecords {
    let review: EveningReview?
    let note: StoredNote?
    let planned: PlannedSession?

    static func load(context: ModelContext, day: Date, profileID: UUID?, calendar: Calendar = .current) -> DayCloseoutRecords {
        // Reads the Coach snapshot only for today's planned session (to prefill the duration).
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let notes = FetchDescriptor<StoredNote>(predicate: #Predicate { $0.date >= start && $0.date < end },
                                                sortBy: [SortDescriptor(\.date, order: .reverse)])
        let repository = CoachRepository(context: context, calendar: calendar)
        let review = repository.reviews(since: start).first { calendar.isDate($0.day, inSameDayAs: start) }
        let planned = repository.snapshot(now: day, profileID: profileID)?.plan.suggested
        return DayCloseoutRecords(review: review, note: (try? context.fetch(notes))?.first, planned: planned)
    }

    /// Cheap check without the Coach snapshot: does today have a review or a note?
    static func isDone(context: ModelContext, day: Date, calendar: Calendar = .current) -> Bool {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let notes = FetchDescriptor<StoredNote>(predicate: #Predicate { $0.date >= start && $0.date < end })
        let reviews = FetchDescriptor<CoachReviewRecord>(predicate: #Predicate { $0.day >= start && $0.day < end })
        return ((try? context.fetchCount(notes)) ?? 0) > 0 || ((try? context.fetchCount(reviews)) ?? 0) > 0
    }
}

/// TODAY's "Tagesabschluss" tile: one evening step for movement, mood, complaints and the note. It replaces the
/// separate Abend-Notiz here and the Abendrückblick in the Coach; both open the same sheet.
struct DayCloseoutCard: View {
    @Environment(SourcesStore.self) private var sources
    // Queries, so the card updates when the closeout is saved from "Jetzt dran" or the Coach tab.
    @Query(sort: \StoredNote.date, order: .reverse) private var notes: [StoredNote]
    @Query(sort: \CoachReviewRecord.day, order: .reverse) private var reviews: [CoachReviewRecord]
    @State private var editing = false

    private var now: Date { CompanionUI.now }

    private var summary: String? {
        let calendar = Calendar.current
        let review = reviews.first { calendar.isDate($0.day, inSameDayAs: now) }?.review
        let note = notes.first { calendar.isDate($0.date, inSameDayAs: now) }?.event
        return DayCloseout.summary(review: review, note: note)
    }

    var body: some View {
        Card {
            SectionHeader(title: "Tagesabschluss")
            if let summary {
                Text(summary).font(Typography.body).foregroundStyle(Palette.ink).wraps()
                Button("Tagesabschluss ändern") { editing = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("eveningNote.open")
            } else {
                Text("Wie war dein Tag? Bewegung, Stimmung und ein Satz, getippt oder diktiert. Daraus plant der Coach morgen.")
                    .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                Button("Tag abschließen") { editing = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("eveningNote.open")
            }
        }
        .sheet(isPresented: $editing) {
            DayCloseoutSheet(day: now, profileID: sources.ownerProfileID)
                .preferredColorScheme(.dark)
        }
    }
}

/// One sheet for the evening: the Coach review (movement, effort, mood, complaints) and the evening note (text and
/// confirmed tags). The mood is asked once and saved in both. The free text stays on the iPhone; only confirmed
/// tags may go into analyses.
struct DayCloseoutSheet: View {
    let day: Date
    let profileID: UUID?
    var onSave: () -> Void = {}
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var review = EveningReview(day: .distantPast, completed: false)
    @State private var effortGiven = false
    @State private var text = ""
    @State private var tags: Set<ContextTag> = []
    @State private var mood: Int?
    @State private var existingNote: StoredNote?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Bewegung heute") {
                    Toggle("Einheit erledigt", isOn: $review.completed)
                    if review.completed {
                        Stepper("Dauer: \(review.minutes ?? 0) min", value: minutes, in: 0...300, step: 5)
                        Toggle("Anstrengung angeben", isOn: $effortGiven)
                        if effortGiven {
                            Stepper("Anstrengung: \(review.rpe ?? 5) von 10", value: rpe, in: 0...10)
                            Text(rpeHint(review.rpe ?? 5)).font(.footnote).foregroundStyle(Palette.inkMuted)
                        }
                    }
                }
                Section {
                    Picker("Stimmung", selection: moodBinding) {
                        Text("–").tag(0)
                        ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("closeout.mood")
                    Stepper("Muskelkater: \(review.check.soreness ?? 0) von 10", value: soreness, in: 0...10)
                    Toggle("Ich fühle mich krank", isOn: $review.check.feelsSick)
                    Toggle("Brustschmerz, Atemnot, Schwindel oder Ohnmacht bei Belastung", isOn: $review.check.alarmSymptoms)
                    if review.check.alarmSymptoms {
                        Text("Bitte lass das ärztlich abklären. Bei akuten Beschwerden sofort den Notruf 112 wählen.")
                            .font(.footnote.weight(.semibold))
                    }
                } header: {
                    Text("Wie geht es dir?")
                } footer: {
                    Text("Stimmung: 1 = sehr schlecht, 5 = sehr gut")
                }
                Section {
                    DisclosureGroup("Schmerzen\(review.check.painRegions.isEmpty ? "" : " (\(review.check.painRegions.count))")") {
                        ForEach(BodyRegion.allCases) { region in
                            Toggle(region.title, isOn: painBinding(region))
                        }
                    }
                }
                Section {
                    TextField("Zum Beispiel: Stressiger Tag, spät gegessen, zwei Kaffee.", text: $text, axis: .vertical)
                        .lineLimit(2...6)
                        .accessibilityIdentifier("eveningNote.text")
                        .onChange(of: text) { _, newValue in suggest(from: newValue) }
                } header: {
                    Text("Ein Satz zum Tag")
                } footer: {
                    Text("Zum Diktieren tippe auf das Mikrofon der Tastatur.")
                }
                Section {
                    ForEach(ContextTag.allCases, id: \.self) { tag in
                        Button {
                            if tags.contains(tag) { tags.remove(tag) } else { tags.insert(tag) }
                        } label: {
                            HStack(spacing: Spacing.m) {
                                Image(systemName: tags.contains(tag) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(Palette.bioCyan)
                                Label(tag.title, systemImage: tag.symbol).foregroundStyle(Palette.ink)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tag.title)
                        .accessibilityAddTraits(tags.contains(tag) ? .isSelected : [])
                        .accessibilityIdentifier("eveningNote.tag.\(tag.rawValue)")
                    }
                } header: {
                    Text("Stichworte")
                } footer: {
                    Text("Tippe an, was stimmt. Nur diese Stichworte können in Analysen einfließen, nie dein Text.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(ScreenBackground())
            .navigationTitle("Tagesabschluss")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .accessibilityIdentifier("closeout.save")
                }
            }
            .onAppear(perform: load)
        }
    }

    private var minutes: Binding<Int> { Binding(get: { review.minutes ?? 0 }, set: { review.minutes = $0 }) }
    private var rpe: Binding<Int> { Binding(get: { review.rpe ?? 5 }, set: { review.rpe = $0 }) }
    private var moodBinding: Binding<Int> { Binding(get: { mood ?? 0 }, set: { mood = $0 == 0 ? nil : $0 }) }
    private var soreness: Binding<Int> { Binding(get: { review.check.soreness ?? 0 }, set: { review.check.soreness = $0 }) }

    private func painBinding(_ region: BodyRegion) -> Binding<Bool> {
        Binding(get: { review.check.painRegions.contains(region) },
                set: { on in if on { review.check.painRegions.insert(region) } else { review.check.painRegions.remove(region) } })
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let records = DayCloseoutRecords.load(context: modelContext, day: day, profileID: profileID)
        review = records.review ?? DayCloseout.startingReview(day: day, planned: records.planned, calendar: .current)
        effortGiven = records.review?.rpe != nil
        existingNote = records.note
        if let event = records.note?.event {
            text = event.text
            tags = Set(event.tags)
        }
        mood = records.note?.mood ?? records.review?.mood
    }

    /// Suggestions only add; what the user switched off stays off until the text changes it again.
    private func suggest(from text: String) {
        let parsed = EveningNoteParser.parse(text)
        tags.formUnion(parsed.tags)
        if mood == nil, let suggested = parsed.mood { mood = suggested }
    }

    private func save() {
        CoachRepository(context: modelContext).save(review: DayCloseout.finalReview(review, effortGiven: effortGiven, mood: mood))
        let ordered = ContextTag.allCases.filter { tags.contains($0) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existingNote {
            existingNote.text = trimmed
            existingNote.tagsRaw = ordered.map(\.rawValue).joined(separator: ",")
            existingNote.mood = mood
        } else if DayCloseout.keepsNote(text: trimmed, tags: ordered, mood: mood) {
            modelContext.insert(StoredNote(ContextEvent(date: day, tags: ordered, mood: mood, text: trimmed)))
        }
        try? modelContext.save()
        onSave()
        dismiss()
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
