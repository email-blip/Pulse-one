import PulseCore
import SwiftData
import SwiftUI

/// TODAY's "Jetzt dran" tile: the one next step of the day from Begleiter, activation and Coach, chosen by
/// `NowPlanner`. Steps of the Begleiter open its screen, the closeout opens the Tagesabschluss sheet; Coach steps
/// name the tab (informational).
struct NowTodayCard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SourcesStore.self) private var sources
    @Environment(CompanionStore.self) private var companion
    @Environment(\.scenePhase) private var scenePhase
    @State private var item: NowItem?
    @State private var activation: ActivationStore?
    @State private var closing = false
    @State private var closeoutSaves = 0

    var body: some View {
        // A stack, not a Group: it exists before the first item, so its task runs.
        VStack(spacing: 0) {
            if let item {
                if item.target == .companion {
                    NavigationLink { CompanionScreen() } label: { NowCardContent(item: item, opens: true) }
                        .buttonStyle(.plain)
                } else if item.target == .eveningNote {
                    Button { closing = true } label: { NowCardContent(item: item, opens: true) }
                        .buttonStyle(.plain)
                } else {
                    NowCardContent(item: item, opens: false)
                }
            }
        }
        // Re-evaluated whenever TODAY appears, the app returns, or the companion finishes a refresh.
        .task(id: "\(scenePhase == .active)|\(companion.lastRefreshAt?.timeIntervalSince1970 ?? 0)|\(closeoutSaves)") { reload() }
        .sheet(isPresented: $closing) {
            DayCloseoutSheet(day: CompanionUI.now, profileID: sources.ownerProfileID) { closeoutSaves += 1 }
                .preferredColorScheme(.dark)
        }
    }

    private func reload() {
        let now = CompanionUI.now
        let calendar = Calendar.current
        let store: ActivationStore
        if let activation {
            store = activation
        } else {
            store = ActivationStore(context: modelContext)
            activation = store
        }
        store.refresh(now: now, profileID: sources.ownerProfileID, day: companion.today)

        let coach = CoachRepository(context: modelContext).snapshot(now: now, profileID: sources.ownerProfileID)
        let dayGuard = DayGuard.evaluate(DayGuardInput(
            coachDecision: coach?.plan.decision,
            limitations: coach?.preferences.limitations ?? [],
            needsMedicalClearance: coach?.preferences.needsMedicalClearance ?? false,
            companionDayType: companion.today?.dayType,
            infectionLevel: companion.today?.infection.level))

        let morningPlan = store.plans.first { $0.slot == .morning }
        var next: (slot: ActivationSlot, time: Date, seconds: Int)?
        for plan in store.plans where plan.slot != .morning && !store.isDone(plan.slot) {
            guard let time = store.time(of: plan.slot, now: now) else { continue }
            // The first open session that is not more than an hour past its time.
            if now.timeIntervalSince(time) <= NowPlanner.dueAfterSeconds {
                next = (slot: plan.slot, time: time, seconds: plan.estimatedSeconds)
                break
            }
        }
        // Closeout done: today's Coach review or evening note exists (works without a set-up coach too).
        let closeout = DayCloseoutRecords.isDone(context: modelContext, day: now, calendar: calendar)
        let reportToday = companion.latestBriefing.map { calendar.isDate($0.createdAt, inSameDayAs: now) } ?? false

        item = NowPlanner.pick(NowInput(
            now: now, calendar: calendar,
            hasMorningReport: reportToday,
            morningActivationOpen: morningPlan != nil && !store.isDone(.morning),
            morningActivationSeconds: morningPlan?.estimatedSeconds ?? 0,
            nextActivation: next,
            snackHint: store.snackHint(now: now),
            coachSession: coach?.plan.suggested,
            eveningReviewDone: closeout,
            dayGuard: dayGuard))
    }
}

private struct NowCardContent: View {
    let item: NowItem
    let opens: Bool

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Label("Jetzt dran", systemImage: "arrow.forward.circle")
                    .font(Typography.label)
                    .foregroundStyle(Palette.bioCyan)
                    .wraps()
                Spacer(minLength: Spacing.s)
                if opens {
                    Image(systemName: "chevron.right")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .accessibilityHidden(true)
                }
            }
            Label(item.title, systemImage: item.symbol)
                .font(Typography.title)
                .foregroundStyle(Palette.ink)
                .wraps()
            Text(item.detail)
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.now")
        .accessibilityHint(opens ? (item.target == .eveningNote ? "Öffnet den Tagesabschluss." : "Öffnet den Begleiter.") : "")
    }
}
