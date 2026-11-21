import PulseCore
import SwiftData
import SwiftUI

/// Small card for HEUTE: today's energy and fluids from the diary.
struct NutritionTodayCard: View {
    @Query private var rows: [StoredMealEntry]

    init() {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _rows = Query(filter: #Predicate<StoredMealEntry> { $0.date >= start && $0.date < end }, sort: \.date)
    }

    var body: some View {
        let summary = DailyNutritionSummary.build(entries: rows.compactMap(\.entry), day: Date())
        Card {
            Label("Ernährung heute", systemImage: "fork.knife")
                .font(Typography.label)
                .foregroundStyle(Palette.inkMuted)
            if summary.isEmpty {
                Text("Noch nichts erfasst.")
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
            } else {
                Text("\(NutritionFormat.value(summary.totals[.energy], of: .energy, incomplete: !summary.totals.isComplete(.energy))) · \(Int(summary.fluidMilliliters)) ml Wasser")
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                    .wraps()
                Text("\(summary.entryCount) Einträge, berechnet aus deinem Tagebuch")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
            }
        }
    }
}
