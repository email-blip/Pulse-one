import PulseCore
import SwiftUI

/// Choose amount, meal and time for one food, with a live preview of the nutrients.
/// Also used to edit or delete an existing entry.
struct PortionView: View {
    let food: FoodItem
    let method: MealEntryMethod
    var existing: (row: StoredMealEntry, entry: MealEntry)?
    var onDone: () -> Void

    @Environment(NutritionStore.self) private var store
    @State private var amount: Double
    @State private var meal: MealType
    @State private var date: Date
    @State private var isFavorite = false

    init(food: FoodItem, method: MealEntryMethod, defaultDate: Date,
         existing: (row: StoredMealEntry, entry: MealEntry)? = nil, onDone: @escaping () -> Void) {
        self.food = food
        self.method = method
        self.existing = existing
        self.onDone = onDone
        _amount = State(initialValue: existing?.entry.amount ?? food.servings.first?.amount ?? 100)
        _meal = State(initialValue: existing?.entry.mealType ?? MealType.suggested(for: defaultDate))
        _date = State(initialValue: existing?.entry.date ?? defaultDate)
    }

    private var entry: MealEntry {
        MealEntry(id: existing?.entry.id ?? UUID(), date: date, mealType: meal, food: food, amount: amount,
                  method: existing?.entry.method ?? method, status: .confirmed)
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(food.displayName)
                        .font(Typography.title)
                        .foregroundStyle(Palette.ink)
                        .wraps()
                    if food.nameDe != nil {
                        Text(food.name).font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                    }
                    if let brand = food.brand {
                        Text(brand).font(Typography.caption).foregroundStyle(Palette.inkMuted)
                    }
                    Text("\(food.source.attribution) · \(food.quality.label)")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .wraps()
                }
                if !food.allergens.isEmpty {
                    Label("Allergene laut Hersteller: \(food.allergens.joined(separator: ", ")). Bitte Verpackung prüfen.",
                          systemImage: "exclamationmark.circle")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.ink)
                        .wraps()
                }
            }

            Section("Menge") {
                HStack {
                    TextField("Menge", value: $amount, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .font(Typography.body)
                        .accessibilityIdentifier("nutrition.amount")
                    Text(food.unit.rawValue).foregroundStyle(Palette.inkMuted)
                }
                if !food.servings.isEmpty {
                    ForEach(food.servings, id: \.self) { serving in
                        Button(serving.label) { amount = serving.amount }
                            .foregroundStyle(Palette.bioCyan)
                    }
                }
                if !entry.isAmountPlausible {
                    Text("Bitte eine Menge zwischen 1 und 5000 \(food.unit.rawValue) eingeben.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.pulseCoral)
                }
            }

            Section {
                Picker("Mahlzeit", selection: $meal) {
                    ForEach(MealType.allCases) { Text($0.label).tag($0) }
                }
                DatePicker("Zeit", selection: $date, in: ...Date())
            }

            Section {
                ForEach(Nutrient.allCases, id: \.self) { n in
                    HStack {
                        Text(n.label).foregroundStyle(Palette.inkMuted)
                        Spacer()
                        Text(NutritionFormat.value(entry.nutrients[n], of: n)).foregroundStyle(Palette.ink).monospacedDigit()
                    }
                    .font(Typography.body)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Nährwerte für \(NutritionFormat.amount(amount, unit: food.unit))")
            } footer: {
                Text("Berechnet aus den Werten je 100 \(food.unit.rawValue). „keine Angabe“ heißt: Die Datenbank kennt diesen Wert nicht.")
            }

            Section {
                Button(existing == nil ? "Eintragen" : "Änderung speichern") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!entry.isAmountPlausible)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("nutrition.add")
                if let existing {
                    Button("Eintrag löschen", role: .destructive) {
                        store.delete(existing.row)
                        onDone()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(ScreenBackground())
        .navigationTitle(existing == nil ? "Hinzufügen" : "Eintrag")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.toggleFavorite(food); isFavorite.toggle() } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                }
                .accessibilityLabel(isFavorite ? "Aus Favoriten entfernen" : "Zu Favoriten")
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen", action: onDone)
            }
        }
        .onAppear { isFavorite = store.isFavorite(food) }
    }

    private func save() {
        if let existing {
            store.update(existing.row, with: entry)
        } else {
            store.add(entry)
        }
        onDone()
    }
}
