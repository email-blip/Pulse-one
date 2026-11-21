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
    private var notifyCharacteristic: CBCharacteristic?
    /// The peripheral whose cancelled link still has to be proven released (review R2-3/R3-1).
    private var releasingPeripheral: CBPeripheral?
    /// Connect → services → characteristics → notify, each with a time limit (Codex review P1-003 F3).
    private var handshake = RingHandshake()
    private var handshakeTicker: Task<Void, Never>?
    private var pendingAction: PendingAction?
    private var userRequestedDisconnect = false
    private var reconnectAttempt = 0
    private let reconnectPolicy = ReconnectPolicy()
    private var reconnectTask: Task<Void, Never>?
    private var measurementTicker: Task<Void, Never>?
    private var measurement = LiveMeasurement()
    private var measurementMode: ColmiProtocol.HeartRateStartMode = .realTime
    private var scanTimeout: Task<Void, Never>?
    /// Second service (SpO₂, sleep history); optional, older firmware may lack it.
    private var bigDataWrite: CBCharacteristic?
    private var bigDataNotify: CBCharacteristic?
    private var historySync: RingHistorySync?
    private var syncStepTimer: Task<Void, Never>?
    private var postReadyTask: Task<Void, Never>?
    private var writeQueue: Task<Void, Never>?
    private let syncSchedule = RingSyncSchedule()

    private enum PendingAction { case scan, reconnect(UUID) }

    private static let rememberedIDKey = "ring.rememberedIdentifier"
    private static let rememberedNameKey = "ring.rememberedName"
    private static let uart = CBUUID(string: ColmiProtocol.uartService)
    private static let uartWrite = CBUUID(string: ColmiProtocol.uartWrite)
    private static let uartNotify = CBUUID(string: ColmiProtocol.uartNotify)
    private static let deviceInfo = CBUUID(string: ColmiProtocol.deviceInfoService)
    private static let firmwareRevision = CBUUID(string: ColmiProtocol.firmwareRevision)
    /// Device information the diagnosis may read. Serial number (2A25) and system ID (2A23) are left out on purpose.
    private static let readableDeviceInfo: Set<CBUUID> = Set(["2A24", "2A26", "2A27", "2A28", "2A29"].map { CBUUID(string: $0) })
    /// Standard services the diagnosis does not subscribe to.
    private static let standardServices: Set<CBUUID> = Set(["1800", "1801", "180A"].map { CBUUID(string: $0) })
    private static let bigDataService = CBUUID(string: ColmiHistory.bigDataService)
    private static let bigDataWriteID = CBUUID(string: ColmiHistory.bigDataWrite)
    private static let bigDataNotifyID = CBUUID(string: ColmiHistory.bigDataNotify)
    static let lastSyncKey = "ring.lastHistorySync"
    /// Seconds without an answer before a history step counts as unanswered.
    private static let stepTimeout: Duration = .seconds(8)

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
        reconnectTask?.cancel()
        // Switching to another ring: release the old link first. The connect below waits for proof.
        if let old = peripheral, old.identifier != target.identifier, old.state != .disconnected { cancelLink() }
        peripheral = target
        let name = displayName(of: target)
        update { $0.connection = .connecting(name: name); $0.deviceName = name; $0.lastError = nil }
        writeCharacteristic = nil
        notifyCharacteristic = nil
        // While a previous link is not proven released, the connect is queued and sent only after the
        // disconnect callback or an observed `.disconnected` state (serialised lifecycle, review R2-3/R3-1).
        checkRelease()
        perform(handshake.handle(.connectRequested(.now)))
        if handshake.isCancelling { trace(.event, "Neue Verbindung wartet auf das Ende der alten") }
        runHandshakeTicker()
    }

    /// Carries out what the handshake asks for.
    private func perform(_ action: RingHandshake.Action) {
        switch action {
        case .none: break
        case .connectNow:
            if let peripheral { manager?.connect(peripheral) }
            runHandshakeTicker()
        case .rejectConnection:
            if let peripheral { manager?.cancelPeripheralConnection(peripheral) }
        case .retryCancel:
            trace(.event, "Alte Verbindung noch nicht beendet, Trennen wird wiederholt")
            if let releasingPeripheral { manager?.cancelPeripheralConnection(releasingPeripheral) }
            runHandshakeTicker()
        }
    }

    /// Asks CoreBluetooth to drop the link. `cancelPeripheralConnection` does not block, so the link
    /// counts as released only on evidence (`didDisconnect` or `checkRelease`), see `RingHandshake`.
    private func cancelLink() {
        handshake.handle(.cancelRequested(.now))
        writeCharacteristic = nil
        notifyCharacteristic = nil
        if let peripheral {
            if handshake.releasePending { releasingPeripheral = peripheral }
            manager?.cancelPeripheralConnection(peripheral)
        }
        runHandshakeTicker()
    }

    /// Evidence of release besides the callback: CoreBluetooth reports the old peripheral as disconnected.
    private func checkRelease() {
        guard handshake.releasePending, let old = releasingPeripheral, old.state == .disconnected else { return }
        trace(.event, "Alte Verbindung laut Bluetooth-Status beendet")
        releaseConfirmed(handshake.handle(.released(.now)))
    }

    private func releaseConfirmed(_ action: RingHandshake.Action) {
        releasingPeripheral = nil
        if action == .connectNow { trace(.event, "Alte Verbindung beendet, neue wird aufgebaut") }
        perform(action)
    }

    /// Checks the time limits and the pending release once per second while something is open.
    private func runHandshakeTicker() {
        handshakeTicker?.cancel()
        handshakeTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.checkRelease()
                let before = self.handshake.failure
                self.perform(self.handshake.handle(.tick(.now)))
                if let failure = self.handshake.failure, failure != before { self.failHandshake(failure) }
                if !self.handshake.needsTimer { return }
            }
        }
    }

    /// Ends a connection attempt that cannot become ready, with a message that says why.
    private func failHandshake(_ failure: HandshakeFailure) {
        trace(.event, "Einrichtung abgebrochen: \(failure.message)")
        userRequestedDisconnect = true
        // `releaseTimeout`: nothing was connected; the old link is still being watched.
        if failure != .releaseTimeout { cancelLink() }
        update { $0.connection = .failed(message: failure.message) }
    }

    /// Callbacks for a peripheral that is no longer the current one are ignored. CoreBluetooth has no
    /// session id, so this alone is no session guard; values additionally need `isExpected`.
    private func isCurrent(_ candidate: CBPeripheral) -> Bool {
        candidate.identifier == peripheral?.identifier
    }

    /// The characteristic object found in this link's own discovery. Objects of an older link (same
    /// UUID, earlier discovery) are different instances and do not pass.
    private func isExpected(_ characteristic: CBCharacteristic, _ handle: CBCharacteristic?) -> Bool {
        guard let handle else { return false }
        return characteristic === handle
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
        cancelLink()
        trace(.event, "Trennen durch Nutzer")
        update { $0.connection = .disconnected; $0.liveHeartRate = nil }
    }

    /// Sends the start command. The screen shows "Messung angefordert" until the ring answers;
    /// "läuft" and values come only from the ring's own answers (`handle`).
    func startHeartRate(mode: ColmiProtocol.HeartRateStartMode = .realTime) {
        guard store?.snapshot.connection == .ready, handshake.isReady, writeCharacteristic != nil,
              !measurement.phase.isActive else {
            trace(.event, "Messung nicht gestartet: Ring nicht bereit")
            return
        }
        measurement.handle(.start(.now))
        measurementMode = mode
        trace(.event, "Messung gestartet (\(mode.traceLabel))")
        write(mode.startPacket)
        update { $0.lastError = nil }
        publishMeasurement()
        measurementTicker?.cancel()
        // No continue command: neither reference client sends one while waiting (see colmi-protokoll.md).
        measurementTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                let now = Date.now
                self.measurement.handle(.tick(now))
                guard self.measurement.phase.isActive else {
                    self.trace(.event, "Messung beendet: \(self.measurement.phase.title)")
                    self.sendStopIfNeeded()
                    self.publishMeasurement()
                    return
                }
                self.publishMeasurement()
            }
        }
    }

    func stopHeartRate() {
        measurementTicker?.cancel()
        measurementTicker = nil
        guard measurement.phase.isActive else { return }
        measurement.handle(.stop(.now))
        trace(.event, "Messung vom Nutzer beendet")
        sendStopIfNeeded()
        publishMeasurement()
    }

    private func sendStopIfNeeded() {
        if measurementMode.sendsStop { write(ColmiProtocol.realTimeStop(.heartRate)) }
    }

    private func publishMeasurement() {
        let phase = measurement.phase
        update {
            $0.measurement = phase
            if case .receiving(let value, _, _) = phase { $0.liveHeartRate = value } else { $0.liveHeartRate = nil }
        }
    }

    func refreshBattery() {
        write(ColmiProtocol.batteryRequest())
    }

    // MARK: Automatic measurements and history

    /// Sends the measuring profile (only features the ring may support), then reads the settings back.
    func applyProfile(_ profile: RingMeasurementProfile) {
        guard handshake.isReady, let store else { return }
        let features = store.snapshot.features
        var packets = profile.packets(for: features)
        for feature in [RingFeature.heartRate, .hrv, .stress, .spo2] where features.mayUse(feature) {
            if let read = ColmiProtocol.preferenceRead(feature) { packets.append(read) }
        }
        trace(.event, "Messprofil „\(profile.title)“ an den Ring senden")
        writeSpaced(packets)
    }

    /// Fetches the stored history. `force` ignores the schedule (button "Verlauf jetzt abrufen").
    func syncHistory(force: Bool) {
        guard handshake.isReady, historySync == nil, let store else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
        guard force || syncSchedule.isDue(lastSync: last, now: .now) else { return }
        guard !measurement.phase.isActive else {
            trace(.event, "Verlauf später abrufen: Messung läuft")
            return
        }
        let calendar = Calendar.current
        let days = syncSchedule.days(lastSync: last, now: .now, calendar: calendar)
        let mapper = RingHistoryMapper(deviceID: store.snapshot.deviceIdentifier ?? "", calendar: calendar, today: .now)
        var sync = RingHistorySync(days: days, support: store.snapshot.features,
                                   hasBigDataChannel: bigDataWrite != nil && bigDataNotify != nil, mapper: mapper)
        trace(.event, "Verlauf abrufen: \(days) Tage")
        let first = sync.start()
        historySync = sync
        continueSync(first)
    }

    func findRing() {
        trace(.event, "Ring finden: Ring soll blinken")
        write(ColmiProtocol.findRingRequest())
    }

    func powerOff() {
        trace(.event, "Ring ausschalten")
        write(ColmiProtocol.powerOffRequest())
    }

    /// Called when the app comes to the foreground: fetch if due, or reconnect the known ring first.
    func syncIfDue() {
        if handshake.isReady {
            syncHistory(force: false)
        } else if CBManager.authorization == .allowedAlways, rememberedIdentifier != nil,
                  store?.snapshot.connection.isConnected == false {
            let last = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
            if syncSchedule.isDue(lastSync: last, now: .now) { reconnectRemembered() }
        }
    }

    private func feedHistory(_ step: (inout RingHistorySync) -> RingHistorySync.Request?) {
        guard var sync = historySync else { return }
        let next = step(&sync)
        historySync = sync
        continueSync(next)
    }

    private func continueSync(_ next: RingHistorySync.Request?) {
        guard let sync = historySync else { return }
        guard let next else {
            if sync.isFinished { finishSync(interrupted: false) }
            return
        }
        syncStepTimer?.cancel()
        update { $0.historySync = .running(step: next.step.title, remaining: sync.remaining + 1) }
        switch next.channel {
        case .uart:
            write(next.packet)
        case .bigData:
            writeBigData(next.packet)
        }
        syncStepTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.stepTimeout)
            guard !Task.isCancelled, let self else { return }
            self.trace(.event, "Keine vollständige Antwort: \(next.step.title)")
            self.feedHistory { $0.timeout() }
        }
    }

    private func finishSync(interrupted: Bool) {
        syncStepTimer?.cancel()
        guard let sync = historySync else { return }
        historySync = nil
        let now = Date.now
        if !sync.observations.isEmpty, let id = store?.snapshot.deviceIdentifier {
            store?.recordHistory(sync.observations, deviceIdentifier: id)
        }
        if !interrupted {
            UserDefaults.standard.set(now, forKey: Self.lastSyncKey)
            store?.noteHistorySynced(at: now)
        }
        let summary = sync.report.summary
        trace(.event, (interrupted ? "Verlauf unterbrochen: " : "Verlauf fertig: ") + summary)
        update {
            for feature in RingFeature.allCases {
                switch sync.support.state(of: feature) {
                case .answered?: $0.features.markAnswered(feature)
                case .unsupported?: $0.features.markSilent(feature)
                default: break
                }
            }
            $0.historySync = interrupted ? .interrupted(summary: summary, at: now) : .finished(summary: summary, at: now)
        }
    }

    private func writeBigData(_ packet: [UInt8]) {
        guard let peripheral, let characteristic = bigDataWrite else {
            trace(.event, "Zweiter Kanal fehlt: \(ColmiProtocol.hex(packet))")
            return
        }
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        trace(.sent, channel: characteristic.uuid.uuidString, ColmiProtocol.hex(packet))
        peripheral.writeValue(Data(packet), for: characteristic, type: type)
    }

    /// Several settings one after another with a short gap, so the ring is not flooded.
    private func writeSpaced(_ packets: [[UInt8]]) {
        writeQueue?.cancel()
        writeQueue = Task { [weak self] in
            for packet in packets {
                guard !Task.isCancelled, let self else { return }
                self.write(packet)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
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
        guard let peripheral, let characteristic = writeCharacteristic, !packet.isEmpty else {
            trace(.event, "Senden nicht möglich (keine Verbindung): \(ColmiProtocol.hex(packet))")
            return
        }
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        trace(.sent, channel: characteristic.uuid.uuidString, ColmiProtocol.hex(packet))
        peripheral.writeValue(Data(packet), for: characteristic, type: type)
    }

    private func trace(_ direction: BLETrace.Direction, channel: String = "", _ text: String) {
        store?.trace.add(direction, channel: channel, text)
    }

    private static func describe(_ properties: CBCharacteristicProperties) -> String {
        var names: [String] = []
        if properties.contains(.read) { names.append("read") }
        if properties.contains(.write) { names.append("write") }
        if properties.contains(.writeWithoutResponse) { names.append("writeNoResp") }
        if properties.contains(.notify) { names.append("notify") }
        if properties.contains(.indicate) { names.append("indicate") }
        return names.joined(separator: ",")
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
            guard type == ColmiProtocol.RealTimeType.heartRate.rawValue else {
                update { $0.logUnknown(ColmiProtocol.hex(packet)) }
                return
            }
            let before = measurement.phase
            measurement.handle(.ringValue(value, .now))
            publishMeasurement()
            // Store only when this answer produced a new valid value.
            guard case .receiving(let bpm, let at, _) = measurement.phase, measurement.phase != before,
                  before.value?.at != at,
                  let reading = makeReading(.heartRate, bpm, snapshot) else { return }
            update {
                $0.lastHeartRate = reading
                $0.capabilities.raise(.heartRate, to: .verified)
            }
            store.record(reading)
        case .realTime(.error(_, let code)):
            measurement.handle(.ringError(code: code, .now))
            if measurement.phase.isActive {
                trace(.event, "Ring meldet vorübergehenden Fehler (Code \(code)), Messung läuft weiter")
            } else {
                measurementTicker?.cancel()
                trace(.event, "Messung beendet: \(measurement.phase.title)")
                sendStopIfNeeded()
            }
            publishMeasurement()
        case .setTimeAck, .realTimeStopAck, .packetSize, .settingWriteAck:
            break
        case .setting(let report):
            update {
                $0.ringSettings[report.feature] = report
                $0.features.markAnswered(report.feature)
            }
        case .history:
            if historySync == nil {
                update { $0.logUnknown(ColmiProtocol.hex(packet)) }
            } else {
                let response = ColmiProtocol.decode(packet)
                feedHistory { $0.handle(response) }
            }
        case .unknown:
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
        handshake.handle(.reconnectScheduled)
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
        // Bluetooth off ends every link; that is proof of release for a cancelled one.
        if central.state == .poweredOff, handshake.releasePending { releaseConfirmed(handshake.handle(.released(.now))) }
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
        guard isCurrent(peripheral) else {
            trace(.event, "Späte Verbindung eines anderen Geräts ignoriert")
            central.cancelPeripheralConnection(peripheral)
            return
        }
        // A didConnect that no step expects (e.g. after the user disconnected) is cancelled again.
        if handshake.handle(.connected(.now)) == .rejectConnection {
            trace(.event, "Unerwartete Verbindung abgelehnt")
            central.cancelPeripheralConnection(peripheral)
            return
        }
        runHandshakeTicker()
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
            $0.features = RingFeatureSupport(model: ColmiModel.detect(advertisedName: name))
            $0.ringSettings = [:]
        }
        bigDataWrite = nil
        bigDataNotify = nil
        remember(peripheral)
        trace(.event, "Verbunden mit \(BLETrace.redactedName(name)); suche alle Dienste")
        // All services, so the diagnosis shows everything the ring offers.
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard isCurrent(peripheral) else { return }
        handshake.handle(.connectFailed)
        trace(.event, "Verbindung fehlgeschlagen: \(error?.localizedDescription ?? "ohne Grund")")
        update { $0.connection = .failed(message: "Verbindung fehlgeschlagen. Bitte erneut versuchen.") }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // Proof that a cancelled link is released, also for the previous ring when switching.
        if handshake.releasePending, let old = releasingPeripheral, old.identifier == peripheral.identifier {
            trace(.event, "Alte Verbindung bestätigt beendet: \(error?.localizedDescription ?? "ohne Fehler")")
            let action = handshake.handle(.disconnected(.now))
            if old.identifier == self.peripheral?.identifier {
                measurementTicker?.cancel()
                measurement.handle(.disconnected(.now))
                publishMeasurement()
            }
            releaseConfirmed(action)
            return
        }
        guard isCurrent(peripheral) else {
            trace(.event, "Trennung eines früheren Geräts ignoriert")
            return
        }
        let wasLinked = handshake.hasLink
        handshake.handle(.disconnected(.now))
        trace(.event, "Verbindung getrennt: \(error?.localizedDescription ?? "ohne Fehler")")
        // A stray callback while a new attempt is still connecting changes nothing (review R3-1).
        guard wasLinked || userRequestedDisconnect else { return }
        writeCharacteristic = nil
        notifyCharacteristic = nil
        bigDataWrite = nil
        bigDataNotify = nil
        postReadyTask?.cancel()
        writeQueue?.cancel()
        if historySync != nil { finishSync(interrupted: true) }
        measurementTicker?.cancel()
        measurement.handle(.disconnected(.now))
        publishMeasurement()
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
        guard isCurrent(peripheral) else { return }
        let services = peripheral.services ?? []
        if let error { trace(.event, "Dienstsuche: Fehler \(error.localizedDescription)") }
        for service in services { trace(.event, channel: service.uuid.uuidString, "Dienst \(service.uuid.uuidString)") }
        handshake.handle(.servicesDiscovered(hasUART: services.contains { $0.uuid == Self.uart },
                                             error: error?.localizedDescription))
        if let failure = handshake.failure { failHandshake(failure); return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard isCurrent(peripheral) else { return }
        if let error {
            trace(.event, channel: service.uuid.uuidString, "Merkmalsuche: Fehler \(error.localizedDescription)")
        }
        for characteristic in service.characteristics ?? [] {
            trace(.event, channel: characteristic.uuid.uuidString,
                  "Merkmal \(characteristic.uuid.uuidString) in \(BLETrace.shortUUID(service.uuid.uuidString)) [\(Self.describe(characteristic.properties))]")
            switch characteristic.uuid {
            case Self.uartWrite where service.uuid == Self.uart && handshake.acceptsCharacteristics:
                writeCharacteristic = characteristic
            case Self.uartNotify where service.uuid == Self.uart && handshake.acceptsCharacteristics:
                notifyCharacteristic = characteristic
            case Self.bigDataWriteID where service.uuid == Self.bigDataService:
                bigDataWrite = characteristic
            case Self.bigDataNotifyID where service.uuid == Self.bigDataService:
                // Gadgetbridge reads SpO₂ and sleep history here (CMD_BIG_DATA_V2).
                bigDataNotify = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            default:
                if service.uuid == Self.deviceInfo {
                    if Self.readableDeviceInfo.contains(characteristic.uuid) { peripheral.readValue(for: characteristic) }
                } else if !Self.standardServices.contains(service.uuid), service.uuid != Self.uart,
                          !characteristic.properties.intersection([.notify, .indicate]).isEmpty {
                    // Listen only (no command is sent): shows whether the ring reports on another channel.
                    trace(.event, channel: characteristic.uuid.uuidString, "nur mitlesen: Benachrichtigungen an")
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        }
        guard service.uuid == Self.uart, handshake.acceptsCharacteristics else { return }
        // Commands need the write channel, answers the notify channel; without both the ring is not ready.
        let canWrite = writeCharacteristic.map { !$0.properties.intersection([.write, .writeWithoutResponse]).isEmpty } ?? false
        let canNotify = notifyCharacteristic.map { !$0.properties.intersection([.notify, .indicate]).isEmpty } ?? false
        handshake.handle(.uartCharacteristics(hasWrite: canWrite, hasNotify: canNotify, error: error?.localizedDescription))
        if let failure = handshake.failure { failHandshake(failure); return }
        if let notifyCharacteristic { peripheral.setNotifyValue(true, for: notifyCharacteristic) }
        update {
            $0.capabilities.raise(.heartRate, to: .discovered)
            $0.capabilities.raise(.battery, to: .discovered)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let state = characteristic.isNotifying ? "an" : "aus"
        let failure = error.map { " · Fehler " + $0.localizedDescription } ?? ""
        trace(.event, channel: characteristic.uuid.uuidString, "Benachrichtigungen " + state + failure)
        guard isCurrent(peripheral), isExpected(characteristic, notifyCharacteristic) else { return }
        let wasReady = handshake.isReady
        handshake.handle(.notifyState(isOn: characteristic.isNotifying, error: error?.localizedDescription))
        if let failure = handshake.failure { failHandshake(failure); return }
        guard handshake.isReady, !wasReady else { return }
        handshakeTicker?.cancel()
        trace(.event, "Bereit: Befehls- und Antwortkanal aktiv")
        update { $0.connection = .ready }
        if let packet = try? ColmiProtocol.setTimeRequest(.now) { write(packet) }
        refreshBattery()
        // Then the measuring profile and the stored history, with pauses so answers do not overlap.
        postReadyTask?.cancel()
        postReadyTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, let store = self.store else { return }
            self.applyProfile(store.measurementProfile)
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self.syncHistory(force: true)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard isCurrent(peripheral) else { return }
        let channel = characteristic.uuid.uuidString
        if let error { trace(.event, channel: channel, "Lesefehler: \(error.localizedDescription)") }
        guard error == nil, let data = characteristic.value else { return }
        let bytes = [UInt8](data)
        if characteristic.service?.uuid == Self.deviceInfo {
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .controlCharacters.union(.whitespaces))
            trace(.received, channel: channel, "\"\(text)\"")
            if characteristic.uuid == Self.firmwareRevision {
                update { $0.firmware = text.isEmpty ? nil : text }
            }
            return
        }
        trace(.received, channel: channel, ColmiProtocol.hex(bytes))
        // Ring answers count only on this link's own notify characteristic object, once ready.
        if isExpected(characteristic, notifyCharacteristic), handshake.isReady { handle(bytes) }
        if isExpected(characteristic, bigDataNotify), handshake.isReady { feedHistory { $0.handleBigData(bytes) } }
    }
}
