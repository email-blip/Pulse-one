# PULSE ONE – Produktarchitektur 5.0

Stand: 2026-11-20. Verantwortlich: Claude Code (Implementierungs- und Planungsführung). Grundlage: Master Directive 5.0, Directives 4.0 und 4.2, Code-Stand `main` nach PR #9.
Ergänzende Dokumente: `HEALTH-DATA-SPEC.md` (Datenmodell), `IMPLEMENTATION-ROADMAP.md` (Reihenfolge), `ACCEPTANCE-MATRIX.md` (Abnahme). Fachkonzepte zu Claude, Coach, Ernährung, Klinik und Design kommen aus eigenen Dokumenten und werden hier nur eingeordnet.

## 1. Leitentscheidungen

| # | Entscheidung | Begründung |
|---|---|---|
| A1 | Eine native App (Swift 6, SwiftUI, SwiftData, iOS 18+), keine Neuentwicklung. Bestehender Code bleibt. | 5.0 „Verbindliche Ausgangslage“; Kern ist getestet (Review 3.2) |
| A2 | Fachlogik nur im Swift-Paket `PulseCore`, ohne UIKit/SwiftUI/HealthKit/CoreBluetooth. Die App enthält Adapter (BLE, HealthKit, Keychain, Netzwerk) und Oberfläche. | Logik ist auf Linux-freien CI-Runnern schnell testbar, Plattformcode bleibt dünn |
| A3 | Module als Ordner in `PulseCore`, nicht als eigene Pakete. Abhängigkeiten nur in eine Richtung (§2). | Ein Paket = ein Build-Schritt in CI (≈ 20 Gratis-Minuten pro Lauf) |
| A4 | Originalmessungen werden nie verändert oder verdichtet gelöscht. Aggregate sind abgeleitet und jederzeit neu berechenbar. | 5.0 Teil III „Langzeitarchiv“ |
| A5 | Lokal zuerst: Jede Auswertung läuft ohne Netz und ohne Claude. Claude bekommt nur einen geprüften, freigegebenen Kontext. | 4.2 §5, 5.0 Teil VI und XI |
| A6 | Wellness und klinisches Forschungsmodul sind technisch getrennt. Das Forschungsmodul hat keinen Code-Pfad in Release-Builds. | 5.0 Teil V |
| A7 | Keine Drittanbieter-Pakete ohne `DECISIONS.md`-Eintrag. AGPL/GPL nie in App-Code. | CLAUDE.md, 5.0 Teil II |
| A8 | Jede Funktion trägt einen Nachweisstatus (Geplant … Abgenommen) in `ACCEPTANCE-MATRIX.md`. | 5.0 Teil XIII |

## 2. Schichten und Module

```
PulseExperience (App: Features/)        TODAY · HEALTH · INTELLIGENCE · COACH · NUTRITION · BODY · DEVICES & SETTINGS
        │
ClaudeIntelligence  CoachEngine  NutritionEngine  ClinicalContext   (PulseCore + dünne App-Adapter)
        │                 │              │               │
HealthEvidence  ◄─────────┴──────────────┴───────────────┘          Belegkatalog, Zahlenprüfer, Qualitätsnachweis
        │
HealthAnalytics                                                      Basislinien, Trends, SpO₂, Puls, HRV, Schlaf, Aktivität, Training
        │
HealthDataFoundation                                                 HealthSample, Dubletten, Profile, Qualität, Aggregate, Abdeckung, Export
        │
DeviceIntegration                                                    Colmi R03/R09, BLE-Pulsgurt, HealthKit, Oura (später), Diagnose
```

Regel: Ein Modul darf nur Module **unter** sich importieren. CoachEngine, NutritionEngine und ClinicalContext greifen nicht direkt auf Gerätecode zu.

## 3. Bestand → Zielmodul (Code-Abgleich)

| Bestehender Code | Zustand | Zielmodul | Maßnahme |
|---|---|---|---|
| `ColmiProtocol.swift`, `HeartRateLogParser.swift`, `ColmiModel.swift` | getestet, R03-Protokoll nur teils belegt | DeviceIntegration | Ortszeit (PR 2), Big-Data-Dienst nach Mitschnitt |
| `LiveMeasurement.swift`, `BLETrace.swift` (PR #9) | getestet | DeviceIntegration | iPhone-Nachweis offen |
| App `Bluetooth/ColmiCentral.swift`, `RingStore.swift` | iPhone: Verbinden ok, Puls offen | DeviceIntegration (App-Adapter) | Mitschnitt auswerten |
| App `Connect/HealthKitAdapter.swift` | gebaut, auf iPhone unbelegt | DeviceIntegration (App-Adapter) | Typ-Status, Beobachter, neue Typen (Release 1) |
| `Connect/DeviceAdapter.swift`, `AdapterCatalog.swift`, `DeviceRegistry.swift` | getestet | DeviceIntegration | Apple-Health-Status im Katalog aktualisieren |
| `Connect/HealthSample.swift`, `MeasurementNormalizer.swift`, `SyncCoordinator.swift`, `ProfileAssignment.swift`, `SourcePolicy.swift` | getestet (Review 3.2) | HealthDataFoundation | weiterverwenden |
| `Connect/DailySeries.swift` | getestet, nur Tageswerte | HealthDataFoundation | ersetzt durch materialisierte Aggregate (HEALTH-DATA-SPEC §5) |
| App `Persistence/StoredSample.swift` | SwiftData, eindeutiger Schlüssel | HealthDataFoundation | Schema versionieren (§6) |
| App `Persistence/StoredMeasurement.swift` | Altmodell, migriert | HealthDataFoundation | nach Release 2 entfernen |
| `RingSnapshot.swift`, `ConnectionState.swift`, `Capability.swift`, `VitalReading.swift` | getestet | DeviceIntegration | weiterverwenden |
| `HeartGeometry.swift`, `HeartSound.swift`, `Heartbeat.swift`, App `HeartChamber/*`, `Services/HeartFeedback.swift` | Prototyp | PulseExperience/BODY | Release 8, Datenbindung früher (Release 1: Zustand „kein Puls“) |
| App `Features/Connect`, `Features/Devices` | iPhone teils | PulseExperience/DEVICES | in Tab-Struktur überführen |

## 4. Navigation (Zielbild 5.0 Teil X)

Tab-Leiste mit fünf Tabs. Das ist die iOS-Grenze für eine lesbare Leiste, deshalb liegen BODY und NUTRITION nicht als eigene Tabs darin:
1. **Heute** (TODAY): Tageszentrale. Öffnet BODY (Heart Chamber) und den Ernährungstag.
2. **Gesundheit** (HEALTH): Messwerte, Trends, Quellen, Langzeit.
3. **Intelligence**: Claude-Berichte, Fragen, Verlauf.
4. **Coach**: Tagesplan, Programme, Übungen. Ab Release 5 kommt NUTRITION als Segment hinzu.
5. **Geräte & Einstellungen**: Sensoren, Profile, KI-Anbieter, Datenschutz, Export.

Release 1 führt die Tab-Struktur mit **Heute**, **Gesundheit** und **Geräte & Einstellungen** ein. Weitere Tabs erscheinen erst, wenn sie echte Funktion haben. Es gibt keine leeren Platzhalter-Tabs (4.0 §12).

## 5. Laufzeit und Nebenläufigkeit

- Oberfläche und Stores sind `@MainActor @Observable`. Die BLE-Zentrale läuft auf der Main-Queue, weil das Paketaufkommen gering ist (16-Byte-Pakete).
- HealthKit-Importe und Aggregation laufen in einem eigenen `@ModelActor` (`HealthArchiveActor`), damit große Importe die Oberfläche nicht blockieren. Das ist neu in Release 1/2.
- Hintergrund: HealthKit Background Delivery plus `BGProcessingTask` für Aggregate. Es gibt kein Echtzeitversprechen. Die BLE-Hintergrundverbindung (`bluetooth-central`) erst nach Bedarf, mit Entscheidung in `DECISIONS.md`.

## 6. Persistenz

- SwiftData mit **versioniertem Schema** (`VersionedSchema` + `SchemaMigrationPlan`) ab Release 1. Heute ist das Schema unversioniert (`PulseOneApp.makeContainer`).
- **Befund:** Scheitert das Öffnen der Datenbank, fällt `makeContainer` still auf einen Speicher im Arbeitsspeicher zurück. Messungen gingen dann beim Beenden verloren, ohne dass der Nutzer es merkt. Release 1 ändert das: Der Fehler wird sichtbar gemeldet, die Ringverbindung bleibt nutzbar, und es wird nichts gespeichert, ohne dass der Nutzer das erfährt.
- Dateischutz `completeUntilFirstUserAuthentication` (Hintergrund-Import muss nach dem ersten Entsperren schreiben können). iCloud-Backup erlaubt (Johannes, 2026-11-19).
- Geheimnisse (Claude-Schlüssel) nur im Keychain, `WhenUnlockedThisDeviceOnly`, nie in SwiftData, Logs oder der Diagnose.

## 7. Externe Dienste

| Dienst | Zweck | Release | Bedingung |
|---|---|---|---|
| Anthropic Messages API | Analysen, Vision (Ernährung) | 3, 5 | Schlüssel des Nutzers; Kosten freigegeben 2026-11-20; nur freigegebene Kategorien |
| Open Food Facts | Barcode, Lebensmittel | 5 | ODbL-Datenlizenz prüfen (Fachkonzept Ernährung) |
| USDA FoodData Central | Nährwerte | 5 | gemeinfrei, API-Schlüssel nötig |
| WHO ICD-11 API | Diagnosensuche | 7 | Lizenzbedingungen WHO (Fachkonzept Klinik) |
| Oura API | Datenquelle | später | OAuth, Nutzerkonto |

Keine Analyse- oder Tracking-SDKs. Netzwerkaufrufe gehen nur an die Dienste dieser Tabelle.

## 8. Widersprüche und Entscheidungen

| Widerspruch | Entscheidung |
|---|---|
| 5.0 nennt 7 Hauptbereiche, iOS-Tab-Leiste trägt 5 | 5 Tabs, BODY über Heute, NUTRITION im Coach (§4) |
| Directive 3.x: Zeit auf Ring in UTC; 3 Open-Source-Projekte: Ortszeit | Ortszeit (OPEN-SOURCE-REVIEW §2.2), Prüfung am R03 per Mitschnitt |
| „Live, soweit verfügbar“ vs. Wunsch nach durchgehender Überwachung | Live nur bei offener App und aktiver Messung. Kontinuierliche Werte kommen aus dem Ring-Verlauf und HealthKit |
| Wunsch nach „anatomisch besserem“ Herz vs. Release-1-Fokus | Heart Chamber bekommt in Release 1 nur korrekte Datenbindung und ehrlichen Zustand. Das 3D-Modell kommt in Release 8 |
