import PulseCore
import SwiftData
import SwiftUI

/// Root of the companion module ("Begleiter"): alarm, morning briefing, day nudges, body weather,
/// forecast lab, night researcher and the expert round. Fully local and rule based; texts describe
/// trends relative to the personal band, never diagnoses.
/// Always shown inside an existing `NavigationStack` (pushed from TODAY); it has no stack of its own.
struct CompanionScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SourcesStore.self) private var sources
    @Environment(ProfileStore.self) private var profile
    @Environment(RingStore.self) private var ring
    @Environment(CompanionStore.self) private var sharedStore
    @Environment(\.reduceMotionEffective) private var reduceMotion
    @Environment(\.freezeAnimations) private var freeze
    @State private var store: CompanionStore?
    @State private var speaker = BriefingSpeaker()
    @State private var doneActions: Set<String> = []
    @State private var showWake = false
    @State private var activation: ActivationStore?
    /// The activation session being shown (full screen), nil when none.
    @State private var activationPlan: ActivationPlan?

    init() {}

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if LaunchOptions.current.usesTestScenario { TestBanner() }
                    if let store {
                        CompanionContent(store: store, activation: activation, speaker: speaker,
                                         doneActions: $doneActions, onStartWake: { showWake = true },
                                         onStartActivation: { activationPlan = $0 })
                    } else {
                        ProgressView("Begleiter wird vorbereitet …")
                            .tint(Palette.bioCyan)
                            .foregroundStyle(Palette.inkMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.xl)
                    }
                }
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.xl)
            }
            .refreshable { await refresh() }
        }
        .navigationTitle("Begleiter")
        .task { await prepare() }
        .onDisappear { speaker.stop() }
        .fullScreenCover(isPresented: $showWake, onDismiss: { Task { await refreshActivation() } }) {
            if let store {
                WakeUpView(store: store, profileID: sources.ownerProfileID, birthYear: profile.profile.birthYear,
                           firstName: CompanionUI.firstName(preferences: store.preferences, profile: profile.profile))
                    .environment(ring)
                    .environment(\.reduceMotionEffective, reduceMotion)
                    .environment(\.freezeAnimations, freeze)
                    .modifier(DynamicTypeOverride(size: LaunchOptions.current.dynamicTypeSize))
                    .preferredColorScheme(.dark)
            }
        }
        .fullScreenCover(item: $activationPlan, onDismiss: { Task { await refreshActivation() } }) { plan in
            if let activation {
                ActivationSessionView(store: activation, plan: plan, speaks: store?.preferences.speaksBriefing ?? false)
                    .environment(\.reduceMotionEffective, reduceMotion)
                    .environment(\.freezeAnimations, freeze)
                    .modifier(DynamicTypeOverride(size: LaunchOptions.current.dynamicTypeSize))
                    .preferredColorScheme(.dark)
            }
        }
        .screenIdentifier(CompanionUI.scenario)
    }

    private func prepare() async {
        guard store == nil else { return }
        store = sharedStore
        activation = ActivationStore(context: modelContext)
        let options = LaunchOptions.current
        // Test view of the wake-up flow: open it directly, like the alarm button would.
        if options.usesTestScenario && options.scenario == CompanionUI.wakeScenario {
            showWake = true
            return
        }
        await refresh()
        // Test view of the guided activation: today's first open session, like its start button would.
        if options.usesTestScenario && options.scenario == CompanionUI.activationScenario, let activation {
            activationPlan = activation.firstOpenPlan ?? activation.plan(for: .snack, now: CompanionUI.now)
        }
    }

    private func refresh() async {
        guard let store else { return }
        await store.refresh(profileID: sources.ownerProfileID, birthYear: profile.profile.birthYear,
                            firstName: CompanionUI.firstName(preferences: store.preferences, profile: profile.profile),
                            confirmedWake: nil, morningHeartRate: nil)
        await refreshActivation()
    }

    /// Re-plans the activation with today's companion day and replaces its notifications.
    private func refreshActivation() async {
        guard let activation else { return }
        let now = CompanionUI.now
        let day = store?.today
        activation.refresh(now: now, profileID: sources.ownerProfileID, day: day)
        await activation.scheduleReminders(now: now, dayType: activation.dayType, infection: activation.infectionLevel,
                                           wake: nil)
    }
}

/// All sections of the companion screen; split from the root so each card is its own small view.
private struct CompanionContent: View {
    let store: CompanionStore
    let activation: ActivationStore?
    let speaker: BriefingSpeaker
    @Binding var doneActions: Set<String>
    let onStartWake: () -> Void
    let onStartActivation: (ActivationPlan) -> Void

    var body: some View {
        morning
        if let activation {
            ActivationSection(store: activation, alarm: alarm, onStart: onStartActivation)
        }
        insights
        footer
    }

    @ViewBuilder
    private var morning: some View {
        let day = store.today
        let briefing = day?.briefing ?? store.latestBriefing
        AlarmCard(store: store)
        Button(action: onStartWake) {
            Label("Guten-Morgen-Ablauf starten", systemImage: "sunrise")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityIdentifier("companion.startWake")
        SectionHeader(title: "Dein Morgen")
        if let briefing {
            BriefingCard(briefing: briefing, speaker: speaker, doneActions: $doneActions)
        } else {
            BriefingPlaceholder(isRefreshing: store.isRefreshing, error: store.lastError)
        }
        if let nudges = day?.nudges, !nudges.isEmpty {
            SectionHeader(title: "Tagesimpulse")
            NudgeListCard(nudges: nudges, now: CompanionUI.now)
        }
    }

    private var alarm: (hour: Int, minute: Int)? {
        guard store.settings.alarmEnabled else { return nil }
        return (hour: store.settings.alarmHour, minute: store.settings.alarmMinute)
    }

    @ViewBuilder
    private var insights: some View {
        let day = store.today
        SectionHeader(title: "Prognose-Labor")
        ForecastLabCard(next: day?.nextForecast, outcome: day?.forecastOutcome, hitRate: store.forecastHitRate)
        if let pace = day?.bodyPace {
            BodyPaceCard(result: pace)
        }
    }

    @ViewBuilder
    private var footer: some View {
        NavigationLink {
            CompanionSettingsView(store: store)
        } label: {
            Label("Begleiter einstellen", systemImage: "slider.horizontal.3")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityIdentifier("companion.settings")
    }
}

/// Shown while no briefing exists yet: honest about why.
private struct BriefingPlaceholder: View {
    let isRefreshing: Bool
    let error: String?

    var body: some View {
        if isRefreshing {
            Card {
                ProgressView("Ring-Daten werden ausgewertet …")
                    .tint(Palette.bioCyan)
                    .foregroundStyle(Palette.inkMuted)
            }
        } else {
            EmptyState(title: "Noch kein Morgenbericht",
                       message: error ?? "Sobald dein Ring eine Nacht aufgezeichnet hat, fasst der Begleiter sie hier zusammen. Zum Aktualisieren nach unten ziehen.",
                       systemImage: "sunrise")
        }
    }
}
