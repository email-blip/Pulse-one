import PulseCore
import SwiftUI

extension StatementType {
    /// Shared badge kind, so statement types look the same in every tab.
    var badgeKind: StatementKind {
        switch self {
        case .measured: .measured
        case .computed: .computed
        case .observation: .observed
        case .interpretation: .interpretation
        case .recommendation: .suggestion
        }
    }
}

/// What an evidence id points to, in plain words, for the evidence sheet.
struct EvidenceItem: Identifiable, Hashable {
    let id: String
    let title: String
    let lines: [String]

    static func resolve(_ ids: [String], in context: HealthAnalysisContext?) -> [EvidenceItem] {
        guard let context else { return [] }
        return ids.compactMap { id in
            if let fact = context.facts.first(where: { $0.id == id }) {
                var lines = [LocalSentences.describe(fact)]
                lines.append("Zeitraum: \(fact.period) · \(fact.n) Werte · Abdeckung \(Int((fact.coverage * 100).rounded())) %")
                if let b = fact.baseline {
                    lines.append("Dein üblicher Bereich: Median \(FactUnits.text(b.median, unit: fact.unit)) aus \(b.n) Tagen der \(b.windowDays) Tage davor")
                }
                return EvidenceItem(id: id, title: fact.title, lines: lines)
            }
            if let c = context.correlations.first(where: { $0.id == id }) {
                let rho = FactUnits.text(IntelligenceStats.rounded(c.rho, decimals: 2), unit: "")
                var lines = ["\(c.titleA) und \(c.titleB): ρ = \(rho) aus \(c.n) Tagen"]
                if c.lagDays > 0 { lines.append("\(c.titleB) jeweils \(c.lagDays) Tag später betrachtet") }
                if !c.note.isEmpty { lines.append(c.note) }
                lines.append("Ein Zusammenhang in deinen Daten, keine Ursache.")
                return EvidenceItem(id: id, title: "Zusammenhang", lines: lines)
            }
            if let e = context.events.first(where: { $0.id == id }) {
                return EvidenceItem(id: id, title: e.type == "analog_day" ? "Ähnlicher früherer Tag" : "Notiz",
                                    lines: ["\(e.date): \(e.label)"])
            }
            return nil
        }
    }
}

/// One sentence from Claude with its type badge, a note if flagged, and its evidence.
struct StatementRow: View {
    let text: String
    let kind: StatementKind
    var evidence: [EvidenceItem] = []
    var flag: String?
    @State private var showsEvidence = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            StatementBadge(kind: kind)
            Text(text)
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
                .wraps()
            if let flag {
                Label(flag, systemImage: "info.circle")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
            }
            if !evidence.isEmpty {
                Button {
                    showsEvidence = true
                } label: {
                    Label(evidence.count == 1 ? "1 Beleg" : "\(evidence.count) Belege", systemImage: "doc.text.magnifyingglass")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.bioCyan)
                        .frame(minHeight: 44)
                }
                .accessibilityHint("Zeigt die Werte, auf die sich diese Aussage stützt")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showsEvidence) { EvidenceSheet(items: evidence) }
    }
}

struct EvidenceSheet: View {
    let items: [EvidenceItem]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(spacing: Spacing.m) {
                        ForEach(items) { item in
                            Card {
                                Text(item.title).font(Typography.label).foregroundStyle(Palette.ink).wraps()
                                ForEach(item.lines, id: \.self) { line in
                                    Text(line).font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                                }
                            }
                        }
                        Text("Alle Werte wurden auf deinem iPhone berechnet. Claude hat sie nur zitiert.")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkMuted)
                            .wraps()
                    }
                    .padding(Spacing.l)
                }
            }
            .navigationTitle("Belege")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
    }
}

/// "Gläserner Bote" (creative lab idea 1): exactly what goes to Claude, what stays, and what it costs.
/// Nothing is sent before "Senden" is tapped.
struct SendPreviewView: View {
    let preview: SendPreview
    let blocker: String?
    let onSend: @MainActor () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showsPayload = false

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(spacing: Spacing.l) {
                        Card {
                            Text(preview.title).font(Typography.title).foregroundStyle(Palette.ink).wraps()
                            Text("Zeitraum: \(preview.periodText)").font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                            Text("\(preview.factCount) berechnete Fakten an \(preview.model.displayName)")
                                .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                        }
                        Card {
                            SectionHeader(title: "Geht an Claude")
                            if preview.categoriesSent.isEmpty {
                                Text("Keine Kategorie freigegeben.").font(Typography.caption).foregroundStyle(Palette.inkMuted)
                            }
                            ForEach(preview.categoriesSent, id: \.self) { category in
                                Label(category.title, systemImage: "arrow.up.circle")
                                    .font(Typography.caption).foregroundStyle(Palette.ink).wraps()
                            }
                        }
                        Card {
                            SectionHeader(title: "Bleibt auf dem iPhone")
                            ForEach(preview.categoriesWithheld, id: \.self) { category in
                                Label(category.title, systemImage: "lock")
                                    .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                            }
                            ForEach(preview.alwaysWithheld, id: \.self) { item in
                                Label(item, systemImage: "lock")
                                    .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                            }
                        }
                        Card {
                            SectionHeader(title: "Kosten")
                            Text("Geschätzt \(preview.estimate.text), abgerechnet über dein Anthropic-Konto.")
                                .font(Typography.caption).foregroundStyle(Palette.ink).wraps()
                            Text("Diesen Monat noch \(preview.sendsRemaining) Sendungen frei.")
                                .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                        }
                        Button(showsPayload ? "Gesendete Daten ausblenden" : "Gesendete Daten genau ansehen") {
                            showsPayload.toggle()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        if showsPayload {
                            Card {
                                Text(preview.payload)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(Palette.inkMuted)
                                    .textSelection(.enabled)
                                    .wraps()
                            }
                        }
                        if let blocker {
                            Card {
                                Label(blocker, systemImage: "hand.raised")
                                    .font(Typography.caption).foregroundStyle(Palette.ink).wraps()
                            }
                        }
                        Button("Senden") {
                            dismiss()
                            onSend()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(blocker != nil)
                        .opacity(blocker == nil ? 1 : 0.5)
                        .accessibilityIdentifier("intelligence.send")
                    }
                    .padding(Spacing.l)
                }
            }
            .navigationTitle("Vor dem Senden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
        }
    }
}

/// Progress line while Claude works.
struct WorkingCard: View {
    let text: String
    var body: some View {
        Card {
            HStack(spacing: Spacing.m) {
                ProgressView()
                Text(text).font(Typography.caption).foregroundStyle(Palette.ink).wraps()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Failure of a run, in plain words.
struct FailureCard: View {
    let message: String
    var body: some View {
        Card {
            Label(message, systemImage: "exclamationmark.bubble")
                .font(Typography.caption)
                .foregroundStyle(Palette.ink)
                .wraps()
        }
    }
}

/// Check log: what the local validator removed or marked (spec §3 step 5).
struct CheckLogView: View {
    let issues: [ValidationIssue]

    var body: some View {
        if !issues.isEmpty {
            Card {
                SectionHeader(title: "Prüfprotokoll")
                ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("\(issue.severity == .rejected ? "Entfernt" : "Markiert") (\(issue.rule)): \(issue.reason)")
                            .font(Typography.caption).foregroundStyle(Palette.ink).wraps()
                        Text(issue.text).font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                    }
                }
            }
        }
    }
}
