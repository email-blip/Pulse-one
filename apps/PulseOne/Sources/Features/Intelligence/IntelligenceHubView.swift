import PulseCore
import SwiftData
import SwiftUI

/// Where the Analyse tab can go.
enum IntelligenceRoute: Hashable {
    case analysis(StoredAnalysis)
    /// nil starts a new consultation.
    case consultation(StoredConsultation?)
    case detective
    case experiments
    case biography
    case history
    case settings
}

/// A confirmed preview waits here until "Senden" is tapped.
struct PendingSend: Identifiable {
    let id = UUID()
    let preview: SendPreview
    let blocker: String?
    let send: @MainActor () -> Void
}

/// Root of the Analyse tab: the iPhone's short lines first (free, offline), then Claude on request with a
/// visible preview, plus the creative lab tools (detective, experiments, body biography).
struct IntelligenceHubView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SourcesStore.self) private var sources
    @Environment(ProfileStore.self) private var profileStore
    @Environment(CompanionStore.self) private var companion
    @State private var engine = IntelligenceEngine()
    @State private var path: [IntelligenceRoute] = []
    @State private var pending: PendingSend?
    @State private var daily: OnDeviceBrain.Lines?
    @State private var question = ""
    @State private var localAnswer: String?
    @State private var caseCount = 0
    /// Nights with sleep data; reports need 7, the lab tools 28 (core rebuild 2026-11-23).
    @State private var nights = 0
    @Query(sort: \StoredAnalysis.createdAt, order: .reverse) private var analyses: [StoredAnalysis]
    @Query(sort: \StoredConsultation.updatedAt, order: .reverse) private var consultations: [StoredConsultation]

    private var services: IntelligenceServices { engine.services }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(spacing: Spacing.l) {
                        if LaunchOptions.current.usesTestScenario { TestBanner() }
                        if let activity = engine.activity { WorkingCard(text: activity) }
                        dailyCard
                        if !services.hasKey { keyCard }
                        consultationCard
                        reportsCard
                        questionCard
                        labCard
                        if let last = analyses.first { lastRunCard(last) }
                    }
                    .padding(Spacing.l)
                }
            }
            .navigationTitle("Mehr")
            .profileToolbar()
            .navigationDestination(for: IntelligenceRoute.self) { route in
                switch route {
                case .analysis(let analysis): ReportView(analysis: analysis)
                case .consultation(let consultation): ConsultationView(engine: engine, consultation: consultation)
                case .detective: DetectiveView(engine: engine)
                case .experiments: ExperimentsView(engine: engine)
                case .biography: BiographyView(engine: engine)
                case .history: AnalysisHistoryView()
                case .settings: IntelligenceSettingsView()
                }
            }
            .sheet(item: $pending) { item in
                SendPreviewView(preview: item.preview, blocker: item.blocker, onSend: item.send)
            }
            .task { await refresh() }
        }
        .screenIdentifier("intelligence")
    }

    // MARK: Cards

    /// One morning report for the whole app: when the Begleiter has today's report, Analyse shows its lines
    /// instead of computing its own summary (same numbers, same words). Otherwise the iPhone's short lines.
    private var dailyCard: some View {
        Card {
            SectionHeader(title: "Heute in Kürze")
            if let report = morningReport {
                Text(report.headline).font(Typography.label).foregroundStyle(Palette.ink).wraps()
                ForEach(Self.reportLines(report), id: \.self) { line in
                    Text(line).font(Typography.body).foregroundStyle(Palette.ink).wraps()
                }
                Text("Aus dem Morgenbericht des Begleiters, berechnet auf deinem iPhone. Nichts wurde gesendet.")
                    .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
            } else {
                ForEach(daily?.lines ?? [], id: \.self) { line in
                    Text(line).font(Typography.body).foregroundStyle(Palette.ink).wraps()
                }
                Text(daily?.rephrased == true ? "Formuliert von Apple Intelligence auf deinem iPhone, nichts wurde gesendet."
                        : "Berechnet auf deinem iPhone, nichts wurde gesendet.")
                    .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
            }
        }
        .accessibilityIdentifier("intelligence.daily")
    }

    /// Today's Begleiter morning report, nil when there is none for today yet.
    private var morningReport: MorningBriefing? {
        guard let report = companion.today?.briefing ?? companion.latestBriefing,
              Calendar.current.isDate(report.createdAt, inSameDayAs: CompanionUI.now) else { return nil }
        return report
    }

    /// The report's body lines about the body (night, infection pattern, outlook, body pace), at most three.
    static func reportLines(_ report: MorningBriefing) -> [String] {
        let kinds: [BriefingSectionKind] = [.night, .infection, .outlook, .bodyPace]
        let lines = kinds.compactMap { kind in report.sections.first { $0.kind == kind }?.text }
            .filter { !$0.isEmpty }
        return Array(lines.prefix(3))
    }

    private var keyCard: some View {
        EmptyState(title: "Claude verbinden",
                   message: "Für Berichte und Fragen brauchst du deinen eigenen Claude-Schlüssel von Anthropic. Er bleibt im Schlüsselbund dieses iPhones.",
                   systemImage: "key", actionTitle: "Schlüssel eingeben") { path.append(.settings) }
    }

    private var consultationCard: some View {
        Card {
            SectionHeader(title: "Sprechstunde")
            Text(engine.settings.clinicalMode
                 ? "Claude deutet deine Werte wie Internist, Sportmediziner und Coach: Einschätzung, mögliche Diagnosen mit Einordnung (passt gut, teilweise oder kaum), Abklärung und Plan. Mit Rückfragen zu deinem Befinden."
                 : "Ein Gespräch mit Claude über deine Werte. Ärztliche Einschätzungen sind unter KI-Anbieter ausgeschaltet.")
                .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
            Button("Neue Sprechstunde") { path.append(.consultation(nil)) }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!engine.settings.clinicalMode || engine.activity != nil)
                .accessibilityIdentifier("intelligence.consultation.new")
            ForEach(consultations.prefix(3)) { consultation in
                row(consultation.title,
                    detail: consultation.updatedAt.formatted(date: .abbreviated, time: .shortened)
                        + (consultation.urgency == ConsultationUrgency.none ? "" : " · " + consultation.urgency.title),
                    systemImage: "stethoscope", route: .consultation(consultation))
            }
        }
    }

    private var reportsCard: some View {
        Card {
            SectionHeader(title: "Berichte von Claude")
            if nights < Self.reportNights {
                // Too little to say anything worth paying for (owner, 2026-11-23: no KI under 7 days).
                Text("Ein Wochenrückblick lohnt sich ab \(Self.reportNights) Nächten mit Schlafdaten. Bisher: \(nights).")
                    .font(Typography.body).foregroundStyle(Palette.ink).wraps()
            } else {
                Text("Kurz und belegt. Claude bekommt nur lokal berechnete Kennzahlen, nie Rohdaten. Du siehst vorher, was gesendet wird.")
                    .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                // The daily line comes from the morning report; Claude writes the weekly review (and monthly once there is a month).
                ForEach(reportKinds, id: \.self) { kind in
                    Button(kind == .weekly ? "Wochenrückblick" : kind.title) { prepareReport(kind) }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(engine.activity != nil)
                        .accessibilityIdentifier("intelligence.report.\(kind.rawValue)")
                }
            }
        }
    }

    private var questionCard: some View {
        Card {
            SectionHeader(title: "Frag deine Daten")
            TextField("Zum Beispiel: Schlafe ich nach Training schlechter?", text: $question, axis: .vertical)
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
                .lineLimit(1...4)
                .padding(Spacing.m)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.surfaceButton))
                .accessibilityIdentifier("intelligence.question")
            Button("Fragen") { prepareQuestion() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || engine.activity != nil)
            if let localAnswer {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Label("auf dem iPhone beantwortet", systemImage: "iphone")
                        .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                    Text(localAnswer).font(Typography.body).foregroundStyle(Palette.ink).wraps()
                }
            }
        }
    }

    static let reportNights = 7
    static let labNights = 28

    private var reportKinds: [AnalysisPeriodKind] { nights >= Self.labNights ? [.weekly, .monthly] : [.weekly] }

    private var labCard: some View {
        Card {
            SectionHeader(title: "Labor")
            if nights >= Self.labNights { labRows } else {
                // Parked until there are four weeks of ring data: without them these tools only guess.
                Text("Körper-Detektiv, Experimente und Körperbiografie kommen dazu, sobald 4 Wochen Schlafdaten da sind. Bisher: \(nights) Nächte.")
                    .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
            }
            row("Bisherige Analysen", detail: "\(analyses.count) auf diesem iPhone", systemImage: "clock.arrow.circlepath", route: .history)
        }
    }

    @ViewBuilder private var labRows: some View {
        row("Körper-Detektiv", detail: caseCount == 0 ? "Gerade keine Abweichung" : "\(caseCount) Abweichung vom üblichen Bereich",
            systemImage: "magnifyingglass", route: .detective)
        row("Experimente", detail: "Selbstversuche planen und auswerten", systemImage: "flask", route: .experiments)
        row("Körperbiografie", detail: "Was sich über Monate bestätigt", systemImage: "book.closed", route: .biography)
    }

    private func row(_ title: String, detail: String, systemImage: String, route: IntelligenceRoute) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: Spacing.m) {
                Image(systemName: systemImage).foregroundStyle(Palette.bioCyan).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Typography.label).foregroundStyle(Palette.ink).wraps()
                    Text(detail).font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.inkMuted)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func lastRunCard(_ analysis: StoredAnalysis) -> some View {
        NavigationLink(value: IntelligenceRoute.analysis(analysis)) {
            Card {
                SectionHeader(title: "Zuletzt")
                Text(analysis.question.isEmpty ? analysis.title : analysis.question)
                    .font(Typography.label).foregroundStyle(Palette.ink).wraps()
                Text(analysis.failed ? analysis.errorMessage : analysis.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func refresh() async {
        let context = engine.reportContext(.daily, modelContext: modelContext, owner: sources.ownerProfileID,
                                           profile: profileStore.profile)
        let now = LaunchOptions.current.usesTestScenario ? TestScenario.fixedTime : Date.now
        nights = SampleReader(context: modelContext).daily(.sleepDuration, days: 62, profileID: sources.ownerProfileID, now: now).count
        caseCount = engine.detectiveCases(modelContext: modelContext, owner: sources.ownerProfileID).count
        let allowModel = services.settings.useOnDeviceModel && !LaunchOptions.current.isUITesting
        daily = await OnDeviceBrain.summary(context, allowModel: allowModel)
    }

    private func prepareReport(_ kind: AnalysisPeriodKind) {
        let context = engine.reportContext(kind, modelContext: modelContext, owner: sources.ownerProfileID,
                                           profile: profileStore.profile)
        let preview = engine.preview(title: kind.title, context: context, system: IntelligencePrompts.report(engine.settings.safetyMode),
                                     expectedOutputTokens: kind.expectedOutputTokens, modelContext: modelContext)
        pending = PendingSend(preview: preview, blocker: engine.blocker(for: preview, modelContext: modelContext)) {
            Task {
                let record = await engine.runReport(kind, context: context, modelContext: modelContext)
                path.append(.analysis(record))
            }
        }
    }

    private func prepareQuestion() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        localAnswer = nil
        if let answer = engine.localAnswer(to: text, modelContext: modelContext, owner: sources.ownerProfileID,
                                           profile: profileStore.profile) {
            localAnswer = answer
            return
        }
        let empty = QuestionTools.context(facts: [], correlations: [], events: [], consent: services.settings.consent,
                                          now: engine.now)
        let preview = engine.preview(title: "Frage: \(text)", context: empty, system: IntelligencePrompts.question(engine.settings.safetyMode),
                                     expectedOutputTokens: 2_500, modelContext: modelContext)
        pending = PendingSend(preview: preview, blocker: engine.blocker(for: preview, modelContext: modelContext)) {
            Task {
                let record = await engine.ask(text, modelContext: modelContext, owner: sources.ownerProfileID)
                question = ""
                path.append(.analysis(record))
            }
        }
    }
}
