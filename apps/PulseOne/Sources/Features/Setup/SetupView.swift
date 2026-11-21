import PulseCore
import SwiftUI
import UIKit

/// First-start setup. Every step is optional, the app works without a device, and the setup
/// continues at the saved step after a restart (Codex P1-003 product order).
struct SetupView: View {
    @Environment(ProfileStore.self) private var store
    @Environment(SourcesStore.self) private var sources
    @State private var step = 0
    @State private var name = ""
    @State private var birthYear = ""
    @State private var height = ""
    @State private var weight = ""

    static let stepCount = 4

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    if LaunchOptions.current.usesTestScenario { TestBanner() }
                    // Opaque card behind all text: the audit measured text directly on the page gradient
                    // as low contrast (CI runs 36 and 44), cards pass on every other screen.
                    Card {
                    HStack {
                        Text("Schritt \(step + 1) von \(Self.stepCount + 1)")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.inkMuted)
                        Spacer(minLength: Spacing.s)
                        if step < Self.stepCount {
                            Button("Später") { finish() }
                                .font(Typography.label)
                                .foregroundStyle(Palette.bioCyan)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                                .accessibilityIdentifier("setup.skipAll")
                        }
                    }
                    content
                    }
                }
                .padding(Spacing.l)
            }
        }
        .onAppear {
            step = min(store.setupStep, Self.stepCount)
            name = store.profile.displayName
        }
        .screenIdentifier("onboarding")
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            page(title: "Willkommen bei PULSE ONE", systemImage: "heart.circle",
                 text: "PULSE ONE sammelt deine Werte vom Ring und aus Apple Health an einem Ort, zeigt Verläufe und deinen persönlichen üblichen Bereich. Alles bleibt auf diesem iPhone. Die App ist kein zugelassenes Medizinprodukt; in der Sprechstunde deutet Claude deine Werte ärztlich.")
            next("Los geht's")
        case 1:
            page(title: "Wie dürfen wir dich nennen?", systemImage: "person",
                 text: "Nur für die Begrüßung. Du kannst das Feld leer lassen.")
            field("Name", text: $name, keyboard: .default)
            next("Weiter")
        case 2:
            page(title: "Ein paar Eckdaten", systemImage: "ruler",
                 text: "Freiwillig. Sie helfen später bei Einordnungen, zum Beispiel beim Energieumsatz.")
            field("Geburtsjahr", text: $birthYear, keyboard: .numberPad)
            field("Größe in cm", text: $height, keyboard: .decimalPad)
            field("Gewicht in kg", text: $weight, keyboard: .decimalPad)
            next("Weiter")
        case 3:
            page(title: "Datenquellen", systemImage: "sensor.tag.radiowaves.forward",
                 text: "Verbinde Apple Health jetzt oder später. Deinen Ring verbindest du jederzeit über den Profil-Knopf oben rechts. PULSE ONE funktioniert auch ganz ohne Gerät.")
            if sources.healthAvailable {
                Button(sources.hasHealth ? "Apple Health ist verbunden" : "Apple Health verbinden", systemImage: "heart.text.square") {
                    Task { await sources.connectHealth() }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(sources.hasHealth)
                .accessibilityIdentifier("setup.health")
            }
            next("Weiter")
        default:
            page(title: "Fertig", systemImage: "checkmark.circle",
                 text: "Unten findest du Heute, Gesundheit, Analyse, Coach und Ernährung. Profil, Geräte und den Ring erreichst du über den Knopf oben rechts.")
            Button("PULSE ONE starten") { finish() }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("setup.finish")
        }
    }

    private func page(title: String, systemImage: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(Palette.bioCyan)
                .accessibilityHidden(true)
            Text(title)
                .font(Typography.title)
                .foregroundStyle(Palette.ink)
                .wraps()
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(Typography.body)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
        }
    }

    private func field(_ title: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        TextField(title, text: text)
            .keyboardType(keyboard)
            .font(Typography.body)
            .foregroundStyle(Palette.ink)
            .padding(Spacing.m)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.surfaceButton))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline))
    }

    private func next(_ title: String) -> some View {
        Button(title) {
            save()
            step += 1
            store.setSetupStep(step)
        }
        .buttonStyle(PrimaryButtonStyle())
        .accessibilityIdentifier("setup.next")
    }

    private func save() {
        store.update {
            $0.displayName = name
            if let year = Int(birthYear.trimmingCharacters(in: .whitespaces)) { $0.birthYear = year }
            if let h = ProfileSheet.number(height) { $0.heightCm = h }
            if let w = ProfileSheet.number(weight) { $0.weightKg = w }
        }
    }

    private func finish() {
        save()
        store.completeSetup()
    }
}
