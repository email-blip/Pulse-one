import Foundation
import Observation
import PulseCore
import SwiftData

/// State and actions of the nutrition module. Reads and writes SwiftData through the injected context;
/// online lookups go through `FoodLookupService` (barcode or search term only, no personal data).
@MainActor
@Observable
final class NutritionStore {
    enum BarcodeOutcome: Equatable {
        case found(FoodItem)
        case notFound(String)
        case failed(String)
    }

    var modelContext: ModelContext?
    /// Online search on/off (NUTRITION-SPEC §4); default on, decided by Johannes 2026-11-20.
    var onlineLookup: Bool { didSet { defaults.set(onlineLookup, forKey: Keys.online) } }
    /// Write confirmed entries to Apple Health; default off.
    var writesToHealth: Bool { didSet { defaults.set(writesToHealth, forKey: Keys.health) } }
    var healthProblem: String?
    private(set) var hasUSDAKey: Bool

    private let defaults: UserDefaults
    private let service: FoodLookupService
    private let health = NutritionHealthWriter()
    let isTestScenario: Bool

    private enum Keys {
        static let online = "nutrition.onlineLookup"
        static let health = "nutrition.writesToHealth"
    }

    init(defaults: UserDefaults = .standard, isTestScenario: Bool = false) {
        self.defaults = defaults
        self.isTestScenario = isTestScenario
        onlineLookup = defaults.object(forKey: Keys.online) as? Bool ?? true
        writesToHealth = defaults.bool(forKey: Keys.health)
        let key = isTestScenario ? nil : NutritionSecrets.usdaKey()
        hasUSDAKey = key != nil
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1"
        if isTestScenario {
            // Screenshots and UI tests never touch the network.
            service = FoodLookupService(appVersion: version, transport: { _ in throw URLError(.notConnectedToInternet) })
        } else {
            service = FoodLookupService(appVersion: version, usdaKey: key)
        }
    }

    // MARK: Diary

    func entries(on day: Date, calendar: Calendar = .current) -> [StoredMealEntry] {
        guard let modelContext else { return [] }
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let descriptor = FetchDescriptor<StoredMealEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end }, sortBy: [SortDescriptor(\.date)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func add(_ entry: MealEntry) {
        guard let modelContext else { return }
        modelContext.insert(StoredMealEntry(entry))
        remember(entry.food, at: Date())
        try? modelContext.save()
        if writesToHealth, entry.status == .confirmed, !isTestScenario {
            Task { await writeToHealth(entry) }
        }
    }

    func update(_ stored: StoredMealEntry, with entry: MealEntry) {
        stored.update(from: entry)
        try? modelContext?.save()
        guard stored.healthWrittenAt != nil, !isTestScenario else { return }
        // Health samples are immutable: replace them. With Health writing switched off, only remove the old ones.
        let rewrite = writesToHealth && entry.status == .confirmed
        Task {
            try? await health.delete(entryID: entry.id)
            if rewrite {
                await writeToHealth(entry)
            } else {
                stored.healthWrittenAt = nil
                try? modelContext?.save()
            }
        }
    }

    func delete(_ stored: StoredMealEntry) {
        let id = stored.entryID
        let wasWritten = stored.healthWrittenAt != nil
        modelContext?.delete(stored)
        try? modelContext?.save()
        if wasWritten, !isTestScenario { Task { try? await health.delete(entryID: id) } }
    }

    func addWater(_ milliliters: Double, at date: Date = Date()) {
        add(MealEntry(date: date, mealType: MealType.suggested(for: date), food: .water, amount: milliliters, method: .quickFluid))
    }

    /// Copies yesterday's entries of one meal to `day` ("Wie gestern", NUTRITION-SPEC §3).
    func repeatYesterday(_ meal: MealType, onto day: Date, calendar: Calendar = .current) -> Int {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
        let previous = entries(on: yesterday, calendar: calendar).compactMap(\.entry).filter { $0.mealType == meal }
        for old in previous {
            let time = calendar.dateComponents([.hour, .minute], from: old.date)
            let copied = calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: day) ?? day
            // Never date a copied entry in the future (dinner copied in the morning lands at "now").
            let date = min(copied, Date())
            add(MealEntry(date: date, mealType: meal, food: old.food, amount: old.amount, method: .repeated))
        }
        return previous.count
    }

    // MARK: Foods

    func remember(_ food: FoodItem, at date: Date) {
        guard let modelContext else { return }
        let row = cached(key: food.id) ?? {
            let new = StoredFoodItem(food: food, fetchedAt: date)
            modelContext.insert(new)
            return new
        }()
        row.store(food, at: food.fetchedAt ?? date)
        row.useCount += 1
        row.lastUsed = date
    }

    func toggleFavorite(_ food: FoodItem) {
        guard let modelContext else { return }
        let row = cached(key: food.id) ?? {
            let new = StoredFoodItem(food: food)
            modelContext.insert(new)
            return new
        }()
        row.isFavorite.toggle()
        try? modelContext.save()
    }

    func isFavorite(_ food: FoodItem) -> Bool { cached(key: food.id)?.isFavorite ?? false }

    /// Favourites first, then most recently used.
    func recentFoods(limit: Int = 12) -> [FoodItem] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<StoredFoodItem>(predicate: #Predicate { (!$0.notFound && $0.useCount > 0) || $0.isFavorite })
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
            return ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast)
        }.prefix(limit).compactMap(\.food)
    }

    func localMatches(_ query: String, limit: Int = 8) -> [FoodItem] {
        let term = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard let modelContext, !term.isEmpty else { return [] }
        let descriptor = FetchDescriptor<StoredFoodItem>(predicate: #Predicate { !$0.notFound && $0.nameLower.contains(term) })
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        return rows.sorted { $0.useCount > $1.useCount }.prefix(limit).compactMap(\.food)
    }

    /// A food the user created for a barcode Open Food Facts did not know.
    private func ownFood(barcode code: String) -> FoodItem? {
        let target: String? = code
        let descriptor = FetchDescriptor<StoredFoodItem>(predicate: #Predicate { $0.barcode == target && !$0.notFound })
        let rows = (try? modelContext?.fetch(descriptor)) ?? []
        return rows.lazy.compactMap(\.food).first
    }

    private func cached(key: String) -> StoredFoodItem? {
        var descriptor = FetchDescriptor<StoredFoodItem>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return (try? modelContext?.fetch(descriptor))?.first
    }

    // MARK: Online

    func search(_ query: String) async -> FoodLookupService.SearchResults {
        guard onlineLookup else {
            return .init(items: [], problems: ["Online-Suche ist ausgeschaltet (Einstellungen)."])
        }
        let results = await service.search(query)
        return results
    }

    /// Cache first (also remembers "not found" for a week), then Open Food Facts.
    func lookup(barcode raw: String) async -> BarcodeOutcome {
        guard let code = Barcode.normalized(raw) else {
            return .failed("Das ist kein gültiger Barcode. Bitte noch einmal scannen oder die Ziffern prüfen.")
        }
        if let row = cached(key: "off:\(code)"), let food = row.food { return .found(food) }
        if let own = ownFood(barcode: code) { return .found(own) }
        if let missing = cached(key: "off-missing:\(code)"), Date().timeIntervalSince(missing.fetchedAt) < 7 * 86_400 {
            return .notFound(code)
        }
        guard onlineLookup else {
            return .failed("Online-Suche ist ausgeschaltet. Du kannst das Lebensmittel selbst anlegen.")
        }
        do {
            switch try await service.lookup(barcode: code) {
            case .found(let food):
                remember(food, at: Date())
                cached(key: food.id)?.useCount = 0   // fetched, not yet eaten
                try? modelContext?.save()
                return .found(food)
            case .notFound:
                if cached(key: "off-missing:\(code)") == nil { modelContext?.insert(StoredFoodItem(missingBarcode: code)) }
                try? modelContext?.save()
                return .notFound(code)
            }
        } catch let error as FoodLookupService.LookupError {
            return .failed(Self.message(for: error))
        } catch {
            return .failed("Abfrage fehlgeschlagen. Bitte später erneut versuchen.")
        }
    }

    static func message(for error: FoodLookupService.LookupError) -> String {
        switch error {
        case .invalidBarcode: "Das ist kein gültiger Barcode."
        case .rateLimited(let wait): "Zu viele Abfragen. Bitte in \(Int(wait.rounded(.up))) Sekunden erneut versuchen."
        case .http(let status): "Open Food Facts antwortet gerade nicht (\(status)). Bitte später erneut versuchen."
        case .unreachable: "Keine Verbindung. Du kannst das Lebensmittel selbst anlegen oder es später erneut versuchen."
        case .malformed: "Die Antwort von Open Food Facts war unlesbar."
        }
    }

    func setUSDAKey(_ key: String?) async {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        NutritionSecrets.setUSDAKey(trimmed)
        hasUSDAKey = trimmed?.isEmpty == false
        await service.setUSDAKey(trimmed)
    }

    // MARK: Apple Health

    /// Turning it on asks for permission; on refusal the switch goes back off and says why.
    func setWritesToHealth(_ on: Bool) async {
        healthProblem = nil
        guard on else { writesToHealth = false; return }
        guard NutritionHealthWriter.available, !isTestScenario else {
            healthProblem = "Apple Health ist auf diesem Gerät nicht verfügbar."
            return
        }
        do {
            try await health.requestAuthorization()
            writesToHealth = true
        } catch {
            healthProblem = "Apple Health hat die Freigabe nicht erteilt."
            writesToHealth = false
        }
    }

    private func writeToHealth(_ entry: MealEntry) async {
        do {
            try await health.write(entry)
            if let row = entries(on: entry.date).first(where: { $0.entryID == entry.id }) {
                row.healthWrittenAt = Date()
                try? modelContext?.save()
            }
        } catch {
            healthProblem = "Schreiben nach Apple Health hat nicht geklappt. Der Eintrag ist in PULSE ONE gespeichert."
        }
    }
}
