import Foundation
import Testing
@testable import PulseCore

private let t0 = Date(timeIntervalSince1970: 1_795_000_000)
private var berlin: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return c
}

private func food(_ name: String, kcal: Double?, protein: Double? = 10, carbs: Double? = 20, fat: Double? = 5,
                  unit: FoodUnit = .gram) -> FoodItem {
    FoodItem(source: .custom, sourceID: name, name: name, unit: unit,
             per100: NutrientValues(energyKcal: kcal, protein: protein, carbohydrates: carbs, fat: fat),
             quality: .user)
}

@Suite("Nutrient values")
struct NutrientValueTests {
    @Test func scalesPer100ToAmountAndKeepsMissingAsNil() {
        let v = NutrientValues(energyKcal: 380, protein: 13, carbohydrates: 60, fat: 7)
        let portion = v.scaled(toAmount: 50)
        #expect(portion.energyKcal == 190)
        #expect(portion.protein == 6.5)
        #expect(portion.sugars == nil)
        #expect(portion.missing.contains(.sugars))
    }

    @Test func sanitizingDropsImpossibleValues() {
        let v = NutrientValues(energyKcal: 1_200, protein: -1, carbohydrates: 10, sugars: 30, fat: 5, saturatedFat: 2, salt: 0.1)
        let (clean, dropped) = v.sanitizedPer100()
        #expect(clean.energyKcal == nil)
        #expect(clean.protein == nil)
        #expect(clean.sugars == nil)          // more sugar than carbohydrates
        #expect(clean.saturatedFat == 2)
        #expect(Set(dropped) == [.energy, .protein, .sugars])
    }

    @Test func sanitizingDropsMacrosAddingUpToMoreThanTheWhole() {
        let v = NutrientValues(energyKcal: 500, protein: 60, carbohydrates: 60, fat: 10, fiber: 5)
        let clean = v.sanitizedPer100().values
        #expect(clean.energyKcal == 500)
        #expect(clean.protein == nil && clean.carbohydrates == nil && clean.fat == nil)
    }

    @Test func sanitizingKeepsHighFibreFoodsWhereCarbsIncludeFibre() {
        // USDA chia seeds: carbohydrates already include the 34.4 g fibre.
        let v = NutrientValues(energyKcal: 486, protein: 16.5, carbohydrates: 42.1, fat: 30.7, fiber: 34.4)
        let (clean, dropped) = v.sanitizedPer100()
        #expect(dropped.isEmpty)
        #expect(clean.protein == 16.5 && clean.carbohydrates == 42.1 && clean.fat == 30.7 && clean.fiber == 34.4)
    }

    @Test func totalsMarkNutrientsMissingInAnyPart() {
        var totals = NutrientTotals()
        totals.add(NutrientValues(energyKcal: 100, protein: 5))
        totals.add(NutrientValues(energyKcal: 50))
        #expect(totals[.energy] == 150)
        #expect(totals[.protein] == 5)
        #expect(totals.isComplete(.energy))
        #expect(!totals.isComplete(.protein))
        #expect(totals[.salt] == nil)
    }

    @Test func formatsAtLeastAndApproximately() {
        #expect(NutritionFormat.value(523.4, of: .energy) == "523 kcal")
        #expect(NutritionFormat.value(6.26, of: .protein, incomplete: true) == "mind. 6,3 g")
        #expect(NutritionFormat.value(12, of: .fat, estimated: true) == "ca. 12 g")
        #expect(NutritionFormat.value(nil, of: .salt) == "keine Angabe")
    }
}

@Suite("Meals and day summary")
struct DailyNutritionTests {
    @Test func suggestsMealTypeFromClockTime() {
        func at(_ h: Int, _ m: Int = 0) -> Date {
            berlin.date(bySettingHour: h, minute: m, second: 0, of: t0)!
        }
        #expect(MealType.suggested(for: at(7), calendar: berlin) == .breakfast)
        #expect(MealType.suggested(for: at(12, 30), calendar: berlin) == .lunch)
        #expect(MealType.suggested(for: at(16), calendar: berlin) == .snack)
        #expect(MealType.suggested(for: at(19), calendar: berlin) == .dinner)
        #expect(MealType.suggested(for: at(23), calendar: berlin) == .snack)
    }

    @Test func summarisesOnlyTheRequestedDay() {
        let day = berlin.startOfDay(for: t0)
        let oats = food("Haferflocken", kcal: 370)
        let mystery = food("Unbekannt", kcal: nil, protein: nil)
        let entries = [
            MealEntry(date: day.addingTimeInterval(8 * 3_600), mealType: .breakfast, food: oats, amount: 50, method: .search),
            MealEntry(date: day.addingTimeInterval(13 * 3_600), mealType: .lunch, food: mystery, amount: 200, method: .manual, status: .estimated),
            MealEntry(date: day.addingTimeInterval(14 * 3_600), mealType: .snack, food: .water, amount: 500, method: .quickFluid),
            MealEntry(date: day.addingTimeInterval(-3_600), mealType: .dinner, food: oats, amount: 100, method: .search)
        ]
        let summary = DailyNutritionSummary.build(entries: entries, day: day.addingTimeInterval(10), calendar: berlin)
        #expect(summary.entryCount == 3)
        #expect(summary.estimatedCount == 1)
        #expect(summary.totals[.energy] == 185)
        #expect(!summary.totals.isComplete(.energy))
        #expect(summary.fluidMilliliters == 500)
        #expect(summary.entriesByMeal[.dinner] == nil)
        #expect(summary.perMeal[.breakfast]?[.carbohydrates] == 10)
    }

    @Test func macroSharesUseEnergyFactors() throws {
        let entry = MealEntry(date: t0, mealType: .lunch, food: food("x", kcal: 100, protein: 10, carbs: 10, fat: 0), amount: 100, method: .manual)
        let shares = try #require(DailyNutritionSummary.build(entries: [entry], day: t0, calendar: berlin).macroEnergyShares)
        #expect(shares.protein == 0.5)
        #expect(shares.fat == 0)
    }

    @Test func estimatedStatusOverridesFoodQuality() {
        let e = MealEntry(date: t0, mealType: .lunch, food: food("x", kcal: 1), amount: 10, method: .photo, status: .estimated)
        #expect(e.quality == .estimated)
        #expect(MealEntry(date: t0, mealType: .lunch, food: food("x", kcal: 1), amount: 0, method: .manual).isAmountPlausible == false)
    }
}

@Suite("Barcode")
struct BarcodeTests {
    @Test func acceptsValidGTINs() {
        #expect(Barcode.normalized("4006381333931") == "4006381333931")   // EAN-13
        #expect(Barcode.normalized("96385074") == "96385074")             // EAN-8
        #expect(Barcode.normalized("036000291452") == "036000291452")     // UPC-A
        #expect(Barcode.normalized(" 4006381 333931 ") == "4006381333931")
    }

    @Test func rejectsWrongCheckDigitOrLength() {
        #expect(Barcode.normalized("4006381333932") == nil)
        #expect(Barcode.normalized("12345") == nil)
        #expect(Barcode.normalized("40063813339a1") == nil)
    }
}

@Suite("Open Food Facts parser")
struct OpenFoodFactsTests {
    static let product = """
    {"code":"4000417025005","status":1,"status_verbose":"product found","product":{
      "code":"4000417025005","product_name":"Choco Crispies","product_name_de":"Schoko Müsli","brands":"Kölln, Peter Kölln",
      "quantity":"500 g","serving_quantity":"40","serving_size":"40 g",
      "allergens_tags":["en:gluten","en:milk","en:sesame-seeds"],
      "nutriments":{"energy-kcal_100g":412,"energy-kj_100g":1730,"proteins_100g":"9,5","carbohydrates_100g":62,
        "sugars_100g":18,"fat_100g":13,"saturated-fat_100g":4.1,"fiber_100g":7.2,"salt_100g":0.05}}}
    """

    @Test func parsesProductWithGermanNameServingsAndAllergens() throws {
        let result = try OpenFoodFacts.parseProduct(Data(Self.product.utf8), barcode: "4000417025005", fetchedAt: t0)
        guard case .found(let item) = result else { Issue.record("not found"); return }
        #expect(item.name == "Schoko Müsli")
        #expect(item.brand == "Kölln")
        #expect(item.per100.energyKcal == 412)
        #expect(item.per100.protein == 9.5)
        #expect(item.quality == .community)
        #expect(item.unit == .gram)
        #expect(item.servings.map(\.amount) == [40, 500])
        #expect(item.allergens == ["Gluten", "Milch", "Sesam"])
        #expect(item.id == "off:4000417025005")
    }

    @Test func missingValuesStayNilAndMarkIncomplete() throws {
        let json = """
        {"status":1,"product":{"product_name":"Mineralwasser","quantity":"0,75 l",
          "categories_tags":["en:beverages","en:waters"],"nutriments":{"energy_100g":0}}}
        """
        guard case .found(let item) = try OpenFoodFacts.parseProduct(Data(json.utf8), barcode: "96385074", fetchedAt: t0) else {
            Issue.record("not found"); return
        }
        #expect(item.per100.energyKcal == 0)
        #expect(item.per100.protein == nil)
        #expect(item.quality == .incomplete)
        #expect(item.unit == .milliliter)
        #expect(item.countsAsFluid)
        #expect(item.servings.first?.amount == 750)
        #expect(item.sourceID == "96385074")
    }

    @Test func convertsKilojoulesAndSodium() throws {
        let json = #"{"status":1,"product":{"product_name":"X","nutriments":{"energy-kj_100g":418.4,"sodium_100g":0.4}}}"#
        guard case .found(let item) = try OpenFoodFacts.parseProduct(Data(json.utf8), barcode: "96385074", fetchedAt: t0) else {
            Issue.record("not found"); return
        }
        #expect(abs((item.per100.energyKcal ?? 0) - 100) < 0.001)
        #expect(abs((item.per100.salt ?? 0) - 1.0) < 0.001)
    }

    @Test func unknownProductIsNotFoundAndGarbageThrows() throws {
        let json = #"{"code":"4006381333931","status":0,"status_verbose":"product not found"}"#
        #expect(try OpenFoodFacts.parseProduct(Data(json.utf8), barcode: "4006381333931", fetchedAt: t0) == .notFound)
        #expect(throws: OpenFoodFacts.ParseError.malformed) {
            try OpenFoodFacts.parseProduct(Data("<html>".utf8), barcode: "4006381333931", fetchedAt: t0)
        }
    }

    @Test func searchSkipsNamelessAndEmptyProductsAndDuplicates() throws {
        let json = """
        {"count":3,"products":[
          {"code":"1","product_name":"Haferflocken zart","nutriments":{"energy-kcal_100g":372,"proteins_100g":13.5,"carbohydrates_100g":58.7,"fat_100g":7}},
          {"code":"1","product_name":"Haferflocken zart","nutriments":{"energy-kcal_100g":372}},
          {"code":"2","nutriments":{"energy-kcal_100g":100}},
          {"code":"3","product_name":"Leer","nutriments":{}}]}
        """
        let items = try OpenFoodFacts.parseSearch(Data(json.utf8), fetchedAt: t0)
        #expect(items.map(\.sourceID) == ["1"])
    }

    @Test func buildsRequestsWithoutPersonalData() throws {
        let url = try #require(OpenFoodFacts.productURL(barcode: "4006381333931"))
        #expect(url.absoluteString.hasPrefix("https://world.openfoodfacts.org/api/v2/product/4006381333931?fields="))
        let search = try #require(OpenFoodFacts.searchURL(query: "Haferflocken Kölln"))
        #expect(search.query?.contains("search_terms=Haferflocken%20K%C3%B6lln") == true)
        #expect(OpenFoodFacts.userAgent(appVersion: "1.0.1") == "PulseOne/1.0.1 (iOS; private health diary)")
    }

    @Test func packageAmounts() {
        #expect(OpenFoodFacts.packageAmount("1,5 l") == 1_500)
        #expect(OpenFoodFacts.packageAmount("33 cl") == 330)
        #expect(OpenFoodFacts.packageAmount("1 kg") == 1_000)
        #expect(OpenFoodFacts.packageAmount("6 x 1 l") == 1_000)
        #expect(OpenFoodFacts.packageAmount("Stück") == nil)
    }
}

@Suite("USDA parser")
struct USDATests {
    static let search = """
    {"totalHits":1,"foods":[{"fdcId":173904,"description":"Cereals, oats, regular and quick, not fortified, dry","dataType":"SR Legacy",
      "foodNutrients":[
        {"nutrientId":1008,"nutrientName":"Energy","unitName":"KCAL","value":379},
        {"nutrientId":1003,"nutrientName":"Protein","unitName":"G","value":13.15},
        {"nutrientId":1005,"nutrientName":"Carbohydrate, by difference","unitName":"G","value":67.7},
        {"nutrientId":1004,"nutrientName":"Total lipid (fat)","unitName":"G","value":6.52},
        {"nutrientId":1079,"nutrientName":"Fiber, total dietary","unitName":"G","value":10.1},
        {"nutrientId":1093,"nutrientName":"Sodium, Na","unitName":"MG","value":6}]},
      {"fdcId":1,"description":"Nothing useful","foodNutrients":[]}]}
    """

    @Test func parsesPer100gValuesAndConvertsSodiumToSalt() throws {
        let items = try USDAFoodData.parseSearch(Data(Self.search.utf8), germanName: "Haferflocken", fetchedAt: t0)
        #expect(items.count == 1)
        let oats = try #require(items.first)
        #expect(oats.displayName == "Haferflocken")
        #expect(oats.per100.energyKcal == 379)
        #expect(oats.per100.sugars == nil)
        #expect(abs((oats.per100.salt ?? 0) - 0.015) < 0.0001)
        #expect(oats.quality == .verified)
        #expect(oats.id == "usda:173904")
    }

    @Test func usesAtwaterEnergyWhenKcalMissing() throws {
        let json = #"{"foods":[{"fdcId":2,"description":"Apple","foodNutrients":[{"nutrientId":2047,"unitName":"KCAL","value":64},{"nutrientId":1003,"unitName":"G","value":0.2},{"nutrientId":1005,"unitName":"G","value":15},{"nutrientId":1004,"unitName":"G","value":0.2}]}]}"#
        let item = try #require(try USDAFoodData.parseSearch(Data(json.utf8), germanName: nil, fetchedAt: t0).first)
        #expect(item.per100.energyKcal == 64)
        #expect(item.displayName == "Apple")
    }

    @Test func keyAndLimits() throws {
        #expect(USDAFoodData.hourlyLimit(apiKey: nil) == 30)
        #expect(USDAFoodData.hourlyLimit(apiKey: "abc") == 1_000)
        let url = try #require(USDAFoodData.searchURL(query: "oats", apiKey: nil))
        #expect(url.query?.contains("api_key=DEMO_KEY") == true)
        #expect(FoodTranslation.english(for: " Haferflocken ") == "oats")
        #expect(FoodTranslation.english(for: "Schoko Müsli") == nil)
    }
}

@Suite("Rate limit and lookup service")
struct FoodLookupServiceTests {
    @Test func slidingWindowBlocksAndRecovers() {
        var limiter = SlidingWindowLimiter(limit: 2, window: 60)
        let first = limiter.tryAcquire(now: t0)
        let second = limiter.tryAcquire(now: t0.addingTimeInterval(1))
        let third = limiter.tryAcquire(now: t0.addingTimeInterval(2))
        #expect(first && second && !third)
        #expect(limiter.retryAfter(now: t0.addingTimeInterval(2)) == 58)
        let later = limiter.tryAcquire(now: t0.addingTimeInterval(60))
        #expect(later)
    }

    @Test func barcodeLookupSendsUserAgentAndParses() async throws {
        let seen = RequestLog()
        let service = FoodLookupService(appVersion: "1.0.1", clock: { t0 }) { request in
            await seen.add(request)
            return (Data(OpenFoodFactsTests.product.utf8), 200)
        }
        let result = try await service.lookup(barcode: "4000417025005")
        guard case .found(let item) = result else { Issue.record("not found"); return }
        #expect(item.name == "Schoko Müsli")
        let request = try #require(await seen.requests.first)
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("PulseOne/1.0.1") == true)
    }

    @Test func invalidBarcodeNeverHitsTheNetwork() async {
        let seen = RequestLog()
        let service = FoodLookupService(appVersion: "1", clock: { t0 }) { request in
            await seen.add(request)
            return (Data(), 200)
        }
        await #expect(throws: FoodLookupService.LookupError.invalidBarcode) {
            try await service.lookup(barcode: "123")
        }
        #expect(await seen.requests.isEmpty)
    }

    @Test func notFoundOn404AndOfflineIsUnreachable() async throws {
        let notFound = FoodLookupService(appVersion: "1", clock: { t0 }) { _ in (Data(#"{"status":0}"#.utf8), 404) }
        #expect(try await notFound.lookup(barcode: "4006381333931") == .notFound)
        let offline = FoodLookupService(appVersion: "1", clock: { t0 }) { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: FoodLookupService.LookupError.unreachable) {
            try await offline.lookup(barcode: "4006381333931")
        }
    }

    @Test func searchCombinesSourcesAndReportsFailures() async {
        let service = FoodLookupService(appVersion: "1", clock: { t0 }) { request in
            if request.url?.host == USDAFoodData.host {
                #expect(request.url?.query?.contains("query=oats") == true)
                return (Data(USDATests.search.utf8), 200)
            }
            return (Data(), 503)
        }
        let results = await service.search("Haferflocken")
        #expect(results.items.map(\.source) == [.usda])
        #expect(results.items.first?.displayName == "Haferflocken")
        #expect(results.problems == ["Open Food Facts antwortet nicht (503)"])
    }

    @Test func searchRespectsOpenFoodFactsLimit() async {
        let service = FoodLookupService(appVersion: "1", clock: { t0 }) { _ in (Data(#"{"products":[],"foods":[]}"#.utf8), 200) }
        for _ in 0..<OpenFoodFacts.searchLimit { _ = await service.search("xy") }
        let blocked = await service.search("xy")
        #expect(blocked.problems.contains { $0.hasPrefix("Open Food Facts: bitte 60 s warten") })
    }
}

private actor RequestLog {
    var requests: [URLRequest] = []
    func add(_ r: URLRequest) { requests.append(r) }
}
