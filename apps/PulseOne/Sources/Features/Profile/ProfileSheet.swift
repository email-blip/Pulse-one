import PulseCore
import SwiftUI

/// DEVICES & SETTINGS (DESIGN-SYSTEM-5.0 §2): profile, ring, devices, AI provider and setup, opened
/// from the profile button of every tab.
struct ProfileSheet: View {
    let options: LaunchOptions
    @Environment(ProfileStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var birthYear = ""
    @State private var height = ""
    @State private var weight = ""
    @State private var sex: UserProfile.Sex = .undisclosed

    var body: some View {
        NavigationStack {
            Form {
                if options.usesTestScenario {
                    Section { TestBanner().listRowBackground(Color.clear) }
                }
                Section {
                    TextField("Name", text: $name, prompt: Text("Name").foregroundStyle(Palette.inkMuted))
                        .textContentType(.givenName)
                        .accessibilityIdentifier("profile.name")
                    TextField("Geburtsjahr", text: $birthYear, prompt: Text("Geburtsjahr").foregroundStyle(Palette.inkMuted))
                        .keyboardType(.numberPad)
                    Picker("Geschlecht", selection: $sex) {
                        ForEach(UserProfile.Sex.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    // A pushed list in the app's colours instead of the grey system pop-up menu (design review).
                    .pickerStyle(.navigationLink)
                    TextField("Größe in cm", text: $height, prompt: Text("Größe in cm").foregroundStyle(Palette.inkMuted))
                        .keyboardType(.decimalPad)
                    TextField("Gewicht in kg", text: $weight, prompt: Text("Gewicht in kg").foregroundStyle(Palette.inkMuted))
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Profil")
                } footer: {
                    Text("Alle Angaben sind freiwillig und bleiben auf diesem iPhone. Sie helfen bei Einordnungen, ersetzen aber keine Untersuchung.")
                }
                .listRowBackground(Palette.surfaceRaised)
                Section("Geräte") {
                    NavigationLink {
                        ConnectScreen(options: options)
                    } label: {
                        Label("Ring verbinden und messen", systemImage: "circle.circle")
                    }
                    .accessibilityIdentifier("profile.ring")
                    NavigationLink {
                        DevicesScreen(showsClose: false)
                    } label: {
                        Label("Geräte und Datenquellen", systemImage: "sensor.tag.radiowaves.forward")
                    }
                    .accessibilityIdentifier("profile.devices")
                }
                .listRowBackground(Palette.surfaceRaised)
                Section("Analyse") {
                    NavigationLink {
                        IntelligenceSettingsView()
                    } label: {
                        Label("KI-Anbieter", systemImage: "key")
                    }
                }
                .listRowBackground(Palette.surfaceRaised)
                Section("App") {
                    Button {
                        save()
                        store.restartSetup()
                        dismiss()
                    } label: {
                        Label("Einrichtung erneut starten", systemImage: "arrow.counterclockwise")
                    }
                    LabeledContent("Version", value: Self.version)
                    Text("PULSE ONE ist kein zugelassenes Medizinprodukt. Einschätzungen und mögliche Diagnosen von Claude beruhen auf den Messwerten von Ring und Uhr.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                }
                .listRowBackground(Palette.surfaceRaised)
            }
            .scrollContentBackground(.hidden)
            .background(ScreenBackground())
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        save()
                        dismiss()
                    }
                    .accessibilityIdentifier("profile.done")
                }
            }
            .onAppear(perform: load)
            // Swiping the sheet down keeps the edits as well; there is no cancel button that promises otherwise.
            .onDisappear(perform: save)
        }
        .screenIdentifier("profile")
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private func load() {
        let p = store.profile
        name = p.displayName
        birthYear = p.birthYear.map(String.init) ?? ""
        height = p.heightCm.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? ""
        weight = p.weightKg.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? ""
        sex = p.sex ?? .undisclosed
    }

    private func save() {
        store.update {
            $0.displayName = name
            $0.birthYear = Int(birthYear.trimmingCharacters(in: .whitespaces))
            $0.heightCm = Self.number(height)
            $0.weightKg = Self.number(weight)
            $0.sex = sex
        }
    }

    /// Accepts "78,5" and "78.5".
    static func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
}
