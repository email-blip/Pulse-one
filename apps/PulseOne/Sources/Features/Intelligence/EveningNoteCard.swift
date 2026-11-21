import PulseCore
import SwiftData
import SwiftUI

/// Evening note on TODAY (creative lab idea 4): a sentence by text or keyboard dictation, turned into
/// tags the user confirms. The free text stays on the iPhone; only confirmed tags may go into analyses.
struct EveningNoteCard: View {
    @Query(sort: \StoredNote.date, order: .reverse) private var notes: [StoredNote]
    @State private var editing = false

    private var now: Date { IntelligenceServices.shared.now }

    private var todaysNote: StoredNote? {
        notes.first { Calendar.current.isDate($0.date, inSameDayAs: now) }
    }

    var body: some View {
        Card {
            SectionHeader(title: "Abend-Notiz")
            if let note = todaysNote {
                let event = note.event
                Text(event.tagLabel).font(Typography.body).foregroundStyle(Palette.ink).wraps()
                Button("Notiz ändern") { editing = true }
                    .buttonStyle(SecondaryButtonStyle())
            } else {
                Text("Wie war dein Tag? Ein Satz genügt, getippt oder diktiert. Daraus werden Stichworte, die du bestätigst.")
                    .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                Button("Notiz schreiben") { editing = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("eveningNote.open")
            }
        }
        .sheet(isPresented: $editing) { NoteEditor(existing: todaysNote, date: now) }
    }
}

struct NoteEditor: View {
    let existing: StoredNote?
    let date: Date
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var tags: Set<ContextTag> = []
    @State private var mood: Int?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(spacing: Spacing.l) {
                        Card {
                            Text("Zum Diktieren tippe auf das Mikrofon der Tastatur.")
                                .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                            TextField("Zum Beispiel: Stressiger Tag, spät gegessen, zwei Kaffee.", text: $text, axis: .vertical)
                                .font(Typography.body)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(3...8)
                                .padding(Spacing.m)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.surfaceButton))
                                .accessibilityIdentifier("eveningNote.text")
                                .onChange(of: text) { _, newValue in suggest(from: newValue) }
                        }
                        Card {
                            SectionHeader(title: "Stichworte")
                            Text("Tippe an, was stimmt. Nur diese Stichworte können in Analysen einfließen, nie dein Text.")
                                .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                            ForEach(ContextTag.allCases, id: \.self) { tag in
                                Button {
                                    if tags.contains(tag) { tags.remove(tag) } else { tags.insert(tag) }
                                } label: {
                                    HStack(spacing: Spacing.m) {
                                        Image(systemName: tags.contains(tag) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(Palette.bioCyan)
                                        Label(tag.title, systemImage: tag.symbol)
                                            .font(Typography.body).foregroundStyle(Palette.ink).wraps()
                                        Spacer()
                                    }
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(tag.title)
                                .accessibilityAddTraits(tags.contains(tag) ? .isSelected : [])
                                .accessibilityIdentifier("eveningNote.tag.\(tag.rawValue)")
                            }
                        }
                        Card {
                            SectionHeader(title: "Stimmung")
                            HStack(spacing: Spacing.s) {
                                ForEach(1...5, id: \.self) { value in
                                    Button("\(value)") { mood = mood == value ? nil : value }
                                        .font(Typography.label)
                                        .foregroundStyle(mood == value ? Palette.obsidian : Palette.ink)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .background(Capsule().fill(mood == value ? Palette.bioCyan : Palette.surfaceButton))
                                        .accessibilityLabel("Stimmung \(value) von 5")
                                        .accessibilityAddTraits(mood == value ? .isSelected : [])
                                }
                            }
                            Text("1 = sehr schlecht, 5 = sehr gut").font(Typography.caption).foregroundStyle(Palette.inkMuted)
                        }
                        Button("Speichern") { save() }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && tags.isEmpty && mood == nil)
                    }
                    .padding(Spacing.l)
                }
            }
            .navigationTitle("Abend-Notiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let existing {
            let event = existing.event
            text = event.text
            tags = Set(event.tags)
            mood = event.mood
        }
    }

    /// Suggestions only add; what the user switched off stays off until the text changes it again.
    private func suggest(from text: String) {
        let parsed = EveningNoteParser.parse(text)
        tags.formUnion(parsed.tags)
        if mood == nil, let suggested = parsed.mood { mood = suggested }
    }

    private func save() {
        let ordered = ContextTag.allCases.filter { tags.contains($0) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing {
            existing.text = trimmed
            existing.tagsRaw = ordered.map(\.rawValue).joined(separator: ",")
            existing.mood = mood
        } else {
            modelContext.insert(StoredNote(ContextEvent(date: date, tags: ordered, mood: mood, text: trimmed)))
        }
        try? modelContext.save()
        dismiss()
    }
}
