import Foundation

/// Descriptors of the adapters PULSE ONE knows today. Statuses mirror the capability matrix in
/// docs/pulse-one-coordination/VERIFIKATION-GD3.md and must be raised only with evidence.
public enum AdapterCatalog {
    public static let colmiR03 = AdapterDescriptor(
        id: "colmi.r03", title: "Colmi R03", category: .smartRing,
        supportedDevices: ["Colmi R03 (R02-Protokoll)"],
        connection: .bluetoothLE, requiredPermissions: ["Bluetooth"], needsPairing: false,
        kinds: [
            .heartRate: .implementedUntested,
            .deviceBattery: .implementedUntested,
            .steps: .implementedUntested,
            .distance: .implementedUntested,
            .oxygenSaturation: .implementedUntested,
            .ringHRV: .implementedUntested,
            .ringStress: .implementedUntested,
            .sleepDuration: .implementedUntested,
            .skinTemperature: .unsupported
        ],
        supportsHistory: .implementedUntested, supportsLive: .implementedUntested, reconnects: true,
        firmwareNote: "Firmware wird gelesen; getestete Versionen in TestedFirmware.",
        knownLimitations: ["Nur eine Verbindung gleichzeitig: QRing-App schließen.", "Ringspeicher etwa 7 Tage."]
    )

    /// Prepared only: same vendor protocol is likely but unproven until the ring arrives.
    public static let colmiR09 = AdapterDescriptor(
        id: "colmi.r09", title: "Colmi R09", category: .smartRing,
        supportedDevices: ["Colmi R09"],
        connection: .bluetoothLE, requiredPermissions: ["Bluetooth"], needsPairing: false,
        kinds: [
            .heartRate: .protocolUnknown,
            .deviceBattery: .protocolUnknown,
            .steps: .protocolUnknown,
            .oxygenSaturation: .protocolUnknown,
            .ringHRV: .protocolUnknown,
            .ringStress: .protocolUnknown,
            .sleepDuration: .protocolUnknown,
            .skinTemperature: .protocolUnknown,
            .skinTemperatureDeviation: .protocolUnknown,
            .bodyTemperature: .unsupported
        ],
        supportsHistory: .protocolUnknown, supportsLive: .protocolUnknown, reconnects: true,
        firmwareNote: "Noch kein Gerät vorhanden.",
        knownLimitations: ["Ring misst an der Haut; keine Körperkerntemperatur."]
    )

    public static let appleHealth = AdapterDescriptor(
        id: "apple.health", title: "Apple Health", category: .phone,
        supportedDevices: ["iPhone", "Apps und Geräte, die in Apple Health schreiben"],
        connection: .healthKit, requiredPermissions: ["Health (je Datentyp)"], needsPairing: false,
        kinds: [
            .heartRate: .implementedUntested, .restingHeartRate: .implementedUntested,
            .heartRateVariability: .implementedUntested, .oxygenSaturation: .implementedUntested,
            .steps: .implementedUntested, .activeEnergy: .implementedUntested, .basalEnergy: .implementedUntested,
            .distance: .implementedUntested, .sleepDuration: .implementedUntested,
            .trainingDuration: .implementedUntested, .elevationGain: .planned,
            .bodyTemperature: .implementedUntested, .skinTemperatureDeviation: .implementedUntested,
            .respiratoryRate: .implementedUntested, .vo2Max: .implementedUntested,
            .bodyMass: .implementedUntested, .height: .implementedUntested
        ],
        supportsHistory: .implementedUntested, supportsLive: .unsupported, reconnects: false,
        firmwareNote: "–",
        knownLimitations: ["Nur für das Profil der iPhone-Besitzerin bzw. des Besitzers.",
                           "Lesezugriff verweigert ist für die App nicht von „keine Daten“ unterscheidbar."]
    )

    public static let ouraCloud = AdapterDescriptor(
        id: "oura.api.v2", title: "Oura Ring (Oura API V2)", category: .cloudService,
        supportedDevices: ["Oura Ring Gen 3/4 über Oura-Konto"],
        connection: .cloudOAuth, requiredPermissions: ["Oura-Anmeldung (OAuth2)"], needsPairing: false,
        kinds: [
            .heartRate: .planned, .restingHeartRate: .planned, .heartRateVariability: .planned,
            .sleepDuration: .planned, .steps: .planned, .skinTemperatureDeviation: .planned,
            .oxygenSaturation: .planned
        ],
        supportsHistory: .planned, supportsLive: .unsupported, reconnects: false,
        firmwareNote: "Cloud-Daten; Verzögerung bis zur Synchronisierung der Oura-App.",
        knownLimitations: ["Braucht Oura-Mitgliedschaft und registrierte Developer-App.", "Keine direkte Bluetooth-Verbindung."]
    )

    /// Bluetooth SIG Heart Rate Service 0x180D (chest straps such as Polar H10).
    public static let bluetoothHeartRate = AdapterDescriptor(
        id: "ble.heart_rate_service", title: "Bluetooth-Pulsgurt (Standard)", category: .chestStrap,
        supportedDevices: ["Geräte mit Heart Rate Service 0x180D"],
        connection: .bluetoothLE, requiredPermissions: ["Bluetooth"], needsPairing: false,
        kinds: [.heartRate: .planned, .deviceBattery: .planned, .heartRateVariability: .planned],
        supportsHistory: .unsupported, supportsLive: .planned, reconnects: true,
        firmwareNote: "Standardprofil, herstellerunabhängig."
    )

    public static let manual = AdapterDescriptor(
        id: "manual", title: "Manuelle Eingabe", category: .manualInput,
        supportedDevices: [],
        connection: .manual, requiredPermissions: [], needsPairing: false,
        kinds: [.trainingDuration: .planned, .distance: .planned, .elevationGain: .planned, .activeEnergy: .planned],
        supportsHistory: .unsupported, supportsLive: .unsupported, reconnects: false,
        firmwareNote: "–"
    )

    public static let all: [AdapterDescriptor] = [colmiR03, colmiR09, appleHealth, ouraCloud, bluetoothHeartRate, manual]

    public static func descriptor(id: String) -> AdapterDescriptor? { all.first { $0.id == id } }

    /// The source system samples of an adapter are stored under.
    public static func sourceKind(adapterID: String) -> DataSourceKind? {
        switch adapterID {
        case colmiR03.id, colmiR09.id: .colmiRing
        case appleHealth.id: .appleHealth
        case ouraCloud.id: .ouraCloud
        case bluetoothHeartRate.id: .bluetoothStandard
        case manual.id: .manual
        default: nil
        }
    }
}
