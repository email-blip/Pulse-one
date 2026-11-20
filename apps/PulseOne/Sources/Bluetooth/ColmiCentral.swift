import CoreBluetooth
import Foundation
import PulseCore

/// CoreBluetooth driver for Colmi rings (Nordic UART service, protocol in `ColmiProtocol`).
///
/// Runs entirely on the main queue. The Bluetooth permission prompt appears only when the
/// user first taps "Ring suchen" (or when a ring was already paired and permission exists).
/// Unknown notifications are logged, never fatal (firmware updates are allowed).
@MainActor
final class ColmiCentral: NSObject {
    private weak var store: RingStore?
    private var manager: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var pendingAction: PendingAction?
    private var userRequestedDisconnect = false
    private var reconnectAttempt = 0
    private let reconnectPolicy = ReconnectPolicy()
    private var connectTimeout: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var keepAlive: Task<Void, Never>?
    private var scanTimeout: Task<Void, Never>?

    private enum PendingAction { case scan, reconnect(UUID) }

    private static let rememberedIDKey = "ring.rememberedIdentifier"
    private static let rememberedNameKey = "ring.rememberedName"
    private static let uart = CBUUID(string: ColmiProtocol.uartService)
    private static let uartWrite = CBUUID(string: ColmiProtocol.uartWrite)
    private static let uartNotify = CBUUID(string: ColmiProtocol.uartNotify)
    private static let deviceInfo = CBUUID(string: ColmiProtocol.deviceInfoService)
    private static let firmwareRevision = CBUUID(string: ColmiProtocol.firmwareRevision)
    /// A live measurement stops by itself to protect the ring battery.
    private static let liveMeasurementLimit: Duration = .seconds(60)

    init(store: RingStore) {
        self.store = store
        super.init()
        store.snapshot.rememberedRing = UserDefaults.standard.string(forKey: Self.rememberedNameKey)
        // Reconnect automatically only if the user already granted Bluetooth earlier.
        if CBManager.authorization == .allowedAlways, let id = rememberedIdentifier {
            pendingAction = .reconnect(id)
            makeManager()
        }
    }

    // MARK: Commands from the UI

    func startScan() {
        guard let manager, manager.state == .poweredOn else {
            pendingAction = .scan
            makeManager()
            return
        }
        update { $0.discovered = []; $0.connection = .scanning; $0.lastError = nil }
        manager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanTimeout?.cancel()
        scanTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            self?.stopScan()
        }
    }

    func stopScan() {
        scanTimeout?.cancel()
        manager?.stopScan()
        if store?.snapshot.connection == .scanning { update { $0.connection = .idle } }
    }

    func connect(_ id: UUID) {
        guard let manager, let target = peripherals[id] ?? manager.retrievePeripherals(withIdentifiers: [id]).first else {
            update { $0.connection = .failed(message: "Ring nicht mehr gefunden. Bitte erneut suchen.") }
            return
        }
        scanTimeout?.cancel()
        manager.stopScan()
        userRequestedDisconnect = false
        reconnectAttempt = 0
        peripheral = target
        let name = displayName(of: target)
        update { $0.connection = .connecting(name: name); $0.deviceName = name; $0.lastError = nil }
        manager.connect(target)
        connectTimeout?.cancel()
        connectTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self, case .connecting = self.store?.snapshot.connection else { return }
            self.userRequestedDisconnect = true
            if let peripheral = self.peripheral { self.manager?.cancelPeripheralConnection(peripheral) }
            self.update {
                $0.connection = .failed(message: "Der Ring antwortet nicht. Ist er in der Nähe und nicht gerade mit der QRing-App verbunden?")
            }
        }
    }

    func reconnectRemembered() {
        guard let id = rememberedIdentifier else { return }
        guard let manager, manager.state == .poweredOn else {
            pendingAction = .reconnect(id)
            makeManager()
            return
        }
        connect(id)
    }

    /// Connects a known ring by its identifier (from the device list), creating the manager if needed.
    func connectKnown(_ id: UUID) {
        guard let manager, manager.state == .poweredOn else {
            pendingAction = .reconnect(id)
            makeManager()
            return
        }
        connect(id)
    }

    func disconnect() {
        userRequestedDisconnect = true
        reconnectTask?.cancel()
        stopHeartRate()
        if let peripheral { manager?.cancelPeripheralConnection(peripheral) }
        update { $0.connection = .disconnected; $0.liveHeartRate = nil }
    }

    func startHeartRate() {
        guard store?.snapshot.connection == .ready else { return }
        write(ColmiProtocol.realTimeStart(.heartRate))
        update { $0.connection = .measuring; $0.liveHeartRate = nil; $0.lastError = nil }
        keepAlive?.cancel()
        keepAlive = Task { [weak self] in
            let started = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled, let self else { return }
                if ContinuousClock.now - started >= Self.liveMeasurementLimit {
                    self.stopHeartRate()
                    return
                }
                self.write(ColmiProtocol.realTimeContinue(.heartRate))
            }
        }
    }

    func stopHeartRate() {
        keepAlive?.cancel()
        keepAlive = nil
        guard store?.snapshot.connection == .measuring else { return }
        write(ColmiProtocol.realTimeStop(.heartRate))
        update { $0.connection = .ready }
    }

    func refreshBattery() {
        write(ColmiProtocol.batteryRequest())
    }

    // MARK: Helpers

    private func makeManager() {
        if manager == nil {
            manager = CBCentralManager(delegate: self, queue: .main)
        } else if let manager {
            centralManagerDidUpdateState(manager)
        }
    }

    private var rememberedIdentifier: UUID? {
        UserDefaults.standard.string(forKey: Self.rememberedIDKey).flatMap(UUID.init(uuidString:))
    }

    private func remember(_ peripheral: CBPeripheral) {
        let name = displayName(of: peripheral)
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Self.rememberedIDKey)
        UserDefaults.standard.set(name, forKey: Self.rememberedNameKey)
        update { $0.rememberedRing = name }
    }

    private func displayName(of peripheral: CBPeripheral) -> String {
        peripheral.name ?? store?.snapshot.discovered.first { $0.id == peripheral.identifier }?.name ?? "Ring"
    }

    private func update(_ change: (inout RingSnapshot) -> Void) {
        guard let store else { return }
        change(&store.snapshot)
    }

    private func write(_ packet: [UInt8]) {
        guard let peripheral, let characteristic = writeCharacteristic, !packet.isEmpty else { return }
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(Data(packet), for: characteristic, type: type)
    }

    private func handle(_ packet: [UInt8]) {
        guard let store else { return }
        let snapshot = store.snapshot
        switch ColmiProtocol.decode(packet) {
        case .battery(let battery):
            update {
                $0.battery = battery
                $0.capabilities.raise(.battery, to: .verified)
            }
            record(.battery, battery.level, snapshot)
        case .realTime(.value(let type, let value)):
            guard type == ColmiProtocol.RealTimeType.heartRate.rawValue, value > 0 else { return }
            guard let reading = makeReading(.heartRate, value, snapshot) else { return }
            update {
                $0.liveHeartRate = value
                $0.lastHeartRate = reading
                $0.capabilities.raise(.heartRate, to: .verified)
            }
            store.record(reading)
        case .realTime(.error(_, let code)):
            update { $0.lastError = "Der Ring meldet einen Messfehler (Code \(code)). Ring enger anlegen und erneut versuchen." }
            stopHeartRate()
        case .setTimeAck:
            break
        case .heartRateLog, .unknown:
            update { $0.logUnknown(ColmiProtocol.hex(packet)) }
        }
    }

    private func makeReading(_ metric: Metric, _ value: Int, _ snapshot: RingSnapshot) -> VitalReading? {
        VitalReading(metric: metric, value: value, timestamp: .now, source: .ringLive,
                     deviceName: snapshot.deviceName ?? "Ring",
                     deviceIdentifier: snapshot.deviceIdentifier ?? "",
                     model: snapshot.model?.name, firmware: snapshot.firmware)
    }

    private func record(_ metric: Metric, _ value: Int, _ snapshot: RingSnapshot) {
        if let reading = makeReading(metric, value, snapshot) { store?.record(reading) }
    }

    private func scheduleReconnect() {
        reconnectAttempt += 1
        guard let delay = reconnectPolicy.delay(forAttempt: reconnectAttempt) else {
            update { $0.connection = .failed(message: "Verbindung verloren. Tippe auf „Erneut verbinden“.") }
            return
        }
        let attempt = reconnectAttempt
        update { $0.connection = .reconnecting(attempt: attempt) }
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, !self.userRequestedDisconnect else { return }
            // CoreBluetooth keeps this request open until the ring is back in range.
            if let peripheral = self.peripheral { self.manager?.connect(peripheral) }
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension ColmiCentral: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let availability: BluetoothAvailability = switch central.state {
        case .poweredOn: .ready
        case .poweredOff: .poweredOff
        case .unauthorized: .unauthorized
        case .unsupported: .unsupported
        default: .unknown
        }
        update { $0.bluetooth = availability }
        guard availability == .ready else {
            if availability != .unknown, store?.snapshot.connection.isBusy == true {
                update { $0.connection = .failed(message: availability.label) }
            }
            return
        }
        switch pendingAction {
        case .scan: pendingAction = nil; startScan()
        case .reconnect(let id): pendingAction = nil; connect(id)
        case nil: break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advertised = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard let name = advertised ?? peripheral.name, !name.isEmpty else { return }
        peripherals[peripheral.identifier] = peripheral
        let ring = DiscoveredRing(id: peripheral.identifier, name: name, rssi: RSSI.intValue,
                                  model: ColmiModel.detect(advertisedName: name))
        update { $0.upsert(ring) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectTimeout?.cancel()
        reconnectAttempt = 0
        self.peripheral = peripheral
        peripheral.delegate = self
        let name = displayName(of: peripheral)
        update {
            $0.connection = .discovering
            $0.deviceName = name
            $0.deviceIdentifier = peripheral.identifier.uuidString
            $0.model = ColmiModel.detect(advertisedName: name)
            $0.capabilities = CapabilityTracker()
        }
        remember(peripheral)
        peripheral.discoverServices([Self.uart, Self.deviceInfo])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectTimeout?.cancel()
        update { $0.connection = .failed(message: "Verbindung fehlgeschlagen. Bitte erneut versuchen.") }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        keepAlive?.cancel()
        writeCharacteristic = nil
        update { $0.liveHeartRate = nil }
        if userRequestedDisconnect {
            if case .failed = store?.snapshot.connection { return }
            update { $0.connection = .disconnected }
        } else {
            self.peripheral = peripheral
            scheduleReconnect()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension ColmiCentral: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let services = peripheral.services ?? []
        guard services.contains(where: { $0.uuid == Self.uart }) else {
            userRequestedDisconnect = true
            manager?.cancelPeripheralConnection(peripheral)
            update { $0.connection = .failed(message: "Dieses Gerät bietet den Colmi-Datendienst nicht an. Ist es wirklich ein Colmi-Ring?") }
            return
        }
        for service in services {
            if service.uuid == Self.uart {
                peripheral.discoverCharacteristics([Self.uartWrite, Self.uartNotify], for: service)
            } else if service.uuid == Self.deviceInfo {
                peripheral.discoverCharacteristics([Self.firmwareRevision], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case Self.uartWrite:
                writeCharacteristic = characteristic
            case Self.uartNotify:
                peripheral.setNotifyValue(true, for: characteristic)
            case Self.firmwareRevision:
                peripheral.readValue(for: characteristic)
            default:
                break
            }
        }
        if service.uuid == Self.uart {
            update {
                $0.capabilities.raise(.heartRate, to: .discovered)
                $0.capabilities.raise(.battery, to: .discovered)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.uartNotify else { return }
        guard error == nil, characteristic.isNotifying else {
            update { $0.connection = .failed(message: "Der Ring sendet keine Daten. Bitte trennen und neu verbinden.") }
            return
        }
        update { $0.connection = .ready }
        if let packet = try? ColmiProtocol.setTimeRequest(.now) { write(packet) }
        refreshBattery()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        switch characteristic.uuid {
        case Self.uartNotify:
            handle([UInt8](data))
        case Self.firmwareRevision:
            let firmware = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .controlCharacters.union(.whitespaces))
            update { $0.firmware = firmware.isEmpty ? nil : firmware }
        default:
            break
        }
    }
}
