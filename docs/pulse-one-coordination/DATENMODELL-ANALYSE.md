# Datenmodell-Analyse und Migration (Directive 3.1, Paket A)

Stand 2026-11-20, Claude Code. **Abschnitte 4 (Dublettenschutz) und Profilwechsel sind durch Review 3.2 überholt: siehe ARCHITEKTUR-BERICHT-3.2.md.**

## 1. Bestand vor Directive 3.1

| Tabelle | Inhalt | Seit | Lücken gegenüber 3.1 |
|---|---|---|---|
| `StoredMeasurement` (SwiftData) | Ring-Werte aus M1: Metrik (Puls, Akku), Ganzzahl, Einheit als Text, Zeit, Herkunft (`ring_live`/`ring_history`), Gerätename, Geräte-ID, Modell, Firmware | M1 | keine Profilzuordnung, keine Importzeit, keine externe ID, kein Qualitätsstatus, kein Dublettenschutz, nur zwei Metriken |
| `StoredSample` (SwiftData) | normalisierter Messwert: Profil, Art, Wert (Double), kanonische Einheit, Beginn/Ende, Zeitzone, Quelle, Geräte-ID, Original-ID der Quelle, Importzeit, Qualität, Methode, Rohdaten-Verweis; eindeutiger `dedupKey` | M2 (PR #4) | alte M1-Zeilen fehlten; keine Zeitstempelprüfung; Quellenwahl kannte nur die Quelle, nicht das Gerät |
| `devices.json` (Registry) | Geräte mit Adapter, Quell-ID, Name, Profil, Integrationsstufe, Akku, Firmware, letzter Sync, letzter Wert, Sync-Cursor, Diagnose | M2 | – |

Seit PR #4 schreibt die App jeden Ring-Wert in **beide** Tabellen. Ältere Zeilen gab es nur in `StoredMeasurement`.

Ehrlicher Hinweis: Es existiert noch kein TestFlight-Build. Auf keinem iPhone liegen bisher echte Daten. Die Migration ist trotzdem vollständig gebaut und getestet, damit sie beim ersten echten Build mit älteren Daten sicher greift.

## 2. Abdeckung der Pflichtfelder aus 3.1 A

| Feld | Wo |
|---|---|
| Profilzuordnung | `profileID` (HealthKit nur Eigentümer: `RegistryError.healthKitOwnerOnly`) |
| Quelle und Gerät | `source` + `deviceID`, zusammen `SampleOrigin` |
| Typ und Einheit | `kind` + kanonische `unit` (Umrechnung im `MeasurementNormalizer`) |
| Mess- und Importzeit | `start`/`end`/`timeZoneIdentifier` und `importedAt` |
| externe ID | `originalSampleID` (HealthKit-UUID, Ring: siehe §4) |
| Qualität / Validierung | `quality` (plausibel/unplausibel, unplausible werden gespeichert, aber nie angezeigt); ungültige Werte werden abgelehnt und protokolliert |
| Messmethode | `method` (live, Geräteverlauf, Health-Speicher, Cloud, manuell) |
| Dublettenschutz | eindeutiger `dedupKey` (§4) |
| historische Zeitreihen | `DailySeries` (Tageswerte je Art, Grundlage für Trends und Baselines; keine Schlussfolgerungen) |
| nachvollziehbare Quellenpriorität | `DataSourceResolver` mit Quellen- und Gerätepriorität; `ResolvedTotal` und `DailyValue.origins` nennen die verwendete Herkunft |

## 3. Migration `StoredMeasurement` → `StoredSample`

- `SourcesStore.migrateLegacyMeasurements(marker:)`, beim App-Start.
- Jede alte Zeile wird zu `VitalReading` zurückgebaut und durch **dieselbe** Abbildung geschickt wie ein Live-Wert (`RawObservation(reading:)`). Dadurch entsteht derselbe Dublettenschlüssel.
- Verarbeitung je Gerät in Blöcken zu 500 über den normalen Sync-Pfad (Normalizer, Plan, Speichern).
- Profil: Profil des Geräts aus der Registry, sonst Eigentümer.
- Marker `migration.storedMeasurement.v1` in UserDefaults erst nach dem letzten erfolgreichen Speichern. Bricht die App ab, läuft die Migration beim nächsten Start erneut; bereits übernommene Werte zählen als „unverändert“.
- Alte Zeilen bleiben erhalten (Rückweg, Prüfbarkeit). Heart Chamber und Verlaufskarte lesen sie weiterhin; die Umstellung der Anzeige auf `StoredSample` folgt mit dem TODAY-Screen.
- Zeilen mit unbekannter Metrik/Herkunft oder unplausiblem Wert werden übersprungen und gezählt (`MigrationReport.skipped`).

## 4. Dublettenschutz (bitte prüfen)

Schlüssel: `quelle | geräte-id | art | original-id`.

- Zwei Geräte derselben Quelle (zwei Ringe) haben verschiedene Geräte-IDs, also nie denselben Schlüssel. Nichts wird überschrieben.
- Ring: Der Ring liefert keine eigene Proben-ID. Original-ID = `live-<ms>-<art>` bzw. `history-<ms>-<art>` (Zeit in Millisekunden, gerundet). Live- und Verlaufswert zur selben Millisekunde bleiben getrennt, weil es zwei verschiedene Messwege sind. Ob der Ring denselben Wert live und im 5-Minuten-Log liefert, klärt der Realtest; die Anzeige wählt ohnehin pro Minute nur eine Herkunft.
- HealthKit: Original-ID = HealthKit-UUID. Gelöschte Health-Proben werden über den Anker gemeldet und entfernt.
- Der Schlüssel enthält das Profil bewusst nicht: Ein Quellwert gehört genau einer Person. Wird ein Gerät einer anderen Person zugeordnet, ändert ein erneuter Sync nur das Profil (Update, kein Duplikat). Live-Ringwerte werden nicht neu synchronisiert und bleiben bei der Person, die den Ring damals trug.
- Doppelzählung über Quellen hinweg (Ring-Schritte + iPhone-Schritte) verhindert nicht der Schlüssel, sondern der `DataSourceResolver`: Summen kommen immer aus genau einer Herkunft, Punktwerte je Minute aus genau einer Herkunft, nie gemittelt.
- Offene Frage an Codex: Soll die Gerätepriorität vom Nutzer einstellbar sein (Geräte-Screen) oder fest „zuletzt hinzugefügt gewinnt“? Derzeit: optional per Parameter, sonst stabile Reihenfolge nach Geräte-ID.

## 5. Zeitstempel

Abgelehnt (nicht gespeichert, in der Diagnose des Geräts protokolliert):
- Beginn vor 2010-01-01 (nicht gestellte Ring-Uhr, 1970/2000),
- Beginn mehr als 10 Minuten nach der Importzeit (falsche Geräte-Uhr),
- Ende vor Beginn.

## 6. QA-Matrix (Directive 3.1 §6)

| Fall | Test |
|---|---|
| wiederholte Synchronisation | `DirectiveQATests.repeatedSyncIsIdempotent`, `SyncCoordinatorTests.secondSyncOfTheSameDataChangesNothing` |
| zwei Geräte mit überlappenden Daten | `twoDevicesOfTheSameSourceAreStoredApartAndResolvedByPriority`, `DataSourceResolverTests.*`, `DailySeriesTests.cumulativeDaysUseOneOriginOnly` |
| unterschiedliche Einheiten | `differentUnitsEndUpCanonical`, `NormalizerTests.convertsUnits` |
| fehlerhafte Zeitstempel | `faultyTimestampsAreRejectedNotStored` |
| abgebrochene Synchronisation | `interruptedMigrationResumesWithoutDuplicates`; App: Health-Cursor wird erst nach erfolgreichem Speichern gesichert |
| Profilwechsel | `profileSwitchMovesResyncedSamplesWithoutDuplicates`, `DeviceRegistryTests` (HealthKit nur Eigentümer) |
| fehlende HealthKit-Berechtigung | `healthSyncWithoutDataIsFlagged`; UI-Test prüft den Hinweis im Geräte-Screen |
| bestehende R03-Funktion | `liveAndMigratedReadingGetTheSameKey`, `migrationAfterDualWriteAddsNothing`, bestehende `ColmiProtocolTests`; UI-Test prüft übernommene Ringwerte im Geräte-Screen |

## 7. Status nach Directive 3.1 §8

| Teil | Stufe |
|---|---|
| Datenmodell, Migration, Dublettenschutz, Zeitreihen | Implementiert → Gebaut/Simulator, sobald CI grün |
| Apple Health | Implementiert, gebaut; Hardwaretest braucht TestFlight |
| Ring über gemeinsamen Pfad | Implementiert, gebaut; Hardwaretest braucht TestFlight + R03 |
| Oura, generisches BLE, R09 | Geplant (Katalog-Einträge vorhanden, keine Datenwege) |
