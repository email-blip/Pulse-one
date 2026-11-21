import PulseCore
import SwiftData
import SwiftUI

/// "KI-Anbieter" in the profile sheet: own Anthropic key (Keychain only), connection test, model,
/// what may be shared, and the monthly brakes (spec §2).
struct IntelligenceSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var engine = IntelligenceEngine()
    @State private var keyInput = ""
    @State private var storedKey: String?
    @State private var status: String?
    @State private var testing = false
    @State private var usage = IntelligenceEngine.MonthUsage(spentUSD: 0, sends: 0)
    @State private var memoryStatus: String?

    private var services: IntelligenceServices { engine.services }

    var body: some View {
        @Bindable var settings = services.settings
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(spacing: Spacing.l) {
                    if LaunchOptions.current.usesTestScenario { TestBanner() }
                    keyCard
                    Card {
                        SectionHeader(title: "Modell")
                        ForEach(ClaudeModel.all) { model in
                            Button { settings.modelID = model.id } label: {
                                HStack(alignment: .top, spacing: Spacing.m) {
                                    Image(systemName: settings.modelID == model.id ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(Palette.bioCyan)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.displayName).font(Typography.label).foregroundStyle(Palette.ink).wraps()
                                        Text(model.note).font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                                    }
                                    Spacer()
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(settings.modelID == model.id ? .isSelected : [])
                        }
                    }
                    Card {
                        SectionHeader(title: "Ärztliche Einschätzung")
                        Toggle(isOn: $settings.clinicalMode) {
                            Text("Claude deutet wie ein Ärzteteam")
                                .font(Typography.body).foregroundStyle(Palette.ink).wraps()
                        }
                        .tint(Palette.bioCyan)
                        .accessibilityIdentifier("intelligence.clinicalMode")
                        Text(settings.clinicalMode
                             ? "Mögliche Diagnosen mit Wahrscheinlichkeit, Abklärung, Training, Reha und Behandlung, ohne Floskeln. Bei Warnzeichen rät die App deutlich zur Abklärung."
                             : "Aus: Claude beschreibt nur Verläufe, ohne Diagnosen und ohne Aussagen zu Behandlung.")
                            .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                        Button("Gedächtnis der Sprechstunde löschen", role: .destructive) { forgetConsultations() }
                            .buttonStyle(SecondaryButtonStyle())
                        if let memoryStatus {
                            Text(memoryStatus).font(Typography.caption).foregroundStyle(Palette.ink).wraps()
                        }
                    }
                    Card {
                        SectionHeader(title: "Was Claude bekommen darf")
                        Text("Nur berechnete Kennzahlen dieser Bereiche. Name, Geräte, Orte und Notiztexte bleiben immer auf dem iPhone.")
                            .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                        ForEach(ConsentCategory.allCases, id: \.self) { category in
                            Toggle(isOn: Binding(get: { settings[consent: category] }, set: { settings[consent: category] = $0 })) {
                                Text(category.title).font(Typography.body).foregroundStyle(Palette.ink).wraps()
                            }
                            .tint(Palette.bioCyan)
                        }
                    }
                    Card {
                        SectionHeader(title: "Monatliche Grenzen")
                        Stepper(value: $settings.monthlyBudgetUSD, in: 1...200, step: 1) {
                            Text("Budget: \(IntelligenceEngine.dollars(settings.monthlyBudgetUSD))")
                                .font(Typography.body).foregroundStyle(Palette.ink).wraps()
                        }
                        Stepper(value: $settings.maxSendsPerMonth, in: 1...300, step: 5) {
                            Text("Höchstens \(settings.maxSendsPerMonth) Sendungen")
                                .font(Typography.body).foregroundStyle(Palette.ink).wraps()
                        }
                        Text("Diesen Monat: \(usage.sends) Sendungen, \(IntelligenceEngine.dollars(usage.spentUSD)) laut den Angaben von Anthropic.")
                            .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                    }
                    Card {
                        SectionHeader(title: "Auf dem iPhone")
                        Toggle(isOn: $settings.useOnDeviceModel) {
                            Text("Kurze Tageszeilen mit Apple Intelligence formulieren, wenn verfügbar")
                                .font(Typography.body).foregroundStyle(Palette.ink).wraps()
                        }
                        .tint(Palette.bioCyan)
                        Text(OnDeviceBrain.isModelAvailable ? "Apple Intelligence ist auf diesem iPhone verfügbar." :
                                "Apple Intelligence ist hier nicht verfügbar. PULSE ONE nutzt feste Sätze.")
                            .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                    }
                }
                .padding(Spacing.l)
            }
        }
        .navigationTitle("KI-Anbieter")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            storedKey = services.secrets.read()
            usage = engine.monthUsage(in: modelContext)
        }
    }

    private var keyCard: some View {
        Card {
            SectionHeader(title: "Dein Claude-Schlüssel")
            if let storedKey, !storedKey.isEmpty {
                Label("Gespeichert: \(storedKey.maskedKey)", systemImage: "key.fill")
                    .font(Typography.body).foregroundStyle(Palette.ink).wraps()
                    .accessibilityIdentifier("intelligence.keyStored")
                Button(testing ? "Prüfe Verbindung …" : "Verbindung prüfen") { testConnection() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(testing)
                Button("Schlüssel löschen", role: .destructive) {
                    services.secrets.delete()
                    self.storedKey = nil
                    status = "Der Schlüssel wurde von diesem iPhone gelöscht."
                }
                .buttonStyle(SecondaryButtonStyle())
            } else {
                Text("Den Schlüssel erstellst du in der Anthropic Console unter „API Keys“. Er beginnt mit „sk-ant-“. Kopiere ihn und füge ihn hier ein, nicht in einen Chat.")
                    .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
                SecureField("sk-ant-…", text: $keyInput)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                    .padding(Spacing.m)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.surfaceButton))
                    .accessibilityIdentifier("intelligence.keyField")
                Button("Speichern und prüfen") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || testing)
            }
            if let status {
                Text(status).font(Typography.caption).foregroundStyle(Palette.ink).wraps()
                    .accessibilityIdentifier("intelligence.keyStatus")
            }
            Text("Der Schlüssel liegt nur im Schlüsselbund dieses iPhones, wird nicht mit iCloud abgeglichen und nie angezeigt oder exportiert. Die Kosten rechnet Anthropic mit deinem Konto ab.")
                .font(Typography.caption).foregroundStyle(Palette.inkMuted).wraps()
        }
    }

    /// Deletes all consultations (conversation and memory) from this iPhone.
    private func forgetConsultations() {
        let all = (try? modelContext.fetch(FetchDescriptor<StoredConsultation>())) ?? []
        for consultation in all { modelContext.delete(consultation) }
        try? modelContext.save()
        memoryStatus = all.isEmpty ? "Es gibt noch keine Sprechstunde." : "Alle Sprechstunden wurden von diesem iPhone gelöscht."
    }

    private func save() {
        let key = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("sk-ant-") else {
            status = "Das sieht nicht wie ein Anthropic-Schlüssel aus. Er beginnt mit „sk-ant-“."
            return
        }
        do {
            try services.secrets.save(key)
            keyInput = ""
            storedKey = key
            testConnection()
        } catch {
            status = "Der Schlüssel konnte nicht im Schlüsselbund gespeichert werden."
        }
    }

    private func testConnection() {
        guard let key = services.secrets.read() else { return }
        testing = true
        status = nil
        let transport = services.transport
        let wanted = services.settings.model
        Task {
            do {
                let available = try await transport.hasModel(wanted.id, apiKey: key)
                status = available
                    ? "Verbunden. \(wanted.displayName) ist für deinen Schlüssel freigeschaltet."
                    : "Verbunden, aber \(wanted.displayName) ist für deinen Schlüssel nicht freigeschaltet. Wähle ein anderes Modell."
            } catch let error as AnthropicError {
                status = error.message
            } catch {
                status = "Die Verbindung hat nicht geklappt."
            }
            testing = false
        }
    }
}
