import PulseCore
import SwiftUI
import Vision
import VisionKit

/// Barcode scan with VisionKit's DataScannerViewController (Apple framework, no dependency).
/// Without a camera (simulator, permission refused) the digits can be typed in.
/// Only the barcode number goes to Open Food Facts.
struct BarcodeScanView: View {
    let defaultDate: Date
    var onDone: () -> Void

    @Environment(NutritionStore.self) private var store
    @State private var phase = Phase.scanning
    @State private var manualCode = ""
    @State private var found: FoodItem?
    @State private var customBarcode: String?

    enum Phase: Equatable {
        case scanning
        case loading(String)
        case notFound(String)
        case failed(String)
    }

    private var scannerAvailable: Bool {
        !store.isTestScenario && DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if store.isTestScenario { TestBanner() }
                    if scannerAvailable, phase == .scanning {
                        BarcodeScanner { code in Task { await handle(code) } }
                            .frame(height: 320)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                            .accessibilityLabel("Kamerabild für den Barcode")
                        Text("Halte den Barcode auf der Verpackung in den Rahmen.")
                            .font(Typography.body)
                            .foregroundStyle(Palette.ink)
                            .wraps()
                    } else if phase == .scanning {
                        Card {
                            Text("Die Kamera ist hier nicht verfügbar. Du kannst die Ziffern unter dem Barcode eintippen.")
                                .font(Typography.body)
                                .foregroundStyle(Palette.ink)
                                .wraps()
                        }
                    }
                    status
                    manualEntry
                    Text(store.onlineLookup
                         ? "Gesendet wird nur die Barcode-Nummer an Open Food Facts. Gefundene Produkte werden auf diesem iPhone gespeichert."
                         : "Online-Suche ist ausgeschaltet: Es werden nur bei dir gespeicherte Produkte gefunden.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                        .wraps()
                }
                .padding(Spacing.l)
            }
            .background(ScreenBackground())
            .navigationTitle("Barcode scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen", action: onDone) }
            }
            .navigationDestination(item: $found) { food in
                PortionView(food: food, method: .barcode, defaultDate: defaultDate, onDone: onDone)
            }
            .navigationDestination(item: $customBarcode) { code in
                CustomFoodView(barcode: code, defaultDate: defaultDate, onDone: onDone)
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch phase {
        case .scanning:
            EmptyView()
        case .loading(let code):
            Card {
                HStack(spacing: Spacing.m) {
                    ProgressView()
                    Text("Suche Barcode \(code) …").font(Typography.body).foregroundStyle(Palette.ink)
                }
            }
        case .notFound(let code):
            Card {
                Text("Open Food Facts kennt den Barcode \(code) nicht.")
                    .font(Typography.body).foregroundStyle(Palette.ink).wraps()
                Button("Selbst anlegen") { customBarcode = code }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Erneut scannen") { phase = .scanning }
                    .buttonStyle(SecondaryButtonStyle())
            }
        case .failed(let message):
            Card {
                Text(message).font(Typography.body).foregroundStyle(Palette.ink).wraps()
                Button("Erneut versuchen") { phase = .scanning }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var manualEntry: some View {
        Card {
            Text("Barcode eintippen")
                .font(Typography.label)
                .foregroundStyle(Palette.inkMuted)
            TextField("z. B. 4006381333931", text: $manualCode)
                .keyboardType(.numberPad)
                .font(Typography.body)
                .padding(Spacing.m)
                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surfaceButton))
                .accessibilityIdentifier("nutrition.barcodeField")
            Button("Suchen") { Task { await handle(manualCode) } }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(manualCode.count < 8)
        }
    }

    private func handle(_ code: String) async {
        if case .loading = phase { return }
        phase = .loading(code)
        switch await store.lookup(barcode: code) {
        case .found(let food):
            phase = .scanning
            found = food
        case .notFound(let code):
            phase = .notFound(code)
        case .failed(let message):
            phase = .failed(message)
        }
    }
}

/// Wraps DataScannerViewController; reports each new EAN/UPC once via the `recognizedItems` stream.
private struct BarcodeScanner: UIViewControllerRepresentable {
    var onCode: (String) -> Void

    final class Coordinator {
        var task: Task<Void, Never>?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced, recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false, isGuidanceEnabled: true, isHighlightingEnabled: true)
        let stream = scanner.recognizedItems
        let report = onCode
        context.coordinator.task = Task { @MainActor in
            var reported = Set<String>()
            for await items in stream {
                for item in items {
                    if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue,
                       reported.insert(payload).inserted {
                        report(payload)
                    }
                }
            }
        }
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        coordinator.task?.cancel()
        scanner.stopScanning()
    }
}
