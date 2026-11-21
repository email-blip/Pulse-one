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
    @State private var engine = IntelligenceEngine()
    @State private var path: [IntelligenceRoute] = []
    @State private var pending: PendingSend?
    @State private var daily: OnDeviceBrain.Lines?
    @State private var question = ""
    @State private var localAnswer: String?
    @State private var caseCount = 0
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
            .navigationTitle("Analyse")
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

    private var dailyCard: some View {
        Card {
            SectionHeader(title: "Heute in Kürze")
            ForEach(daily?.lines ?? [], id: \.self) { line in
                Text(line).font(Typography.body).foregroundStyle(Palette.ink).wraps()
            }
            Text(daily?.rephrased == true ? "Formuliert von Apple Intelligence auf deinem iPhone, nichts wurde gesendet."
                    : "Berechnet auf deinem iPhone, nichts wurde gesendet.")
                .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
        }
        .accessibilityIdentifier("intelligence.daily")
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
                 ? "Claude deutet deine Werte wie Internist, Sportmediziner und Coach: Einschätzung, mögliche Diagnosen mit Wahrscheinlichkeit, Abklärung und Plan. Mit Rückfragen zu deinem Befinden."
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
            Text("Claude bekommt nur lokal berechnete Kennzahlen, nie Rohdaten. Du siehst vorher genau, was gesendet wird.")
                .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
            ForEach(AnalysisPeriodKind.allCases, id: \.self) { kind in
                Button(kind.title) { prepareReport(kind) }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(engine.activity != nil)
                    .accessibilityIdentifier("intelligence.report.\(kind.rawValue)")
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

    private var labCard: some View {
        Card {
            SectionHeader(title: "Labor")
            row("Körper-Detektiv", detail: caseCount == 0 ? "Gerade keine Abweichung" : "\(caseCount) Abweichung vom üblichen Bereich",
                systemImage: "magnifyingglass", route: .detective)
            row("Experimente", detail: "Selbstversuche planen und auswerten", systemImage: "flask", route: .experiments)
            row("Körperbiografie", detail: "Was sich über Monate bestätigt", systemImage: "book.closed", route: .biography)
            row("Verlauf", detail: "\(analyses.count) Analysen auf diesem iPhone", systemImage: "clock.arrow.circlepath", route: .history)
        }
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
