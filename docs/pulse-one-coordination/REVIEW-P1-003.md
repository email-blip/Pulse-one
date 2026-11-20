# P1-003 Reviewpaket – PULSE ONE (Stand 2026-11-20, 23:10 MEZ)

Keine echten Gesundheitsdaten, keine Secrets. Alle Werte in Screenshots stammen aus markierten Testszenarien (`-uiTesting YES`, Banner „Testansicht“).

## 1. Repository, Branch, Commit

| | Wert |
|---|---|
| Repo | https://github.com/email-blip/Pulse-one (öffentlich; native App Swift 6/SwiftUI/SwiftData, Ordner `apps/PulseOne`) |
| main | `f1408b843ce07fdcd2193c9e69b34044714684f8` (PR #16, Doku). Letzter Code auf main: `ac32af5` (PR #9) |
| Arbeitsbranch | `claude/project-thread-p4cjhd` = PR #14, Head `1f6c701` (Code-Commit `a6e5db5`, danach nur Doku) |
| Nur im PR #14, nicht auf main | Ring-Uhr in Ortszeit (BCD) statt UTC; Paket `0x73 0x0C` als Akku-Push; Doku 5.0 + ROADMAP |
| Ungesichert (lokal, nicht gepusht) | R1-5/R1-6, siehe `uncommitted-R1-5-R1-6.patch`: Datenbankfehler-Banner, Health-Typen Atemfrequenz/Grundumsatz/VO₂max/Gewicht/Größe, Trainingsdauer, Import-Status je Datentyp, automatischer Health-Abgleich beim Öffnen (15-min-Drossel). Nicht kompiliert (kein Mac), geht mit dem nächsten PR in CI |
| Auf dem iPhone | TestFlight-Build 0.1.0 (4) aus `ffd33cc` (Lauf https://github.com/email-blip/Pulse-one/actions/runs/44816266591). **Enthält PR #8/#9/#14 noch nicht**: keine Messphasen, kein Diagnose-Export, Ring-Uhr noch UTC |
| MyBotty | Expo-App MyBody, eingefroren; letzter main `d67c3ab`. Dein `49f7451` = MyBotty PR #6. Nicht Teil von PULSE ONE |
| ios-studio | Vorlage (Skills, Agenten, CI-Muster), keine App |

## 2. Dateien in diesem Paket

| Datei | Inhalt |
|---|---|
| `pulse-one-source-1f6c701.zip` | `git archive` von `1f6c701`, kompletter Quellstand inkl. `docs/pulse-one-coordination/` |
| `pulse-one-1f6c701.bundle` | `git bundle` mit voller Historie (Branch-Head + main). Prüfen: `git clone pulse-one-1f6c701.bundle pulse-one` |
| `KEY-FILES.md` | alle Swift-Dateien, `project.yml`, `Package.swift`, beide Workflows als Text mit Pfad |
| `uncommitted-R1-5-R1-6.patch` | `git diff` der ungesicherten Arbeit gegen `1f6c701` |
| `screenshots-9885a1c-iPhone17Pro.zip` | 18 CI-Screenshots (halbe Auflösung, JPEG) |

### Wegweiser zu den Schlüsseldateien (Pfade unter `apps/PulseOne/`)

| Thema | Dateien |
|---|---|
| Build-Konfiguration | `project.yml`, `Packages/PulseCore/Package.swift`, `.github/workflows/ios-ci.yml`, `.github/workflows/testflight.yml` |
| Profil / Registry / Adapter / Fähigkeiten | `PulseCore/Connect/DeviceRegistry.swift`, `ProfileAssignment.swift`, `DeviceAdapter.swift`, `AdapterCatalog.swift`, `PulseCore/Capability.swift`. Ein `UserProfile`-Typ mit Oberfläche existiert **nicht**; heute gibt es eine Eigentümer-Profil-ID (`SourcesStore.ownerID`) und Zeiträume je Gerät |
| CoreBluetooth Verbindung und Pulsabruf | `Sources/Bluetooth/ColmiCentral.swift` (Scan, Connect, Discovery, Notify, Realtime-Start/Continue/Stop, Ticker, Reconnect-Backoff), `RingStore.swift` |
| Parser / Protokoll | `PulseCore/ColmiProtocol.swift`, `HeartRateLogParser.swift`, `LiveMeasurement.swift`, `BLETrace.swift`, `ConnectionState.swift` |
| Persistenz / Sync / Resolver | `Sources/Persistence/StoredSample.swift`, `StoredMeasurement.swift`, `PulseCore/Connect/SyncCoordinator.swift`, `MeasurementNormalizer.swift`, `RingReadingMapping.swift`, `SourcePolicy.swift`, `DailySeries.swift`, `Sources/Connect/SourcesStore.swift` |
| HealthKit und Besitzerbindung | `Sources/Connect/HealthKitAdapter.swift`; Bindung an den Eigentümer in `SourcesStore.sync` (`profiles: .constant(ownerProfileID)`) |
| Onboarding / Präferenzen | Onboarding: **nicht gebaut**. Präferenzen je Messart: `SourcePolicy.swift`, `SourcesStore.setPreference` |
| Tests | `Packages/PulseCore/Tests/PulseCoreTests/*.swift` (Swift Testing), `UITests/AccessibilityTests.swift`, `InteractionTests.swift`, `ScreenshotTests.swift` |

## 3. Build-Nachweise (getrennt nach Art)

| Art | Lauf | SHA | Ergebnis |
|---|---|---|---|
| CI Simulator (letzter fertiger Code-Lauf, PR #9) | https://github.com/email-blip/Pulse-one/actions/runs/44823976253 (Job 136591725312) | `9885a1c` | grün. Xcode 26.6 auf `macos-26`, Swift 6. 91 Swift-Testing-Tests in 18 Suiten, 11 UI-Tests (5 Accessibility-Audits, 5 Interaktion, 1 Screenshot-Lauf), 0 Fehler. Simulatoren iPhone 17 Pro, 17 Pro Max, 17e |
| CI main nach Merge #9 | Lauf 22 | `ac32af5` | grün |
| CI PR #14 | https://github.com/email-blip/Pulse-one/actions/runs/44829262153 | `af58b31` | läuft |
| TestFlight (signiert) | Lauf 4, Link oben | `ffd33cc` | grün, auf Johannes' iPhone installiert. Läufe 1–3 rot (Signierung, behoben in PR #7) |
| Echtes Gerät mit R03 | Test Johannes 2026-11-20 mit Build 4 | `ffd33cc` | laut Johannes: Verbindung ja, **Pulsmessung scheitert**. Kein Mitschnitt vorhanden (Build 4 hatte noch keinen Export) |

CI-grün belegt nur Kompilieren, Logik-Tests und Simulator-Oberfläche. Keine R03-Funktion ist damit bestätigt.

## 4. Screenshots

Quelle: CI-Lauf 21, Commit `9885a1c`, Simulator iPhone 17 Pro, Datenmodus **Testszenario** (sichtbares Banner, feste Beispielwerte aus `TestScenario.swift`). Nur Dunkelmodus, weil die App ihn erzwingt. Varianten: Standardschrift und XXXL; `__reduced` = Reduce Motion.

| Bildname | Was es zeigt |
|---|---|
| `start` | Startzustand ohne Ring |
| `scanning` | Suche |
| `connected` | verbunden, keine Messung |
| `live` | Messung mit Testwert (Banner „keine echten Messwerte“) |
| `failed` | ehrlicher Fehlerzustand „Messung fehlgeschlagen“ mit Diagnose-Hinweis |
| `reconnecting` | Verbindung wird wiederhergestellt |
| `devices` | Geräte & Datenquellen inkl. Apple-Health-Karte (Stufe „kompatibel“) |
| `heart` | Heart Chamber |

**Nicht vorhanden, weil nicht gebaut:** Profil-Seite, Onboarding, HEUTE-Seite, eigene Health-Seite (Health steckt in „Geräte“). Es wurden dafür keine Platzhalterbilder erzeugt.

## 5. Nächste Schritte (P1-003)

1. PR #14 nach grüner CI mergen, TestFlight-Build auslösen (kostenlos, öffentliches Repo).
2. Code-Prüfung des Pulspfads in `ColmiCentral.swift`: GATT-Discovery, Notify-Bestätigung, Timeout, Abbruch, Reconnect. Unabhängig testbare Fehler zuerst, mit Regressionstest.
3. Minimaler Gerätetest für Johannes (unten), danach Ursache aus dem Mitschnitt belegen.

### Minimaler Gerätetest (nach neuem Build)

1. QRing-App beenden (der Ring erlaubt nur eine Verbindung).
2. Ring eng am Finger, Hand ruhig auf dem Tisch.
3. PULSE ONE öffnen → „Ring suchen“ → Ring antippen → warten bis „Verbunden“.
4. „Puls jetzt messen“ → 60 Sekunden warten, nichts antippen.
5. Nach unten scrollen → „Bluetooth-Diagnose teilen“ → Datei an Claude schicken.
