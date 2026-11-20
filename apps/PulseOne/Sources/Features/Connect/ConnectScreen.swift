import PulseCore
import SwiftData
import SwiftUI

/// Milestone "FIRST DEVICE CONNECT": find the Colmi ring, connect, show status,
/// battery and live heart rate, and the stored real values with their origin.
struct ConnectScreen: View {
    let options: LaunchOptions
    @Environment(RingStore.self) private var ring
    @Query(sort: \StoredMeasurement.timestamp, order: .reverse) private var stored: [StoredMeasurement]

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
                    actions(snapshot)
                    if snapshot.connection.isConnected || snapshot.deviceName != nil, snapshot.connection != .scanning {
                        DeviceCard(snapshot: snapshot)
                    }
                    HistoryCard(items: Array(stored.prefix(8)))
                    footer
                }
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.xl)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.\(options.scenario ?? "start")")
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
            Text("ONE BODY. MANY WORLDS.")
                .font(Typography.motto)
                .tracking(2)
                .foregroundStyle(Palette.bioCyan)
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
            .background(Capsule().fill(Palette.iceWhite))
            .accessibilityIdentifier("testBanner")
    }

    @ViewBuilder
    private func actions(_ snapshot: RingSnapshot) -> some View {
        switch snapshot.connection {
        case .ready:
            VStack(spacing: Spacing.m) {
                Button("Puls jetzt messen", systemImage: "heart.fill") { ring.startHeartRate() }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("measure")
                Button("Trennen", systemImage: "xmark.circle") { ring.disconnect() }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("disconnect")
            }
        case .measuring:
            VStack(spacing: Spacing.m) {
                Button("Messung beenden", systemImage: "stop.fill") { ring.stopHeartRate() }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("stopMeasure")
                Text("Ring ruhig halten. Die Messung endet nach einer Minute von selbst.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
                    .multilineTextAlignment(.center)
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

    private var footer: some View {
        Text("PULSE ONE ist kein Medizinprodukt. Werte beschreiben Trends, keine Befunde. Alle Daten bleiben auf diesem iPhone.")
            .font(Typography.caption)
            .foregroundStyle(Palette.inkMuted)
            .multilineTextAlignment(.center)
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
                        .accessibilityIdentifier("status")
                    Text(snapshot.bluetooth.label)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                }
            }
            if let error = snapshot.lastError {
                Text(error)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.pulseCoral)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch snapshot.connection {
        case .ready, .measuring: Palette.bioCyan
        case .failed, .reconnecting: Palette.pulseCoral
        default: Palette.neuralViolet
        }
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
                Spacer()
                if ring.snapshot.connection == .scanning {
                    ProgressView().tint(Palette.bioCyan)
                }
            }
            if ring.visibleRings.isEmpty {
                Text("Noch kein Ring gefunden. Ring aus der Ladeschale nehmen, kurz bewegen und die QRing-App schließen.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
            }
            ForEach(ring.visibleRings) { found in
                Button { ring.connect(found) } label: {
                    HStack(spacing: Spacing.m) {
                        Image(systemName: "circle.circle")
                            .foregroundStyle(Palette.bioCyan)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(found.name).font(Typography.body).foregroundStyle(Palette.ink)
                            Text([found.model.map { "Colmi \($0.name)" }, found.signalLabel].compactMap { $0 }.joined(separator: " · "))
                                .font(Typography.caption)
                                .foregroundStyle(Palette.inkMuted)
                        }
                        Spacer()
                        Text("Verbinden")
                            .font(Typography.label)
                            .foregroundStyle(Palette.bioCyan)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ring.\(found.name)")
            }
            Toggle("Alle Bluetooth-Geräte zeigen", isOn: $ring.showAllDevices)
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
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

    var body: some View {
        Card {
            Text(snapshot.deviceName ?? "Ring")
                .font(Typography.title)
                .foregroundStyle(Palette.ink)
            row("Modell", snapshot.model.map { "Colmi \($0.name) (am Namen erkannt)" } ?? "unbekannt")
            row("Firmware", snapshot.firmwareNote ?? "wird gelesen …")
            row("Akku", snapshot.battery.map { "\($0.level) %" + ($0.charging ? " · lädt" : "") } ?? "–")
            Divider().overlay(Palette.hairline)
            Text("Fähigkeiten")
                .font(Typography.label)
                .foregroundStyle(Palette.ink)
            ForEach(Metric.allCases, id: \.self) { metric in
                row(metric.title, snapshot.capabilities.level(of: metric)?.label ?? "–")
            }
            if !snapshot.unknownPackets.isEmpty {
                Text("\(snapshot.unknownPackets.count) unbekannte Antworten vom Ring protokolliert")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
            }
        }
        .accessibilityIdentifier("deviceCard")
    }

    private func row(_ title: String, _ value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).foregroundStyle(Palette.inkMuted)
                Spacer()
                Text(value).foregroundStyle(Palette.ink).multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Palette.inkMuted)
                Text(value).foregroundStyle(Palette.ink)
            }
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
            if items.isEmpty {
                Text("Noch keine echten Messwerte. Verbinde deinen Ring und miss den Puls.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.inkMuted)
            }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(item.metric?.title ?? item.metricRaw): \(item.value) \(item.unit)")
                        .font(Typography.body)
                        .foregroundStyle(Palette.ink)
                    Text("\(item.timestamp.formatted(date: .abbreviated, time: .shortened)) · \(item.deviceName) · live gemessen")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier("history")
    }
}
