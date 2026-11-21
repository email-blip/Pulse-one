import PulseCore
import SwiftData
import SwiftUI

/// ERNÄHRUNG tab (NUTRITION-SPEC §3): diary of one day, totals with visible data quality,
/// barcode scan, search, own foods, water quick buttons.
struct NutritionScreen: View {
    @Environment(\.modelContext) private var modelContext
    @State private var store = NutritionStore(isTestScenario: LaunchOptions.current.usesTestScenario)
    @State private var day = Calendar.current.startOfDay(for: Date())

    var body: some View {
        NavigationStack {
            // `.id(day)` rebuilds the diary when the day changes, so its @Query filter follows the new day.
            DayDiaryView(day: $day)
                .id(day)
                .navigationTitle("Ernährung")
                .profileToolbar()
                .navigationDestination(for: NutritionRoute.self) { route in
                    switch route {
                    case .settings: NutritionSettingsView()
                    }
                }
        }
        .environment(store)
        .onAppear { store.modelContext = modelContext }
        .screenIdentifier("nutrition")
    }
}

enum NutritionRoute: Hashable {
    case settings
}

/// What the diary shows in a sheet.
enum NutritionSheet: Identifiable {
    case search
    case scan
    case custom
    case edit(StoredMealEntry)

    var id: String {
        switch self {
        case .search: "search"
        case .scan: "scan"
        case .custom: "custom"
        case .edit(let row): "edit-\(row.entryID)"
        }
    }
}

private struct DayDiaryView: View {
    @Binding var day: Date
    @Environment(NutritionStore.self) private var store
    @Query private var rows: [StoredMealEntry]
    @State private var sheet: NutritionSheet?

    init(day: Binding<Date>) {
        _day = day
        let start = Calendar.current.startOfDay(for: day.wrappedValue)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _rows = Query(filter: #Predicate<StoredMealEntry> { $0.date >= start && $0.date < end }, sort: \.date)
    }

    private var entries: [(row: StoredMealEntry, entry: MealEntry)] {
        rows.compactMap { row in row.entry.map { (row, $0) } }
    }

    private var summary: DailyNutritionSummary {
        DailyNutritionSummary.build(entries: entries.map(\.entry), day: day)
    }

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        List {
            if store.isTestScenario {
                TestBanner().listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
            Section { dayPicker }
                .listRowBackground(Color.clear)
            Section {
                NutritionTotalsCard(summary: summary)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            Section { captureButtons }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            ForEach(MealType.allCases) { meal in
                mealSection(meal)
            }
            if rows.count > entries.count {
                Text("\(rows.count - entries.count) Einträge konnten nicht gelesen werden und werden nicht mitgezählt.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .listRowBackground(Color.clear)
            }
            Section {
                NavigationLink(value: NutritionRoute.settings) {
                    Label("Einstellungen und Datenquellen", systemImage: "gearshape")
                        .font(Typography.body)
                        .foregroundStyle(Palette.ink)
                }
                .listRowBackground(Palette.surfaceRaised)
                Text("Nährwerte stammen aus Datenbanken (Open Food Facts, USDA) oder deiner Eingabe. Sie beschreiben, was du erfasst hast, und sind keine Ernährungsberatung.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ScreenBackground())
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
                .environment(store)
                .preferredColorScheme(.dark)
        }
        .alert("Apple Health", isPresented: Binding(get: { store.healthProblem != nil },
                                                    set: { if !$0 { store.healthProblem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.healthProblem ?? "")
        }
    }

    private var dayPicker: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel("Vorheriger Tag")
            Spacer()
            Text(dayTitle)
                .font(Typography.title)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .disabled(isToday)
                .accessibilityLabel("Nächster Tag")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Palette.bioCyan)
    }

    private var dayTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Heute" }
        if calendar.isDateInYesterday(day) { return "Gestern" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "de_DE")))
    }

    private func shift(_ days: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: day) else { return }
        day = min(Calendar.current.startOfDay(for: next), Calendar.current.startOfDay(for: Date()))
    }

    private var captureButtons: some View {
        Card {
            Button { sheet = .scan } label: {
                Label("Barcode scannen", systemImage: "barcode.viewfinder")
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("nutrition.scan")
            Button { sheet = .search } label: {
                Label("Lebensmittel suchen", systemImage: "magnifyingglass")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("nutrition.search")
            Button { sheet = .custom } label: {
                Label("Selbst eingeben", systemImage: "square.and.pencil")
            }
            .buttonStyle(SecondaryButtonStyle())
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.s) { waterButtons }
                VStack(spacing: Spacing.s) { waterButtons }
            }
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder private var waterButtons: some View {
        ForEach([250.0, 500.0], id: \.self) { ml in
            Button { store.addWater(ml, at: entryDate) } label: {
                Label("Wasser \(Int(ml)) ml", systemImage: "drop")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    /// Now on today; the same clock time on an earlier day.
    private var entryDate: Date {
        if isToday { return Date() }
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return Calendar.current.date(bySettingHour: now.hour ?? 12, minute: now.minute ?? 0, second: 0, of: day) ?? day
    }

    @ViewBuilder private func mealSection(_ meal: MealType) -> some View {
        let items = entries.filter { $0.entry.mealType == meal }
        Section {
            if items.isEmpty {
                HStack {
                    Text("Noch nichts erfasst")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                    Spacer()
                    Button("Wie gestern") { _ = store.repeatYesterday(meal, onto: day) }
                        .font(Typography.caption)
                        .foregroundStyle(Palette.bioCyan)
                        .buttonStyle(.borderless)
                }
                .listRowBackground(Palette.surfaceRaised)
            }
            ForEach(items, id: \.row.entryID) { item in
                Button { sheet = .edit(item.row) } label: { MealEntryRow(entry: item.entry) }
                    .listRowBackground(Palette.surfaceRaised)
                    .swipeActions {
                        Button("Löschen", systemImage: "trash", role: .destructive) { store.delete(item.row) }
                    }
            }
        } header: {
            HStack {
                Text(meal.label)
                Spacer()
                if let kcal = summary.perMeal[meal]?[.energy] {
                    Text(NutritionFormat.value(kcal, of: .energy, incomplete: !(summary.perMeal[meal]?.isComplete(.energy) ?? true)))
                }
            }
            .font(Typography.label)
            .foregroundStyle(Palette.inkMuted)
        }
    }

    @ViewBuilder private func sheetContent(_ sheet: NutritionSheet) -> some View {
        switch sheet {
        case .search:
            FoodSearchView(defaultDate: entryDate) { self.sheet = nil }
        case .scan:
            BarcodeScanView(defaultDate: entryDate) { self.sheet = nil }
        case .custom:
            NavigationStack {
                CustomFoodView(barcode: nil, defaultDate: entryDate) { self.sheet = nil }
            }
        case .edit(let row):
            if let entry = row.entry {
                NavigationStack {
                    PortionView(food: entry.food, method: entry.method, defaultDate: entry.date, existing: (row, entry)) { self.sheet = nil }
                }
            }
        }
    }
}

struct MealEntryRow: View {
    let entry: MealEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(entry.food.displayName)
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                    .wraps()
                Text("\(NutritionFormat.amount(entry.amount, unit: entry.food.unit)) · \(entry.quality.label)")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
            }
            Spacer(minLength: Spacing.s)
            Text(NutritionFormat.value(entry.nutrients.energyKcal, of: .energy, estimated: entry.status == .estimated))
                .font(Typography.label)
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}

/// Day totals. "mind." marks a sum where at least one entry had no value for that nutrient.
struct NutritionTotalsCard: View {
    let summary: DailyNutritionSummary
    @ScaledMetric(relativeTo: .largeTitle) private var bigSize: CGFloat = 40

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text("Tagessumme")
                    .font(Typography.label)
                    .foregroundStyle(Palette.inkMuted)
                Spacer()
                Text("berechnet aus deinen Einträgen")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
            }
            if summary.isEmpty {
                Text("Noch keine Einträge an diesem Tag.")
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                    .wraps()
            } else {
                Text(energyText)
                    .font(Typography.vital(size: bigSize))
                    .foregroundStyle(Palette.ink)
                    .wraps()
                    .accessibilityLabel("Energie \(energyText)")
                VStack(spacing: Spacing.s) {
                    ForEach([Nutrient.protein, .carbohydrates, .sugars, .fat, .fiber, .salt], id: \.self) { n in
                        row(n.label, NutritionFormat.value(summary.totals[n], of: n, incomplete: !summary.totals.isComplete(n)))
                    }
                    row("Getränke (Wasser)", "\(Int(summary.fluidMilliliters)) ml")
                }
                if summary.estimatedCount > 0 {
                    Text("\(summary.estimatedCount) Einträge sind geschätzt.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                }
                if !summary.totals.incomplete.isEmpty {
                    Text("„mind.“ heißt: Bei mindestens einem Eintrag fehlt diese Angabe in der Datenbank.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .wraps()
                }
            }
        }
    }

    private var energyText: String {
        NutritionFormat.value(summary.totals[.energy], of: .energy, incomplete: !summary.totals.isComplete(.energy))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Palette.inkMuted)
            Spacer()
            Text(value).foregroundStyle(Palette.ink).monospacedDigit()
        }
        .font(Typography.body)
        .accessibilityElement(children: .combine)
    }
}
