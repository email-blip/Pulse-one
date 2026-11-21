import CoreTransferable
import PulseCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Milestone "FIRST DEVICE CONNECT": find the Colmi ring, connect, show status,
/// battery and live heart rate, and the stored real values with their origin.
struct ConnectScreen: View {
    let options: LaunchOptions
    @Environment(RingStore.self) private var ring
    @Query(sort: \StoredMeasurement.timestamp, order: .reverse) private var stored: [StoredMeasurement]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.reduceMotionEffective) private var reduceMotion
    @Environment(\.freezeAnimations) private var freeze
    @State private var showHeart = false
    @State private var showDevices = false
    @Environment(SourcesStore.self) private var sources

    var body: some View {
        let snapshot = ring.snapshot
        ZStack {
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.45], [0.5, 0.35], [1, 0.45],
                [0, 1], [0.5, 1], [1, 1]
            ], colors: Palette.mesh)
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Spacing.xl) {
                    header
                    if ring.isTestScenario { testBanner }
                    PulseOrb(bpm: snapshot.liveHeartRate, isConnected: snapshot.connection.isConnected)
                    StatusCard(snapshot: snapshot)
                    if snapshot.measurement != .idle {
                        MeasurementCard(phase: snapshot.measurement, deviceName: snapshot.deviceName)
                    }
                    actions(snapshot)
                    heartEntry
                    devicesEntry
                    if snapshot.connection.isConnected || snapshot.deviceName != nil, snapshot.connection != .scanning {
                        DeviceCard(snapshot: snapshot)
                    }
                    HistoryCard(items: Array(stored.prefix(8)))
                    if !ring.trace.isEmpty { DiagnosticsCard() }
                    footer
                }
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.xl)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(options.scenario ?? "start")")
        .fullScreenCover(isPresented: $showHeart) {
            // Covers start a new presentation: hand over the environment explicitly.
            HeartChamberView()
                .environment(ring)
                .modelContext(modelContext)
                .environment(\.reduceMotionEffective, reduceMotion)
                .environment(\.freezeAnimations, freeze)
                .preferredColorScheme(.dark)
                .modifier(DynamicTypeOverride(size: options.dynamicTypeSize))
        }
        .sheet(isPresented: $showDevices) {
            DevicesScreen()
                .environment(ring)
                .environment(sources)
                .environment(\.reduceMotionEffective, reduceMotion)
                .environment(\.freezeAnimations, freeze)
                .preferredColorScheme(.dark)
                .modifier(DynamicTypeOverride(size: options.dynamicTypeSize))
        }
        .sensoryFeedback(trigger: snapshot.connection.isConnected) { _, connected in
            connected ? .success : nil
        }
    }

    private var header: some View {
        VStack(spacing: Spacing.xs) {
            Text("PULSE ONE")
                .font(Typography.wordmark)
                .tracking(4)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .wraps()
            Text("ONE BODY. MANY WORLDS.")
                .font(Typography.motto)
                .tracking(2)
                .foregroundStyle(Palette.bioCyan)
                .multilineTextAlignment(.center)
                .wraps()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.l)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var testBanner: some View {
        Label("Testansicht für Screenshots – keine echten Messwerte", systemImage: "testtube.2")
            .font(Typography.caption)
            .foregroundStyle(Palette.obsidian)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.iceWhite))
            .accessibilityIdentifier("testBanner")
    }

    @ViewBuilder
    private func actions(_ snapshot: RingSnapshot) -> some View {
        switch snapshot.connection {
        case .ready where snapshot.measurement.isActive:
            Button("Messung beenden", systemImage: "stop.fill") { ring.stopHeartRate() }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("stopMeasure")
        case .ready:
            VStack(spacing: Spacing.m) {
                Button(snapshot.measurement == .idle ? "Puls jetzt messen" : "Erneut messen", systemImage: "heart.fill") {
                    ring.startHeartRate()
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("measure")
                // Second start variant from Gadgetbridge, until the R03 test shows which one it needs.
                Button("Puls messen – Variante B", systemImage: "heart") {
                    ring.startHeartRate(mode: .manual)
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("measureVariantB")
                Button("Trennen", systemImage: "xmark.circle") { ring.disconnect() }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("disconnect")
            }
        case .connecting, .discovering, .reconnecting:
            Button("Abbrechen", systemImage: "xmark") { ring.disconnect() }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("cancel")
        case .scanning:
            ScanResults()
        case .idle, .disconnected, .failed:
            VStack(spacing: Spacing.m) {
                Button("Ring suchen", systemImage: "dot.radiowaves.left.and.right") { ring.startScan() }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("scan")
                if let remembered = snapshot.rememberedRing {
                    Button("Erneut verbinden mit \(remembered)", systemImage: "arrow.clockwise") { ring.reconnectRemembered() }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("reconnect")
                }
                if !snapshot.discovered.isEmpty { ScanResults() }
            }
        }
    }

    private var heartEntry: some View {
        Button("Heart Chamber öffnen", systemImage: "heart.circle") { showHeart = true }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityHint("Zeigt ein 3D-Herz im Takt deines Pulses")
            .accessibilityIdentifier("openHeart")
    }

    private var devicesEntry: some View {
        Button("Geräte & Datenquellen", systemImage: "sensor.tag.radiowaves.forward") { showDevices = true }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("openDevices")
    }

    private var footer: some View {
        Text("PULSE ONE ist kein Medizinprodukt. Werte beschreiben Trends, keine Befunde. Alle Daten bleiben auf diesem iPhone.")
            .font(Typography.caption)
            .foregroundStyle(Palette.inkMuted)
            .multilineTextAlignment(.center)
            .wraps()
            .frame(maxWidth: .infinity)
    }
}

private struct StatusCard: View {
    let snapshot: RingSnapshot

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(snapshot.connection.label)
                        .font(Typography.title)
                        .foregroundStyle(Palette.ink)
                        .wraps()
                        .accessibilityIdentifier("status")
                    Text(snapshot.bluetooth.label)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .wraps()
                }
            }
            if let error = snapshot.lastError {
                Text(error)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.pulseCoral)
                    .wraps()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch snapshot.connection {
        case .ready: Palette.bioCyan
        case .failed, .reconnecting: Palette.pulseCoral
        default: Palette.neuralViolet
        }
    }
}

/// One live measurement, in the order the directive asks for: requested → running → value
/// received / failed / connection lost. A value always shows unit, time and source.
private struct MeasurementCard: View {
    let phase: MeasurementPhase
    let deviceName: String?

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                if phase.isActive && phase.value == nil {
                    ProgressView().tint(Palette.bioCyan).accessibilityHidden(true)
                } else {
                    Image(systemName: icon).foregroundStyle(tint).accessibilityHidden(true)
                }
                Text(phase.title)
                    .font(Typography.title)
                    .foregroundStyle(Palette.ink)
                    .wraps()
                    .accessibilityIdentifier("measurementPhase")
            }
            if let value = phase.value {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text("\(value.bpm)")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(Palette.ink)
                    Text("Schläge/min")
                        .font(Typography.label)
                        .foregroundStyle(Palette.inkMuted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(value.bpm) Schläge pro Minute")
                Text("gemessen \(value.at.formatted(date: .omitted, time: .standard)) · Quelle: \(deviceName.map(spoken) ?? "Ring"), Live-Messung")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
            }
            Text(phase.detail)
                .font(Typography.caption)
                .foregroundStyle(isFailure ? Palette.pulseCoral : Palette.inkMuted)
                .wraps()
            if isFailure {
                Text("Tipp: Unten „Bluetooth-Diagnose teilen“ antippen und die Datei an Claude schicken.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("measurementCard")
    }

    private var isFailure: Bool {
        switch phase {
        case .failed, .connectionLost: true
        default: false
        }
    }

    private var icon: String {
        switch phase {
        case .failed, .connectionLost: "exclamationmark.triangle.fill"
        case .finished, .receiving: "heart.fill"
        default: "heart"
        }
    }

    private var tint: Color { isFailure ? Palette.pulseCoral : Palette.bioCyan }
}

/// Export of the Bluetooth conversation for diagnosis on the real ring.
private struct DiagnosticsCard: View {
    @Environment(RingStore.self) private var ring

    var body: some View {
        Card {
            Text("Bluetooth-Diagnose")
                .font(Typography.title)
                .foregroundStyle(Palette.ink)
                .wraps()
            Text("\(ring.trace.entries.count) Einträge seit App-Start. Enthält die Rohdaten vom Ring (auch Pulswerte), aber keine Geräte-ID. Wird nur geteilt, wenn du es tust.")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .wraps()
            ShareLink(item: DiagnosticFile(text: ring.diagnosticReport()),
                      preview: SharePreview("PULSE ONE Bluetooth-Diagnose")) {
                Label("Bluetooth-Diagnose teilen", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("shareDiagnostics")
            Button("Diagnose leeren", systemImage: "trash") { ring.clearTrace() }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("clearDiagnostics")
        }
        .accessibilityIdentifier("diagnosticsCard")
    }
}

/// The diagnosis as a .txt file in the share sheet (Mail, Dateien, Nachrichten, Claude).
struct DiagnosticFile: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { file in Data(file.text.utf8) }
            .suggestedFileName("PULSE-ONE-Diagnose.txt")
    }
}

private struct ScanResults: View {
    @Environment(RingStore.self) private var ring

    var body: some View {
        @Bindable var ring = ring
        Card {
            HStack {
                Text("Gefundene Ringe")
                    .font(Typography.title)
                    .foregroundStyle(Palette.ink)
                    .wraps()
                Spacer()
                if ring.snapshot.connection == .scanning {
                    ProgressView().tint(Palette.bioCyan)
                }
            }
            if ring.visibleRings.isEmpty {
                Text("Noch kein Ring gefunden. Ring aus der Ladeschale nehmen, kurz bewegen und die QRing-App schließen.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
            }
            ForEach(ring.visibleRings) { found in
                Button { ring.connect(found) } label: {
                    HStack(spacing: Spacing.m) {
                        Image(systemName: "circle.circle")
                            .foregroundStyle(Palette.bioCyan)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(found.name).font(Typography.body).foregroundStyle(Palette.ink).wraps()
                            Text([found.model.map { "Colmi \($0.name)" }, found.signalLabel].compactMap { $0 }.joined(separator: " · "))
                                .font(Typography.caption)
                                .foregroundStyle(Palette.inkMuted)
                                .wraps()
                        }
                        Spacer()
                        Text("Verbinden")
                            .font(Typography.label)
                            .foregroundStyle(Palette.bioCyan)
                            .fixedSize()
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(spoken(found.name)), \(found.model.map { "Colmi \($0.name)" } ?? "unbekanntes Gerät"), \(found.signalLabel)")
                .accessibilityHint("Verbinden")
                .accessibilityIdentifier("ring.\(found.name)")
            }
            Toggle(isOn: $ring.showAllDevices) {
                Text("Alle Bluetooth-Geräte zeigen")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.ink)
                    .wraps()
            }
            .tint(Palette.bioCyan)
            if ring.snapshot.connection == .scanning {
                Button("Suche stoppen") { ring.stopScan() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

private struct DeviceCard: View {
    let snapshot: RingSnapshot
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Card {
            Text(snapshot.deviceName ?? "Ring")
                .font(Typography.title)
                .foregroundStyle(Palette.ink)
                .wraps()
                .accessibilityLabel("Ring \(spoken(snapshot.deviceName ?? ""))")
            row("Modell", snapshot.model.map { "Colmi \($0.name) (am Namen erkannt)" } ?? "unbekannt")
            row("Firmware", snapshot.firmwareNote ?? "wird gelesen …")
            row("Akku", snapshot.battery.map { "\($0.level) %" + ($0.charging ? " · lädt" : "") } ?? "–")
            Divider().overlay(Palette.hairline)
            Text("Fähigkeiten")
                .font(Typography.label)
                .foregroundStyle(Palette.ink)
                .wraps()
            ForEach(Metric.allCases, id: \.self) { metric in
                row(metric.title, snapshot.capabilities.level(of: metric)?.label ?? "–")
            }
            if !snapshot.unknownPackets.isEmpty {
                Text("\(snapshot.unknownPackets.count) unbekannte Antworten vom Ring protokolliert")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
            }
        }
        .accessibilityIdentifier("deviceCard")
    }

    /// Side by side at normal sizes, stacked at accessibility sizes (no truncation either way).
    private func row(_ title: String, _ value: String) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.m))
        return layout {
            Text(title).foregroundStyle(Palette.inkMuted).wraps()
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Text(value).foregroundStyle(Palette.ink)
                .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                .wraps()
        }
        .font(Typography.body)
        .accessibilityElement(children: .combine)
    }
}

private struct HistoryCard: View {
    let items: [StoredMeasurement]

    var body: some View {
        Card {
            Text("Gespeicherte Werte")
                .font(Typography.title)
                .foregroundStyle(Palette.ink)
                .wraps()
            if items.isEmpty {
                Text("Noch keine echten Messwerte. Verbinde deinen Ring und miss den Puls.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .wraps()
            }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(item.metric?.title ?? item.metricRaw): \(item.value) \(item.unit)")
                        .font(Typography.body)
                        .foregroundStyle(Palette.ink)
                        .wraps()
                    Text("\(item.timestamp.formatted(date: .abbreviated, time: .shortened)) · \(item.deviceName) · live gemessen")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .wraps()
                }
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier("history")
    }
}

/// BLE names like "R03_1A2B" read badly with VoiceOver; speak them with spaces.
func spoken(_ name: String) -> String {
    name.replacingOccurrences(of: "_", with: " ")
}
