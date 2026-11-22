import PulseCore
import SwiftUI

/// Own food with values per 100 g/ml from the package (NUTRITION-SPEC §3 "Mahlzeit manuell").
/// Empty fields stay "keine Angabe", never 0.
struct CustomFoodView: View {
    let barcode: String?
    var initialName = ""
    let defaultDate: Date
    var onDone: () -> Void

    @State private var name = ""
    @State private var unit = FoodUnit.gram
    @State private var countsAsFluid = false
    @State private var fields: [Nutrient: String] = [:]
    @State private var created: FoodItem?

    var body: some View {
        Form {
            Section {
                TextField("Name, z. B. Omas Linsensuppe", text: $name)
                    .accessibilityIdentifier("nutrition.customName")
                Picker("Angaben je", selection: $unit) {
                    Text("100 g").tag(FoodUnit.gram)
                    Text("100 ml").tag(FoodUnit.milliliter)
                }
                .pickerStyle(.segmented)
                if unit == .milliliter {
                    Toggle("Zählt als Getränk (Wasser, Tee …)", isOn: $countsAsFluid)
                }
                if let barcode {
                    Text("Barcode \(barcode) wird mit gespeichert. Beim nächsten Scan findet PULSE ONE dieses Lebensmittel.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                }
            }
            Section {
                ForEach(Nutrient.allCases, id: \.self) { n in
                    HStack {
                        Text(n.label)
                        Spacer()
                        TextField("–", text: binding(n))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                        Text(n.unitSymbol).foregroundStyle(Palette.inkMuted)
                    }
                }
            } header: {
                // Own colours: the system's grey header and footer fail the contrast audit on the dark background.
                Text("Nährwerte je 100 \(unit.rawValue)")
                    .font(Typography.label)
                    .foregroundStyle(Palette.ink)
                    .textCase(nil)
            } footer: {
                Text("Leer lassen, was nicht auf der Packung steht. Unmögliche Werte (z. B. über 900 kcal je 100 g) werden nicht übernommen.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
            }
            Section {
                Button("Weiter zur Menge") { created = makeFood() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(ScreenBackground())
        .navigationTitle("Selbst eingeben")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Abbrechen", action: onDone) }
        }
        .navigationDestination(item: $created) { food in
            PortionView(food: food, method: .manual, defaultDate: defaultDate, onDone: onDone)
        }
        .onAppear { if name.isEmpty { name = initialName } }
    }

    private func binding(_ n: Nutrient) -> Binding<String> {
        Binding(get: { fields[n] ?? "" }, set: { fields[n] = $0 })
    }

    private func makeFood() -> FoodItem {
        var values = NutrientValues()
        for n in Nutrient.allCases {
            let text = (fields[n] ?? "").replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
            values[n] = Double(text)
        }
        var food = FoodItem.custom(name: name.trimmingCharacters(in: .whitespaces), unit: unit, per100: values,
                                   countsAsFluid: unit == .milliliter && countsAsFluid)
        food.barcode = barcode
        if !values.hasCoreValues { food.quality = .incomplete }
        return food
    }
}
