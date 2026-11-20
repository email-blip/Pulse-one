import PulseCore
import RealityKit
import SwiftData
import SwiftUI

/// Heart Chamber (directive §5.3): a 3D heart that beats with the real heart rate from the ring,
/// with synchronised haptics and optional sound. Rotation by dragging, zoom by pinching.
/// The motion is derived from BPM only and is labelled as such – it is not an ECG.
struct HeartChamberView: View {
    @Environment(RingStore.self) private var ring
    @Environment(\.dismiss) private var dismiss
    @Environment(\.reduceMotionEffective) private var reduceMotion
    @Environment(\.freezeAnimations) private var freeze
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query(filter: #Predicate<StoredMeasurement> { $0.metricRaw == "heart_rate" },
           sort: \StoredMeasurement.timestamp, order: .reverse) private var heartRates: [StoredMeasurement]

    @State private var scene = HeartScene()
    @State private var feedback = HeartFeedback()
    @State private var look: HeartScene.Look = .anatomy
    @State private var yaw: Float = -0.35
    @State private var pitch: Float = 0.08
    @State private var dragStart: (yaw: Float, pitch: Float)?
    @State private var zoom: Float = 1
    @State private var zoomStart: Float?
    @State private var start = Date()
    @AppStorage("heart.haptics") private var hapticsOn = true
    @AppStorage("heart.sound") private var soundOn = false

    private var source: (bpm: Int, live: Bool, date: Date?)? {
        if let live = ring.snapshot.liveHeartRate { return (live, true, nil) }
        if let last = heartRates.first { return (last.value, false, last.timestamp) }
        return nil
    }

    var body: some View {
        let source = source
        let period = source.map { Heartbeat.period(bpm: $0.bpm) } ?? Heartbeat.idlePeriod
        ZStack(alignment: .top) {
            RadialGradient(colors: [Color(hex: 0x14204A), Palette.obsidian], center: .center, startRadius: 20, endRadius: 520)
                .ignoresSafeArea()

            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion || freeze)) { context in
                let t = (reduceMotion || freeze) ? period * 0.22 : context.date.timeIntervalSince(start)
                let phase = Heartbeat.phase(at: t, period: period)
                let contraction = source == nil ? Heartbeat.idle(phase: phase) : Heartbeat.contraction(phase: phase)
                let beatIndex = Int(t / period)
                RealityView { content in
                    content.camera = .virtual
                    content.add(scene.build())
                    let camera = PerspectiveCamera()
                    camera.camera.fieldOfViewInDegrees = 38
                    // Aim below the heart so it sits in the upper half, clear of the controls.
                    camera.look(at: [0, -0.35, 0], from: [0, -0.2, 4.4], relativeTo: nil)
                    content.add(camera)
                } update: { _ in
                    scene.apply(look)
                    scene.pose(contraction, yaw: yaw, pitch: pitch, zoom: zoom)
                }
                .onChange(of: beatIndex) { _, _ in
                    guard source?.live == true, !freeze, scenePhase == .active else { return }
                    feedback.beat(gap: (Heartbeat.dubPhase - Heartbeat.lubPhase) * period,
                                  haptic: hapticsOn, sound: soundOn)
                }
            }
            .gesture(rotate.simultaneously(with: pinch))
            .accessibilityElement()
            .accessibilityLabel("3D-Herz")
            .accessibilityValue(source.map { "schlägt mit \($0.bpm) Schlägen pro Minute" } ?? "ruht, kein Pulswert")
            .accessibilityHint("Mit einem Finger drehen, mit zwei Fingern zoomen")
            .accessibilityIdentifier("heart3d")

            // Scrim keeps the headline readable when the heart is rotated under it.
            LinearGradient(colors: [Palette.obsidian.opacity(0.9), Palette.obsidian.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 240)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            overlay(source)
        }
        .onDisappear { feedback.stop() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.heart")
    }

    private func overlay(_ source: (bpm: Int, live: Bool, date: Date?)?) -> some View {
        VStack(spacing: Spacing.m) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HEART CHAMBER")
                        .font(Typography.motto)
                        .tracking(2)
                        .foregroundStyle(Palette.bioCyan)
                        .wraps()
                    Text(headline(source))
                        .font(Typography.title)
                        .foregroundStyle(Palette.ink)
                        .wraps()
                    Text(detail(source))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .wraps()
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: Spacing.s)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Palette.surfaceButton))
                }
                .accessibilityLabel("Schließen")
                .accessibilityIdentifier("closeHeart")
            }
            if ring.isTestScenario {
                Text("Testansicht – keine echten Messwerte")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.obsidian)
                    .padding(.horizontal, Spacing.m)
                    .padding(.vertical, Spacing.xs)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.iceWhite))
                    .wraps()
                    .accessibilityIdentifier("testBanner")
            }
            Spacer()
            controls
        }
        .padding(Spacing.l)
    }

    private var controls: some View {
        VStack(spacing: Spacing.m) {
            Picker("Darstellung", selection: $look) {
                ForEach(HeartScene.Look.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("lookPicker")
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Spacing.s)) : AnyLayout(HStackLayout(spacing: Spacing.m))
            layout {
                toggle("Haptik", systemImage: "hand.tap", isOn: $hapticsOn, id: "toggleHaptics")
                toggle("Ton", systemImage: "speaker.wave.2", isOn: $soundOn, id: "toggleSound")
            }
            Text("Schematisches Herzmodell, keine anatomische Darstellung. Bewegung aus deinem Pulswert abgeleitet, kein EKG.")
                .font(Typography.caption)
                .foregroundStyle(Palette.inkMuted)
                .multilineTextAlignment(.center)
                .wraps()
        }
        .padding(Spacing.l)
        .background(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).fill(Palette.surfaceRaised))
    }

    /// Toggle as a full-width button: the system button-style toggle keeps a hit area of only the label.
    private func toggle(_ title: String, systemImage: String, isOn: Binding<Bool>, id: String) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Label(title, systemImage: systemImage)
                .font(Typography.label)
                .foregroundStyle(isOn.wrappedValue ? Palette.obsidian : Palette.ink)
                .wraps()
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isOn.wrappedValue ? Palette.bioCyan : Palette.surfaceButton)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn.wrappedValue ? "an" : "aus")
        .accessibilityIdentifier(id)
    }

    private func headline(_ source: (bpm: Int, live: Bool, date: Date?)?) -> String {
        guard let source else { return "Kein Pulswert" }
        return source.live ? "\(source.bpm) bpm · live" : "\(source.bpm) bpm · zuletzt gemessen"
    }

    private func detail(_ source: (bpm: Int, live: Bool, date: Date?)?) -> String {
        guard let source else { return "Verbinde deinen Ring und miss den Puls. Bis dahin ruht das Herz." }
        if source.live { return "Das Herz schlägt im Takt deines Rings." }
        return "Gemessen \(source.date?.formatted(date: .abbreviated, time: .shortened) ?? "") – Herz zeigt diesen Takt."
    }

    private var rotate: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let base = dragStart ?? (yaw, pitch)
                dragStart = base
                yaw = base.yaw + Float(value.translation.width) * 0.01
                pitch = min(0.9, max(-0.9, base.pitch + Float(value.translation.height) * 0.01))
            }
            .onEnded { _ in dragStart = nil }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = zoomStart ?? zoom
                zoomStart = base
                zoom = min(2.2, max(0.6, base * Float(value.magnification)))
            }
            .onEnded { _ in zoomStart = nil }
    }
}
