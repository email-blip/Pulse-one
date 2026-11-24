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

/// Root of the Coach tab (rebuild 2026-11-23, team 05): ROOK's lead for today (interpretation → direction →
/// action), "Einheit starten" into the guided session, "Warum?" for the signals, then the day's blocks, the
/// program and the load. Plan logic is the rule-based coach engine; no Claude call here.
struct CoachScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SourcesStore.self) private var sources
    @State private var snapshot: CoachSnapshot?
    @State private var loaded = false
    @State private var showSetup = false
    @State private var showReview = false
    @State private var showWhy = false
    @State private var proposal: CoachProposal?
    @State private var refresh = 0

    private var now: Date { LaunchOptions.current.usesTestScenario ? TestScenario.fixedTime : .now }
    private var repository: CoachRepository { CoachRepository(context: modelContext) }
    private var training: TrainingController { .shared }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.l) {
                        if LaunchOptions.current.usesTestScenario { TestBanner() }
                        if training.hasOpenSession { resumeCard }
                        // 05's voice channel: talk with ROOK hands-free (04's conversation section sits next to it).
                        RookVoicePanel()
                        if let snapshot {
                            content(snapshot)
                        } else if loaded {
                            EmptyState(title: "Coach einrichten",
                                       message: "Sag mir, was du gern machst und wie viel Zeit du hast. Ohne Sportart plane ich Alltagsbewegung, Beweglichkeit und Erholung.",
                                       systemImage: "figure.run", actionTitle: "Jetzt einrichten") { showSetup = true }
                                .accessibilityIdentifier("coach.setup")
                        }
                    }
                    .padding(.horizontal, Spacing.l)
                    .padding(.bottom, Spacing.xl)
                }
            }
            .navigationTitle("Coach")
            .profileToolbar()
            .task(id: "\(refresh)|\(sources.syncing.count)|\(training.isPresented)") { reload() }
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
        lead(s)
        if showWhy { why(s) }
        SectionHeader(title: "Dein Tag")
        ForEach(s.plan.blocks) { block in
            CoachBlockCard(block: block) { start(block) }
        }
        reviewCard(s)
        SectionHeader(title: "Dein Programm")
        CoachWeekCard(program: s.program, position: s.position, now: now)
        loadCard(s.load)
        Button { showSetup = true } label: { Label("Coach anpassen", systemImage: "slider.horizontal.3") }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("coach.settings")
    }

    // MARK: Lead

    private func lead(_ s: CoachSnapshot) -> some View {
        let primary = WorkoutBuilder.primaryBlock(of: s.plan)
        let lead = CoachLead.make(plan: s.plan, doneToday: s.doneToday, canStart: primary != nil)
        return VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.s) {
                Circle()
                    .fill(RadialGradient(colors: [Palette.bioCyan, Palette.neuralViolet.opacity(0.6)],
                                         center: .center, startRadius: 1, endRadius: 14))
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                Text("ROOK")
                    .font(Typography.motto)
                    .tracking(1.5)
                    .foregroundStyle(Palette.ink)
                Spacer()
                if s.plan.decision == .seekHelp { StatementBadge(kind: .medicalCheck) }
            }
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(lead.headline)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .wraps()
                Text(lead.line)
                    .font(Typography.body)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("coach.decision")
            if let title = lead.actionTitle, let primary {
                Button { start(primary) } label: {
                    Label(title, systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("coach.start")
            }
            HStack(spacing: Spacing.m) {
                Button(showWhy ? "Weniger" : "Warum?") { showWhy.toggle() }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("coach.why")
                if s.plan.decision != .rest, s.plan.decision != .seekHelp, s.plan.suggested.kind != .rest {
                    adjustMenu(s)
                }
            }
        }
        .padding(Spacing.l)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(LinearGradient(colors: [Palette.surfaceRaised, Palette.neuralViolet.opacity(0.18)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1))
        )
    }

    private var resumeCard: some View {
        Card {
            Label(training.summary == nil ? "Deine Einheit läuft noch" : "Deine Einheit wartet auf den Abschluss",
                  systemImage: "figure.strengthtraining.functional")
                .font(Typography.label)
                .foregroundStyle(Palette.pulseCoral)
                .wraps()
            Button(training.summary == nil ? "Fortsetzen" : "Abschließen") { training.reopen() }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("coach.resume")
        }
    }

    /// "Warum?": what the plan rests on, measured signals only; unknown ones stay out of the way.
    private func why(_ s: CoachSnapshot) -> some View {
        Card {
            HStack {
                Text("WARUM")
                    .font(Typography.motto)
                    .tracking(1)
                    .foregroundStyle(Palette.inkMuted)
                Spacer()
                StatementBadge(kind: .computed)
            }
            Text(s.plan.decision.explanation)
                .font(Typography.caption)
                .foregroundStyle(Palette.ink)
                .wraps()
            ForEach(s.plan.signals.filter { $0.state != .unknown }) { signal in
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Label(signal.kind.title, systemImage: signal.state == .notable ? "arrow.up.and.down.circle" : "circle")
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
            if let reason = s.plan.blocks.first(where: { $0.id == "main" })?.reason {
                Label(reason, systemImage: "info.circle")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.ink)
                    .wraps()
            }
            ForEach(s.plan.notes, id: \.self) { note in
                Label(note, systemImage: "info.circle")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.ink)
                    .wraps()
            }
            Text("Ich vergleiche mit deinen eigenen Werten der letzten 30 Tage und passe nur an, wenn ein Wert deutlich außerhalb deines üblichen Bereichs liegt.")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
        }
        .accessibilityIdentifier("coach.signals")
    }

    private func adjustMenu(_ s: CoachSnapshot) -> some View {
        let session = s.plan.suggested
        let others = Sport.allCases.filter { $0 != session.sport && (!$0.isOptionalModule || s.preferences.sports.contains($0)) }
        return Menu {
            Button("Heute nur 15 Minuten") { propose(.timeLimit(minutes: 15), s) }
            Button("Leichter") { propose(.easier, s) }
            Button("Etwas mehr") { propose(.harder, s) }
            Menu("Lieber etwas anderes") {
                ForEach(others) { sport in
                    Button(sport.title) { propose(.swapActivity(sport), s) }
                }
            }
            Menu("Ich habe Muskelkater") {
                ForEach(BodyRegion.allCases) { region in
                    Menu(region.title) {
                        Button("leicht bis mittel") { propose(.soreness(region: region, level: 4), s) }
                        Button("stark") { propose(.soreness(region: region, level: 8), s) }
                    }
                }
            }
            Button("Heute aussetzen", role: .destructive) { propose(.skipToday, s) }
        } label: {
            Text("Anpassen").frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityIdentifier("coach.adjust")
    }

    private func propose(_ intent: CoachIntent, _ s: CoachSnapshot) {
        let (after, reason) = PlanAdjuster.apply(intent, to: s.plan.suggested, preferences: s.preferences, decision: s.plan.decision,
                                                 neighbourIsHard: s.program.neighbourIsHard(of: s.plan.day, calendar: .current))
        proposal = CoachProposal(intent: intent, before: s.plan.suggested, after: after, reason: reason)
    }

    /// Opens the guided session for a block (main session or any block with exercises).
    private func start(_ block: DayBlock) {
        guard let session = WorkoutBuilder.session(for: block) else { return }
        training.open(session, title: block.title)
    }

    // MARK: Review and load

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
                Text("Zwei Minuten am Abend reichen: Daraus plane ich morgen.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
            }
            Button(s.todayReview == nil ? "Tag abschließen" : "Tagesabschluss ändern") { showReview = true }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("coach.review")
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
            if let mean = load.fourWeekMean {
                Text("Mittel der 4 Wochen davor: \(Int(mean))")
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
    /// Starts the guided session for this block; shown when the block has something to play.
    var onStart: (() -> Void)?

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
            if let onStart, block.kind != .mainWorkout, !block.exercises.isEmpty {
                Button { onStart() } label: {
                    Label("Geführt starten", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("coach.block.\(block.id).start")
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
