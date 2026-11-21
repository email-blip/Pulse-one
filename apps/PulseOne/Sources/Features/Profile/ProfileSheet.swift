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
                    TextField("Name", text: $name)
                        .textContentType(.givenName)
                        .accessibilityIdentifier("profile.name")
                    TextField("Geburtsjahr", text: $birthYear)
                        .keyboardType(.numberPad)
                    Picker("Geschlecht", selection: $sex) {
                        ForEach(UserProfile.Sex.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    TextField("Größe in cm", text: $height)
                        .keyboardType(.decimalPad)
                    TextField("Gewicht in kg", text: $weight)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Profil")
                } footer: {
                    Text("Alle Angaben sind freiwillig und bleiben auf diesem iPhone. Sie helfen bei Einordnungen, ersetzen aber keine Untersuchung.")
                }
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
                Section("Analyse") {
                    NavigationLink {
                        IntelligenceSettingsView()
                    } label: {
                        Label("KI-Anbieter", systemImage: "key")
                    }
                }
                Section("App") {
                    Button {
                        save()
                        store.restartSetup()
                        dismiss()
                    } label: {
                        Label("Einrichtung erneut starten", systemImage: "arrow.counterclockwise")
                    }
                    LabeledContent("Version", value: Self.version)
                    Text("PULSE ONE ist kein Medizinprodukt. Die App beschreibt Werte und Verläufe, sie stellt keine Diagnosen.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                }
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
