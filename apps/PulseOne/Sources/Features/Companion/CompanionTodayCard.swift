import PulseCore
import SwiftData
import SwiftUI

/// Companion summary for TODAY. When the alarm button opened the app, it offers the wake-up flow
/// prominently; otherwise it shows the day type, the briefing headline and the next nudge.
/// Content only: the lead wraps the summary in the NavigationLink to `CompanionScreen`.
struct CompanionTodayCard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SourcesStore.self) private var sources
    @Environment(ProfileStore.self) private var profile
    @Environment(RingStore.self) private var ring
    @Environment(\.reduceMotionEffective) private var reduceMotion
    @Environment(\.freezeAnimations) private var freeze
    @State private var store: CompanionStore?
    @Environment(\.scenePhase) private var scenePhase
    @State private var showWake = false
    /// The alarm button opened the app and the wake-up flow has not run yet.
    @State private var alarmWaiting = false

    var body: some View {
        Group {
            if let store {
                if alarmWaiting {
                    wakePrompt
                } else {
                    CompanionTodaySummary(store: store)
                }
            }
        }
        .task { await prepare() }
        .onChange(of: scenePhase) { _, phase in
            // Alarm button while TODAY is already open: the app only returns to the foreground.
            if phase == .active { checkPendingWake() }
        }
        .fullScreenCover(isPresented: $showWake, onDismiss: { alarmWaiting = store?.pendingAlarmWake != nil }) {
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
    }

    /// Prominent text only: the whole card is the label of TODAY's NavigationLink, so no buttons here.
    /// The wake-up flow itself opens automatically (see `prepare`).
    private var wakePrompt: some View {
        Card {
            CompanionCardTitle(title: "Begleiter", systemImage: "sunrise")
            Text("Guten Morgen – Bericht starten")
                .font(Typography.title)
                .foregroundStyle(Palette.ink)
                .wraps()
            Text("Dein Wecker hat geklingelt. Der Morgenbericht öffnet sich gleich.")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.companion")
    }

    /// Runs on every appearance: creates the store once, then refreshes when the day is missing, from
    /// yesterday or older than 15 minutes (the TODAY tab stays alive across days).
    private func prepare() async {
        let created: CompanionStore
        if let store {
            created = store
        } else {
            created = CompanionStore(context: modelContext)
            store = created
        }
        checkPendingWake()
        if alarmWaiting { return }
        if created.needsRefresh(now: CompanionUI.now) {
            await created.refresh(profileID: sources.ownerProfileID, birthYear: profile.profile.birthYear,
                                  firstName: CompanionUI.firstName(preferences: created.preferences, profile: profile.profile),
                                  confirmedWake: nil, morningHeartRate: nil)
        }
    }

    /// Opened by the alarm button: start the wake-up flow right away (never in UI tests; the store's
    /// `pendingAlarmWake` is nil there). The flow itself refreshes with the confirmed wake time.
    private func checkPendingWake() {
        guard let store, !LaunchOptions.current.isUITesting else { return }
        alarmWaiting = store.pendingAlarmWake != nil
        if alarmWaiting && !showWake { showWake = true }
    }
}

/// Compact companion state: day type, headline and the next nudge.
private struct CompanionTodaySummary: View {
    let store: CompanionStore

    var body: some View {
        let briefing = store.today?.briefing ?? store.latestBriefing
        let now = CompanionUI.now
        let next = store.today?.nudges.first(where: { $0.time > now })
        Card {
            HStack(alignment: .firstTextBaseline) {
                CompanionCardTitle(title: "Begleiter", systemImage: "sunrise")
                Spacer(minLength: Spacing.s)
                if store.settings.alarmEnabled {
                    Label(CompanionUI.clock(hour: store.settings.alarmHour, minute: store.settings.alarmMinute),
                          systemImage: "alarm")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                }
            }
            if let briefing {
                Text(briefing.dayType.title)
                    .font(Typography.motto)
                    .foregroundStyle(Palette.bioCyan)
                    .wraps()
                Text(briefing.headline)
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                    .wraps()
            } else {
                Text("Wecker, Morgenbericht und wenige Hinweise über den Tag, aus deinen eigenen Werten.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
            }
            if let next {
                Label("Als Nächstes um \(CompanionUI.time(next.time)): \(next.title)", systemImage: next.kind.symbol)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.ink)
                    .wraps()
                if !store.nudgesDelivered {
                    Text("Mitteilungen sind aus, dieser Hinweis erscheint nur hier.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .wraps()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.companion")
    }
}
