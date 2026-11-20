import PulseCore
import SwiftUI

/// DEVICES (General Directive 3.0 §4 "Geräteverwaltung"): every data source with its real
/// integration stage, battery, sync state, supported values and diagnosis. A Bluetooth connection
/// alone never shows as a finished integration.
struct DevicesScreen: View {
    @Environment(SourcesStore.self) private var sources
    @Environment(RingStore.self) private var ring
    @Environment(\.dismiss) private var dismiss
    var showsClose = true
    @State private var renaming: RegisteredDevice?
    @State private var newName = ""

    var body: some View {
        ZStack {
            Palette.obsidian.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    header
                    if sources.isTestScenario { testBanner }
                    if sources.devices.isEmpty {
                        Card {
                            Text("Noch keine Geräte. Füge deinen Ring oder Apple Health hinzu.")
                                .font(Typography.body)
                                .foregroundStyle(Palette.ink)
                                .wraps()
                        }
                    }
                    ForEach(sources.devices) { device in
                        DeviceSourceCard(device: device, syncing: sources.syncing.contains(device.id),
                                         onSync: { Task { await sources.sync(device.id) } },
                                         onRename: { newName = device.name; renaming = device },
                                         onRemove: { sources.remove(device.id) })
                    }
                    if !sources.devices.isEmpty { PreferredSourcesCard() }
                    addButtons
                    Text("Stufen: entdeckt → verbunden → kompatibel → Datenzugriff → synchronisiert → Qualität geprüft. Eine Bluetooth-Verbindung allein ist noch keine fertige Anbindung.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .wraps()
                }
                .padding(Spacing.l)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.devices")
        .alert("Gerät umbenennen", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Sichern") { if let renaming { sources.rename(renaming.id, to: newName) } }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("DEVICES")
                    .font(Typography.motto)
                    .tracking(2)
                    .foregroundStyle(Palette.bioCyan)
                    .wraps()
                Text("Geräte & Datenquellen")
                    .font(Typography.title)
                    .foregroundStyle(Palette.ink)
                    .wraps()
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.s)
            if showsClose {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Palette.surfaceButton))
                }
                .accessibilityLabel("Schließen")
                .accessibilityIdentifier("closeDevices")
            }
        }
    }

    private var testBanner: some View {
        Text("Testansicht – keine echten Geräte")
            .font(Typography.caption)
            .foregroundStyle(Palette.obsidian)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.iceWhite))
            .wraps()
            .accessibilityIdentifier("testBanner")
    }

    private var addButtons: some View {
        VStack(spacing: Spacing.m) {
            Button("Ring hinzufügen", systemImage: "dot.radiowaves.left.and.right") {
                ring.startScan()
                dismiss()
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("addRing")
            if !sources.hasHealth {
                Button("Apple Health verbinden", systemImage: "heart.text.square") {
                    Task { await sources.connectHealth() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!sources.healthAvailable)
                .accessibilityIdentifier("connectHealth")
            }
        }
    }
}

private struct DeviceSourceCard: View {
    let device: RegisteredDevice
    let syncing: Bool
    let onSync: () -> Void
    let onRename: () -> Void
    let onRemove: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(SourcesStore.self) private var sources
    @Environment(RingStore.self) private var ring
    @State private var imported: [SourcesStore.ImportedKind] = []

    private var adapter: AdapterDescriptor? { AdapterCatalog.descriptor(id: device.adapterID) }

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(Typography.title)
                        .foregroundStyle(Palette.ink)
                        .wraps()
                        .accessibilityLabel("Gerät \(spoken(device.name))")
                    Text(adapter?.title ?? device.adapterID)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .wraps()
                }
                Spacer(minLength: Spacing.s)
                Menu {
                    Button("Umbenennen", systemImage: "pencil", action: onRename)
                    Button("Entfernen", systemImage: "trash", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Aktionen für \(spoken(device.name))")
            }
            StageTrack(stage: device.stage)
            if isRing { ringConnection }
            facts
            if device.syncedWithoutData && device.adapterID == AdapterCatalog.appleHealth.id { healthHint }
            storedData
            if !device.typeReports.isEmpty { typeReports }
            if let adapter { kinds(adapter) }
            if !device.diagnostics.isEmpty {
                Text(device.diagnostics.suffix(2).joined(separator: "\n"))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
                    .accessibilityLabel("Diagnose: \(device.diagnostics.suffix(2).joined(separator: ". "))")
            }
            if device.adapterID == AdapterCatalog.appleHealth.id {
                Button(syncing ? "Synchronisiere …" : "Jetzt synchronisieren", systemImage: "arrow.triangle.2.circlepath",
                       action: onSync)
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(syncing)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("device.\(device.adapterID)")
        .task(id: device.lastSuccessfulSync) { imported = sources.importedData(deviceID: device.sourceIdentifier) }
    }

    private var isRing: Bool { device.adapterID.hasPrefix("colmi.") }
    private var isThisRingActive: Bool { ring.snapshot.deviceIdentifier == device.sourceIdentifier }

    /// Connect or disconnect this ring. The connection state comes from the ring itself, never from the registry.
    private var ringConnection: some View {
        let state = isThisRingActive ? ring.snapshot.connection : .idle
        return VStack(alignment: .leading, spacing: Spacing.s) {
            fact("Verbindung", state.label)
            if state.isConnected {
                Button("Trennen", systemImage: "link.badge.minus") { ring.disconnect() }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("disconnect.\(device.adapterID)")
            } else if !state.isBusy {
                Button("Verbinden", systemImage: "link") { ring.connect(identifier: device.sourceIdentifier) }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("connect.\(device.adapterID)")
            }
        }
    }

    private var healthHint: some View {
        Text("Apple Health hat keine Werte geliefert. Prüfe in der Health-App unter Teilen › Apps › PULSE ONE, ob das Lesen erlaubt ist, und synchronisiere dann erneut. Ohne Apple Watch liefert Health nur iPhone-Werte wie Schritte; Puls, SpO₂, HRV und Schlaf kommen vom Ring.")
            .font(Typography.caption)
            .foregroundStyle(Palette.ink)
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.bioCyan, lineWidth: 1))
            .wraps()
            .accessibilityIdentifier("healthPermissionHint")
    }

    /// Transparent view of what is stored from this source (Directive 3.1 C/D).
    private var storedData: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Gespeicherte Werte")
                .font(Typography.label)
                .foregroundStyle(Palette.ink)
                .wraps()
            if imported.isEmpty {
                Text("Noch keine gespeicherten Werte von dieser Quelle.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
            }
            ForEach(imported) { item in
                fact(item.kind.title, "\(item.count) · zuletzt \(item.latest?.formatted(date: .abbreviated, time: .shortened) ?? "–")")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("storedData.\(device.adapterID)")
    }

    /// What the last sync read per data type, including types that could not be read.
    private var typeReports: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Letzter Abgleich je Datentyp")
                .font(Typography.label)
                .foregroundStyle(Palette.ink)
                .wraps()
            ForEach(device.typeReports) { report in
                fact(report.kind.title, report.summary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("typeReports.\(device.adapterID)")
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let battery = device.batteryPercent { fact("Akku", "\(battery) %") }
            if let firmware = device.firmware { fact("Firmware", firmware) }
            fact("Letzte Synchronisierung", device.lastSuccessfulSync?.formatted(date: .abbreviated, time: .shortened) ?? "noch nie")
            fact("Letzter Messwert", device.lastSampleAt?.formatted(date: .abbreviated, time: .shortened) ?? "noch keiner")
        }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                                                  : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        return layout {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
            if !typeSize.isAccessibilitySize { Spacer(minLength: Spacing.s) }
            Text(value)
                .font(Typography.label)
                .foregroundStyle(Palette.ink)
                .wraps()
        }
        .accessibilityElement(children: .combine)
    }

    static func symbol(for status: SupportStatus) -> String {
        switch status {
        case .confirmed: "checkmark.circle.fill"
        case .implementedUntested: "hourglass.circle"
        case .protocolUnknown: "questionmark.circle"
        case .planned, .unsupported: "circle.dashed"
        }
    }

    private func kinds(_ adapter: AdapterDescriptor) -> some View {
        let listed = SampleKind.allCases.filter { adapter.status(of: $0) != .unsupported }
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Messwerte")
                .font(Typography.label)
                .foregroundStyle(Palette.ink)
                .wraps()
            ForEach(listed, id: \.self) { kind in
                let status = adapter.status(of: kind)
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                    // Symbol follows the evidence level: only "bestätigt" gets a check mark.
                    Image(systemName: Self.symbol(for: status))
                        .foregroundStyle(status == .confirmed ? Palette.bioCyan : Palette.inkMuted)
                        .accessibilityHidden(true)
                    Text("\(kind.title): \(status.label)")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.ink)
                        .wraps()
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Six-step progress of an integration; filled up to the reached stage.
private struct StageTrack: View {
    let stage: IntegrationStage

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: 4) {
                ForEach(IntegrationStage.allCases, id: \.self) { step in
                    Capsule()
                        .fill(step <= stage ? Palette.bioCyan : Palette.hairline)
                        .frame(height: 6)
                }
            }
            .accessibilityHidden(true)
            Text(stage.label)
                .font(Typography.label)
                .foregroundStyle(Palette.bioCyan)
                .wraps()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stufe \(stage.rawValue + 1) von 6: \(stage.label)")
    }
}

/// Geräte → Datenquellen → Bevorzugte Quelle (Review 3.2 §4). One choice per kind; "Automatisch" follows
/// the documented order for that kind and falls back when the chosen source has no data.
private struct PreferredSourcesCard: View {
    @Environment(SourcesStore.self) private var sources

    private var kinds: [SampleKind] {
        SampleKind.allCases.filter { $0 != .deviceBattery && !sources.candidates(for: $0).isEmpty }
    }

    var body: some View {
        Card {
            Text("Bevorzugte Quellen")
                .font(Typography.title)
                .foregroundStyle(Palette.ink)
                .wraps()
                .accessibilityAddTraits(.isHeader)
            Text("Pro Messwert zählt immer nur eine Quelle, nichts wird doppelt gezählt. Fehlt die gewählte Quelle, springt die automatische Reihenfolge ein.")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
            ForEach(kinds, id: \.self) { kind in
                row(kind)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("preferredSources")
    }

    private func row(_ kind: SampleKind) -> some View {
        let candidates = sources.candidates(for: kind)
        let selection = Binding(get: { sources.preferences.choice(for: kind) },
                                set: { sources.setPreference($0, for: kind) })
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(kind.title)
                .font(Typography.label)
                .foregroundStyle(Palette.ink)
                .wraps()
            Picker(kind.title, selection: selection) {
                Text("Automatisch").tag(SourceChoice.automatic)
                ForEach(candidates.indices, id: \.self) { i in
                    Text(candidates[i].title).tag(candidates[i].choice)
                }
            }
            .pickerStyle(.menu)
            .tint(Palette.bioCyan)
            .accessibilityLabel("Bevorzugte Quelle für \(kind.title)")
            .accessibilityIdentifier("preference.\(kind.rawValue)")
            Text("Automatisch: \(SourcePolicy.automaticOrder(for: kind, context: .general).prefix(3).map(\.title).joined(separator: " › "))")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
        }
        .padding(.top, Spacing.xs)
    }
}
