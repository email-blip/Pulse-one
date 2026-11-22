import PulseCore
import SwiftData
import SwiftUI

/// A change the person picked, shown before/after until it is confirmed (spec §6.4).
struct CoachProposal: Identifiable {
    let id = UUID()
    let intent: CoachIntent
    let before: PlannedSession
    let after: PlannedSession
    let reason: String
}

/// Root of the Coach tab (Welle 3): today's plan from load and recovery, adjustments, evening review,
/// the 4-week program and the training load. Rule based and fully local; no Claude call here.
struct CoachScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SourcesStore.self) private var sources
    @State private var snapshot: CoachSnapshot?
    @State private var loaded = false
    @State private var showSetup = false
    @State private var showReview = false
    @State private var proposal: CoachProposal?
    @State private var refresh = 0

    private var now: Date { LaunchOptions.current.usesTestScenario ? TestScenario.fixedTime : .now }
    private var repository: CoachRepository { CoachRepository(context: modelContext) }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.l) {
                        if LaunchOptions.current.usesTestScenario { TestBanner() }
                        if let snapshot {
                            content(snapshot)
                        } else if loaded {
                            EmptyState(title: "Coach einrichten",
                                       message: "Sag dem Coach, was du gern machst und wie viel Zeit du hast. Ohne Sportart plant er Alltagsbewegung, Beweglichkeit und Erholung.",
                                       systemImage: "figure.run", actionTitle: "Jetzt einrichten") { showSetup = true }
                                .accessibilityIdentifier("coach.setup")
                        }
                        Text("Der Coach gibt allgemeine Bewegungsvorschläge aus deinen eigenen Werten. Er stellt keine Diagnosen und ersetzt keine ärztliche Beratung.")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkMuted)
                            .wraps()
                    }
                    .padding(.horizontal, Spacing.l)
                    .padding(.bottom, Spacing.xl)
                }
            }
            .navigationTitle("Coach")
            .profileToolbar()
            .task(id: "\(refresh)|\(sources.syncing.count)") { reload() }
            .sheet(isPresented: $showSetup) {
                CoachSetupView(initial: snapshot?.preferences ?? CoachPreferences()) { preferences in
                    repository.save(preferences: preferences, now: now)
                    refresh += 1
                }
                .preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showReview) {
                DayCloseoutSheet(day: now, profileID: sources.ownerProfileID) { refresh += 1 }
                .preferredColorScheme(.dark)
            }
            .sheet(item: $proposal) { proposal in
                ProposalSheet(proposal: proposal) {
                    repository.save(revision: PlanRevision(day: now, intent: proposal.intent, before: proposal.before,
                                                           after: proposal.after, reason: proposal.reason, createdAt: .now))
                    refresh += 1
                }
                .preferredColorScheme(.dark)
                .presentationDetents([.medium, .large])
            }
        }
        .screenIdentifier("coach")
    }

    private func reload() {
        snapshot = repository.snapshot(now: now, profileID: sources.ownerProfileID)
        loaded = true
    }

    @ViewBuilder
    private func content(_ s: CoachSnapshot) -> some View {
        decisionCard(s.plan)
        SectionHeader(title: "Dein Tag")
        ForEach(s.plan.blocks) { block in
            CoachBlockCard(block: block)
        }
        // On rest days set by the rules (feeling sick, alarm signs) changes are not applied, so none are offered.
        if s.plan.decision != .rest, s.plan.decision != .seekHelp {
            adjustCard(s)
        }
        reviewCard(s)
        SectionHeader(title: "Erholungssignale")
        signalsCard(s.plan.signals)
        SectionHeader(title: "Dein Programm")
        CoachWeekCard(program: s.program, position: s.position, now: now)
        loadCard(s.load)
        Button { showSetup = true } label: { Label("Coach anpassen", systemImage: "slider.horizontal.3") }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("coach.settings")
    }

    private func decisionCard(_ plan: DailyPlan) -> some View {
        Card {
            HStack {
                StatementBadge(kind: plan.decision == .seekHelp ? .medicalCheck : .suggestion)
                Spacer()
            }
            Text(plan.decision.title)
                .font(Typography.title)
                .foregroundStyle(Palette.ink)
                .wraps()
            Text(plan.decision.explanation)
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
            ForEach(plan.notes, id: \.self) { note in
                Label(note, systemImage: "info.circle")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.ink)
                    .wraps()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coach.decision")
    }

    private func adjustCard(_ s: CoachSnapshot) -> some View {
        let session = s.plan.suggested
        let others = Sport.allCases.filter { $0 != session.sport && (!$0.isOptionalModule || s.preferences.sports.contains($0)) }
        return Card {
            Label("Plan anpassen", systemImage: "arrow.triangle.2.circlepath")
                .font(Typography.label)
                .foregroundStyle(Palette.bioCyan)
                .wraps()
            Text("Jede Änderung siehst du vorher und nachher. Gespeichert wird erst, wenn du sie übernimmst. Deine Grenzen gelten immer.")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
            Button("Heute nur 15 Minuten") { propose(.timeLimit(minutes: 15), s) }
                .buttonStyle(SecondaryButtonStyle())
            Button("Leichter") { propose(.easier, s) }
                .buttonStyle(SecondaryButtonStyle())
            Button("Etwas mehr") { propose(.harder, s) }
                .buttonStyle(SecondaryButtonStyle())
            Menu {
                ForEach(others) { sport in
                    Button(sport.title) { propose(.swapActivity(sport), s) }
                }
            } label: {
                Text("Lieber etwas anderes").frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            Menu {
                ForEach(BodyRegion.allCases) { region in
                    Menu(region.title) {
                        Button("leicht bis mittel") { propose(.soreness(region: region, level: 4), s) }
                        Button("stark") { propose(.soreness(region: region, level: 8), s) }
                    }
                }
            } label: {
                Text("Ich habe Muskelkater").frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            Button("Heute aussetzen") { propose(.skipToday, s) }
                .buttonStyle(SecondaryButtonStyle())
        }
        .accessibilityIdentifier("coach.adjust")
    }

    private func propose(_ intent: CoachIntent, _ s: CoachSnapshot) {
        let (after, reason) = PlanAdjuster.apply(intent, to: s.plan.suggested, preferences: s.preferences, decision: s.plan.decision,
                                                 neighbourIsHard: s.program.neighbourIsHard(of: s.plan.day, calendar: .current))
        proposal = CoachProposal(intent: intent, before: s.plan.suggested, after: after, reason: reason)
    }

    private func reviewCard(_ s: CoachSnapshot) -> some View {
        Card {
            Label("Tagesabschluss", systemImage: DayBlockKind.eveningReview.symbol)
                .font(Typography.label)
                .foregroundStyle(Palette.neuralViolet)
                .wraps()
            if let review = s.todayReview {
                Text(DayCloseout.movementText(review))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.ink)
                    .wraps()
            } else {
                Text("Noch kein Tagesabschluss für heute. Zwei Minuten am Abend reichen; daraus plant der Coach morgen. Du findest ihn auch auf „Heute“.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
            }
            Button(s.todayReview == nil ? "Tag abschließen" : "Tagesabschluss ändern") { showReview = true }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("coach.review")
        }
    }

    private func signalsCard(_ signals: [RecoverySignal]) -> some View {
        Card {
            HStack {
                StatementBadge(kind: .computed)
                Spacer()
            }
            ForEach(signals) { signal in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Label(signal.kind.title + " · " + stateText(signal.state), systemImage: stateSymbol(signal.state))
                        .font(Typography.label)
                        .foregroundStyle(signal.state == .notable ? Palette.neuralViolet : Palette.ink)
                        .wraps()
                    Text(signal.text)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .wraps()
                }
                .accessibilityElement(children: .combine)
            }
            Text("Der Coach vergleicht mit deinen eigenen Werten der 30 Tage davor (mindestens 15 Tage) und passt nur an, wenn ein Wert deutlich außerhalb deines üblichen Bereichs liegt. Kein Gesamtwert.")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
        }
        .accessibilityIdentifier("coach.signals")
    }

    private func stateText(_ state: SignalState) -> String {
        switch state {
        case .notable: "deutlich außerhalb des üblichen Bereichs"
        case .usual: "unauffällig"
        case .unknown: "noch unbekannt"
        }
    }

    private func stateSymbol(_ state: SignalState) -> String {
        switch state {
        case .notable: "arrow.up.and.down.circle"
        case .usual: "circle"
        case .unknown: "questionmark.circle"
        }
    }

    private func loadCard(_ load: LoadSummary) -> some View {
        Card {
            HStack {
                Label("Belastung", systemImage: "chart.bar")
                    .font(Typography.label)
                    .foregroundStyle(Palette.bioCyan)
                Spacer()
                StatementBadge(kind: .computed)
            }
            Text("Letzte 7 Tage: \(Int(load.weekLoad)) (Minuten × Anstrengung)")
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
                .wraps()
            Text(load.fourWeekMean.map { "Mittel der 4 Wochen davor: \(Int($0))" } ?? "Noch kein Vergleich: Abendrückblicke der letzten Wochen fehlen.")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
            if load.missingRPE > 0 {
                Text("\(load.missingRPE) Einheit(en) ohne Angabe der Anstrengung; sie fehlen in der Summe.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One building block of the day.
struct CoachBlockCard: View {
    let block: DayBlock

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Label(block.title, systemImage: block.kind.symbol)
                    .font(Typography.label)
                    .foregroundStyle(block.kind == .mainWorkout ? Palette.pulseCoral : Palette.bioCyan)
                    .wraps()
                Spacer()
                if block.minutes > 0 {
                    Text("\(block.minutes) min")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                }
            }
            Text(block.detail)
                .font(Typography.caption)
                .foregroundStyle(Palette.ink)
                .wraps()
            if let reason = block.reason {
                Label(reason, systemImage: "info.circle")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
            }
            if !block.exercises.isEmpty {
                NavigationLink {
                    ExerciseListView(title: block.title, exercises: block.exercises)
                } label: {
                    Label(block.exercises.count == 1 ? "1 Übung ansehen" : "\(block.exercises.count) Übungen ansehen", systemImage: "list.bullet")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .accessibilityIdentifier("coach.block.\(block.id)")
    }
}

/// The current week of the program, day by day.
struct CoachWeekCard: View {
    let program: TrainingProgram
    let position: (week: Int, day: Int)?
    let now: Date

    var body: some View {
        let weekIndex = position?.week ?? 0
        let week = program.weeks[min(weekIndex, program.weeks.count - 1)]
        let calendar = Calendar.current
        let weekStart = calendar.date(byAdding: .day, value: 7 * week.index, to: program.start) ?? program.start
        return Card {
            Text("Woche \(week.index + 1) von \(program.weeks.count)" + (week.isLighter ? " · Entlastungswoche" : " · Aufbau"))
                .font(Typography.label)
                .foregroundStyle(Palette.bioCyan)
                .wraps()
            ForEach(Array(week.days.enumerated()), id: \.offset) { offset, session in
                let date = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
                HStack(alignment: .firstTextBaseline) {
                    Text(date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "de_DE"))))
                        .font(Typography.caption.weight(position?.day == offset ? .bold : .regular))
                        .foregroundStyle(position?.day == offset ? Palette.ink : Palette.inkMuted)
                        .frame(minWidth: 32, alignment: .leading)
                    Text(session.kind == .rest ? session.title : "\(session.title) · \(session.minutes) min · \(session.intensity.title)")
                        .font(Typography.caption)
                        .foregroundStyle(session.kind == .rest ? Palette.inkMuted : Palette.ink)
                        .wraps()
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
            Text("3 Wochen Aufbau, dann 1 leichtere Woche. Die Wochenlast steigt höchstens um 10 % (Einsteiger 5 %), mindestens ein Ruhetag, nie zwei harte Tage hintereinander.")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
        }
        .accessibilityIdentifier("coach.week")
    }
}

/// Exercises of one block with steps, dose and safety notes.
struct ExerciseListView: View {
    let title: String
    let exercises: [Exercise]

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    ForEach(exercises) { e in
                        Card {
                            HStack(alignment: .firstTextBaseline) {
                                Text(e.name).font(Typography.label).foregroundStyle(Palette.ink).wraps()
                                Spacer()
                                Text(e.dose).font(Typography.caption).foregroundStyle(Palette.bioCyan)
                            }
                            ForEach(Array(e.steps.enumerated()), id: \.offset) { i, step in
                                Text("\(i + 1). \(step)").font(Typography.caption).foregroundStyle(Palette.ink).wraps()
                            }
                            if let easier = e.easier {
                                Text("Leichter: \(easier)").font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                            }
                            if let harder = e.harder {
                                Text("Schwerer: \(harder)").font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                            }
                            Label(e.safety, systemImage: "hand.raised").font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                            Text("Quelle: \(e.origin)").font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                        }
                    }
                }
                .padding(Spacing.l)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Before/after of one change; saved only on "Übernehmen".
struct ProposalSheet: View {
    let proposal: CoachProposal
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    Text(proposal.intent.title)
                        .font(Typography.title)
                        .foregroundStyle(Palette.ink)
                        .wraps()
                    StatementBadge(kind: .suggestion)
                    row("Vorher", proposal.before)
                    row("Nachher", proposal.after)
                    Text(proposal.reason)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.ink)
                        .wraps()
                    Button("Übernehmen") { onConfirm(); dismiss() }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("coach.confirm")
                    Button("Abbrechen") { dismiss() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .padding(Spacing.l)
            }
        }
    }

    private func row(_ label: String, _ s: PlannedSession) -> some View {
        Card {
            Text(label).font(Typography.motto).foregroundStyle(Palette.inkMuted)
            Text(s.kind == .rest ? s.title : "\(s.title) · \(s.minutes) min · \(s.intensity.title)")
                .font(Typography.label)
                .foregroundStyle(Palette.ink)
                .wraps()
        }
        .accessibilityElement(children: .combine)
    }
}
