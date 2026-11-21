import PulseCore
import SwiftUI

/// Search: own foods and favourites first, then Open Food Facts and USDA (NUTRITION-SPEC §3).
/// Only the search term leaves the phone; the screen says so.
struct FoodSearchView: View {
    let defaultDate: Date
    var onDone: () -> Void

    @Environment(NutritionStore.self) private var store
    @State private var query = ""
    @State private var online: FoodLookupService.SearchResults?
    @State private var searching = false

    var body: some View {
        NavigationStack {
            List {
                let local = query.isEmpty ? store.recentFoods() : store.localMatches(query)
                if !local.isEmpty {
                    Section(query.isEmpty ? "Favoriten und zuletzt verwendet" : "Bei dir gespeichert") {
                        ForEach(local) { foodLink($0) }
                    }
                }
                if query.trimmingCharacters(in: .whitespaces).count >= 2 {
                    Section {
                        if searching {
                            HStack { ProgressView(); Text("Suche läuft …").foregroundStyle(Palette.inkMuted) }
                        }
                        if let online {
                            ForEach(online.items) { foodLink($0) }
                            if online.items.isEmpty, !searching {
                                Text("Keine Treffer. Du kannst das Lebensmittel selbst anlegen.")
                                    .foregroundStyle(Palette.inkMuted)
                            }
                            ForEach(online.problems, id: \.self) { problem in
                                Label(problem, systemImage: "exclamationmark.triangle")
                                    .font(Typography.caption)
                                    .foregroundStyle(Palette.inkMuted)
                            }
                        }
                    } header: {
                        Text("Datenbanken")
                    } footer: {
                        Text(store.onlineLookup
                             ? "Gesendet wird nur der Suchbegriff „\(query)“ an Open Food Facts und USDA, keine Gesundheits- oder Profildaten."
                             : "Online-Suche ist ausgeschaltet. Es wird nichts gesendet.")
                    }
                }
                Section {
                    NavigationLink("Selbst eingeben") {
                        CustomFoodView(barcode: nil, initialName: query, defaultDate: defaultDate, onDone: onDone)
                    }
                    .foregroundStyle(Palette.bioCyan)
                }
            }
            .scrollContentBackground(.hidden)
            .background(ScreenBackground())
            .navigationTitle("Lebensmittel suchen")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "z. B. Haferflocken, Apfel")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen", action: onDone) }
            }
            .task(id: query) { await runSearch() }
        }
    }

    private func foodLink(_ food: FoodItem) -> some View {
        NavigationLink {
            PortionView(food: food, method: .search, defaultDate: defaultDate, onDone: onDone)
        } label: {
            FoodRow(food: food)
        }
    }

    /// Debounced (600 ms) so typing does not hit the 10-per-minute Open Food Facts limit.
    private func runSearch() async {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2 else { online = nil; searching = false; return }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        searching = true
        let results = await store.search(term)
        searching = false
        guard !Task.isCancelled else { return }
        online = results
    }
}

struct FoodRow: View {
    let food: FoodItem

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(food.displayName)
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
                .wraps()
            Text(detail)
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts: [String] = []
        if let brand = food.brand { parts.append(brand) }
        parts.append("\(NutritionFormat.value(food.per100.energyKcal, of: .energy)) je 100 \(food.unit.rawValue)")
        parts.append(food.source.label)
        parts.append(food.quality.label)
        return parts.joined(separator: " · ")
    }
}
