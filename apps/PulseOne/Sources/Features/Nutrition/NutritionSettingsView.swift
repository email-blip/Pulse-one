import PulseCore
import SwiftUI

/// Data sources, what is sent where, optional USDA key and the Apple Health opt-in (NUTRITION-SPEC §4, §9).
struct NutritionSettingsView: View {
    @Environment(NutritionStore.self) private var store
    @State private var usdaKey = ""
    @State private var healthBusy = false

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Toggle("Online-Suche", isOn: $store.onlineLookup)
                    .accessibilityIdentifier("nutrition.onlineToggle")
            } footer: {
                Text("Beim Scannen und Suchen fragt PULSE ONE Open Food Facts und USDA FoodData Central. Gesendet wird nur der Barcode oder der Suchbegriff, keine Gesundheits- oder Profildaten. Diese Dienste sehen also, welches Produkt du suchst. Ausgeschaltet findet die App nur bei dir gespeicherte Lebensmittel.")
            }

            Section {
                Toggle("Mahlzeiten in Apple Health schreiben", isOn: Binding(
                    get: { store.writesToHealth },
                    set: { on in
                        healthBusy = true
                        Task {
                            await store.setWritesToHealth(on)
                            healthBusy = false
                        }
                    }))
                    .disabled(healthBusy)
                if let problem = store.healthProblem {
                    Text(problem).font(Typography.caption).foregroundStyle(Palette.ink)
                }
            } footer: {
                Text("Standard: aus. Eingeschaltet schreibt PULSE ONE neue Einträge (Energie, Eiweiß, Kohlenhydrate, Fett, Ballaststoffe, Zucker, Wasser) in Apple Health. Fehlende Werte werden nicht geschrieben. Löschst du einen Eintrag hier, wird er auch dort entfernt.")
            }

            Section {
                SecureField(store.hasUSDAKey ? "Eigener Schlüssel gespeichert" : "api.data.gov-Schlüssel (optional)", text: $usdaKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Schlüssel speichern") {
                    let key = usdaKey
                    usdaKey = ""
                    Task { await store.setUSDAKey(key) }
                }
                .disabled(usdaKey.trimmingCharacters(in: .whitespaces).isEmpty)
                if store.hasUSDAKey {
                    Button("Schlüssel entfernen", role: .destructive) { Task { await store.setUSDAKey(nil) } }
                }
            } header: {
                Text("USDA-Schlüssel")
            } footer: {
                Text("Ohne eigenen Schlüssel nutzt PULSE ONE den Demo-Zugang (etwa 30 Suchen pro Stunde). Ein eigener kostenloser Schlüssel von api.data.gov erlaubt 1000 pro Stunde. Er wird nur im Schlüsselbund dieses iPhones gespeichert.")
            }

            Section("Datenquellen") {
                ForEach([FoodSource.openFoodFacts, .usda, .custom], id: \.self) { source in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(source.label).font(Typography.body).foregroundStyle(Palette.ink)
                        Text(source.attribution).font(Typography.caption).foregroundStyle(Palette.inkMuted)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("Kennzeichen an jedem Wert: amtliche Tabelle, Herstellerangabe, unvollständig, geschätzt, eigene Angabe. Dein Ernährungstagebuch bleibt auf diesem iPhone.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
            }
        }
        .scrollContentBackground(.hidden)
        .background(ScreenBackground())
        .navigationTitle("Ernährung: Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
    }
}
