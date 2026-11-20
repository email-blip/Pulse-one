# Architekturbericht zu Review 3.2

Stand 2026-11-20, Claude Code. Grundlage: PR #5 (gemergt). Änderungen auf Branch `claude/project-thread-p4cjhd`, PR folgt nach grünem CI.

## 1. Geänderte Dateien

Kern (`apps/PulseOne/Packages/PulseCore/Sources/PulseCore/Connect/`):
- `ProfileAssignment.swift` (neu): `DeviceAssignment`, `ProfileTimeline`, Übergabe und Korrektur von Zeiträumen.
- `SourcePolicy.swift` (neu): `SourceChoice`, `SourcePreferences`, `UsageContext`, `SourcePolicy` (Automatik je Messwertart und Situation), `ResolutionReason`.
- `HealthSample.swift`: `profileID` optional (nil = ungeklärt), Qualitätsstufen + `qualityReason`, `SampleIdentity`, `SampleAggregation`, `measurementSite`, `DataSourceKind.title`, Methoden-Rangfolge.
- `MeasurementNormalizer.swift`: Qualitätsbewertung mit Grund, `deviceFlag`, `identity`.
- `RingReadingMapping.swift`: Ersatzidentität mit Wert und optionalem Intervall.
- `SyncCoordinator.swift`: Plan über `ProfileTimeline`, Profil gespeicherter Werte bleibt, `conflicts`, `reattribute`; Resolver über `SourcePolicy`, Methoden-Vorrang, stündliche Zusammenführung von Zählern.
- `DailySeries.swift`: Aggregation je Wertart, `sampleIDs`, `coveredHours`.
- `DeviceRegistry.swift`: Zuordnungsverlauf, `correctAssignment`, Präferenzen je Profil, rückwärtskompatibles Laden.
- `AdapterCatalog.swift`: `sourceKind(adapterID:)`.

App: `Persistence/StoredSample.swift` (Schema, `reattribute`), `Connect/SourcesStore.swift` (Zeitachsen statt fester Profile, Korrektur, Präferenzen), `Features/Devices/DevicesScreen.swift` (Karte „Bevorzugte Quellen“), `UITests/InteractionTests.swift`.

Tests: `Review32Tests.swift` (neu), `MigrationAndQATests.swift` und `ConnectTests.swift` angepasst.

## 2. Datenbankschema und Migrationsfolgen

`StoredSample` (SwiftData, leichte Migration ohne Code):
- `profileID: UUID` → `UUID?` (nil = ungeklärter Zeitraum).
- neu `qualityReason: String?`.
- neu `identityRaw: String = "source_id"` (Standardwert für bestehende Zeilen).
- `qualityRaw` kennt neue Werte (`valid`, `incomplete`, `time_uncertain`, `technical_error`); alte Werte bleiben gültig.

`devices.json` (Registry): neu `assignments` je Gerät und `preferences` je Profil. Alte Dateien laden weiter: fehlende Historie wird zu einem offenen Zeitraum mit Grund „Übernommen aus Version ohne Zuordnungsverlauf“ (getestet).

Ring-Ersatzidentität hat ein neues Format (Wert im Schlüssel). Folge: Ringwerte, die mit dem alten Format gespeichert wurden, würden beim nächsten Import doppelt gespeichert. **Es gibt bisher keinen Build auf einem iPhone, also keine solchen Daten.** Die Migration aus `StoredMeasurement` erzeugt die neuen Schlüssel.

## 3. Profilzuordnung

- Jedes Gerät hat Zeiträume `(Profil oder ungeklärt, von, bis, Grund, erfasst am)`.
- Ein neuer Wert bekommt das Profil, das zu **seinem Messzeitpunkt** galt. Außerhalb jedes Zeitraums oder in einem ungeklärten Zeitraum: `profileID = nil`.
- Ein Sync ändert das Profil gespeicherter Werte nie (Test `resyncAfterProfileSwitchKeepsHistoricProfile`, `historicSamplesStayWithTheirProfile`).
- Übergabe (`assign … from:`) beendet den laufenden Zeitraum. Eine Übergabe vor dessen Beginn wird abgelehnt; dafür gibt es die Korrektur.
- Korrektur (`correctAssignment`) schneidet überlappende Zeiträume, speichert Grund und Zeitpunkt, schreibt eine Diagnosezeile; danach ordnet `reattribute` genau die betroffenen Werte neu zu.
- Apple Health: immer Eigentümer (fester Zeitraum).
- Erstzuordnung gilt ab „immer“ (auch für den Ringspeicher vor dem Hinzufügen, ca. 7 Tage); der Grund sagt das. Grenze: Wird ein Ring entfernt und von einer anderen Person neu hinzugefügt, landen die alten Speicherdaten bei der neuen Person, sofern niemand korrigiert.
- Noch keine Oberfläche für Übergabe/Korrektur: Es gibt bisher nur ein Profil (Profile kommen mit M3). Die Logik und die App-Funktion `SourcesStore.correctAssignment` sind fertig.

## 4. Dublettenschutz und seine Grenzen

Schlüssel bleibt `quelle | geräte-id | art | original-id`. Neu ist, wie die Original-ID entsteht und was danach passiert:

| Stufe | Wann | Original-ID | Verhalten |
|---|---|---|---|
| A Quellen-ID | Quelle liefert eigene ID (HealthKit-UUID, später Oura) | ID der Quelle | gleiche ID = gleiche Probe; geänderter Wert = Update (Profil bleibt); zwei Werte mit gleicher ID im selben Import = `conflicts` + erster gewinnt |
| B Ersatzidentität | Ring ohne Proben-ID | `live|history - ms - [i<Intervall>] - art - v<Wert>` | gleicher Wert erneut importiert = keine Dublette; zwei verschiedene Werte zur selben Zeit = zwei Proben |
| C Inhaltliche Überlappung | verschiedene Proben, gleicher Vorgang | – | nichts wird gelöscht; Auswertung wählt je Minute eine Herkunft und darin einen Messweg (live vor Verlauf), je Stunde eine Herkunft für Zähler, je Tag eine Herkunft für Intervalle und abgeleitete Werte |

Geprüfte Fälle: Live/Verlauf (Test 4), mehrfacher Verlaufsimport (Test 3), gleiche Zeit verschiedene Werte (Test 2), Gerätewechsel zwischen Personen (Test 1, 10), Ring und HealthKit (Test 5).

Grenzen (ehrlich):
- Zeitauflösung: Der Ring-Verlauf liefert 5-Minuten-Slots. Das Intervall ist im Schlüssel vorgesehen, wird aber erst mit dem angebundenen Verlaufsimport gesetzt.
- Firmware-Wechsel, der Zeitstempel anders rundet: alter und neuer Import ergeben verschiedene Schlüssel. Gespeichert wird doppelt, gezählt nur einmal (Auswertung je Minute).
- Derselbe Wert zweimal zur selben Millisekunde aus zwei echten Messungen wird als eine Probe behandelt. Beim Ring praktisch ausgeschlossen.
- QRing-App schreibt Ringdaten eventuell nach Apple Health. Dann beschreiben Ring- und Health-Probe denselben Vorgang mit verschiedenen Herkünften. Die Auswertung zählt sie je Minute/Stunde nur einmal; erkannt wird das aber nicht ausdrücklich (`rawDataReference` enthält die Bundle-ID; Abgleich folgt nach Realtest).

## 5. Gerätepriorität

`SourcePolicy.choose(kind:among:)`, deterministisch, Grund wird mitgeliefert:
1. Präferenz des Profils für die Messwertart (`konkretes Gerät` oder `Quellsystem`, z. B. Apple Health), wenn sie hier Daten hat → `preferred`.
2. Sonst Automatik je Messwertart und Situation (`general`, `workout`, `rest`) → `automatic`; war eine Präferenz gesetzt, aber ohne Daten → `fallback(preferredMissing:)`.
3. Innerhalb eines Quellsystems: optionale Geräteliste, dann Geräte-ID. „Zuletzt hinzugefügt gewinnt“ gibt es nicht.

Automatik (Auszug): Puls allgemein Pulsgurt › Ring › Oura › Health; beim Sport Pulsgurt › Health › Ring; in Ruhe Ring › Oura › Health. Ruhepuls Oura › Health › Ring. Schlaf Oura › Ring › Health. Schritte/Energie/Strecke Health › Ring › Oura. Hauttemperatur Ring › Oura; Temperaturabweichung Oura › Health › Ring; Körpertemperatur Eingabe › Health. Vollständig in `SourcePolicy.automaticOrder`.

Oberfläche: Geräte-Screen, Karte „Bevorzugte Quellen“, je Messwertart Auswahl „Automatisch“ oder ein verbundenes Gerät, darunter die automatische Reihenfolge. Gespeichert je Profil in der Registry. Die Situation (Sport/Ruhe) wird noch nicht automatisch erkannt; die App nutzt bis zum Trainingsmodul `general`.

## 6. Datenqualität

Reihenfolge der Regeln (erste trifft): Gerät meldet Fehler → `technisch fehlerhaft`; außerhalb des plausiblen Bereichs → `unplausibel`; Intervall ohne Ende → `unvollständig`; Zeit liegt bis 10 min in der Zukunft oder Zeitzone fehlt → `zeitlich unsicher`; Quelle am Gerät bestätigt → `gültig`; sonst `plausibel, unbestätigt`. Jede Bewertung speichert ihren Grund. Harte Fehler (keine Zahl, falsche Einheit, Ende vor Beginn, vor 2010, mehr als 10 min Zukunft) werden abgewiesen und protokolliert.

Nur `gültig` und `plausibel` gehen in Auswertungen, Tageswerte und später den Coach. Da noch keine Quelle am iPhone bestätigt ist, ist heute nichts `gültig`. Der Coach kann `coveredHours` und Qualität nutzen, um Unsicherheit auszusprechen.

## 7. Tageswerte

| Art | Beispiele | Tageswert |
|---|---|---|
| Punkt | Puls, HRV, SpO₂, Temperatur | Mittel der aufgelösten Minutenwerte |
| Intervall | Schlaf, Training | Vereinigung der Zeitspannen einer Herkunft (Überlappung nicht doppelt) |
| Zähler | Schritte, Energie, Strecke, Höhe | Summe über Stunden, je Stunde eine Herkunft |
| Abgeleitet | Ruhepuls, Temperaturabweichung | letzter Wert einer Herkunft |
| Herstellerscore | (noch keine) | wie abgeleitet, nie zwischen Herstellern gemischt |

Jeder Tageswert trägt `origins`, `sampleIDs` und `coveredHours`. Rohwerte bleiben unverändert gespeichert.

## 8. Tests

`Review32Tests` (Nummern wie Review §7): 1 `historicSamplesStayWithTheirProfile`, `unclearPeriodsAreUnresolvedAndCorrectionsAreLogged`; 2 `sameTimestampDifferentValuesAreBothKept`; 3 `repeatedHistorySyncAddsNothing`; 4 `liveAndHistoryOfTheSameMinuteCountOnce`; 5 `differentSourcesOnOneDayFillGapsWithoutDoubleCounting`; 6 `manualPreferenceWins`; 7 `missingPreferredSourceFallsBackVisibly`; 8 `incompleteDaysShowTheirCoverage`; 9 `faultyAndUncertainValuesAreKeptButNeverAnalysed`; 10 `migrationResumesAndUsesTheTimeline`. Zusätzlich: Schlaf-Überlappung, rückwärtskompatible Registry, Temperatur-Messort. Angepasst: Profilwechsel-Test (jetzt: Profil bleibt), Schritte-Tageswert (stündliche Zusammenführung). UI-Test prüft die Karte „Bevorzugte Quellen“.

## 9. CI-Ergebnis

CI-Lauf 17 (Commit 1eb1f88) **grün**: https://github.com/email-blip/Pulse-one/actions/runs/44808903967
- Kern-Tests (Swift Testing) alle bestanden, inklusive aller `Review32Tests` und der angepassten Tests aus 3.1.
- App-Build, UI-Tests (inklusive Karte „Bevorzugte Quellen“), Bedienungshilfen-Prüfung, Screenshots 3 Geräte × Standard/xxxl (Branch `ci-screenshots/claude/project-thread-p4cjhd`).
- Vorläufe: Lauf 15 rot (Typprüfung im Test zu langsam, Ausdruck aufgeteilt), Lauf 16 rot (1 von 76 Tests: Testspeicher importierte vor dem Messzeitpunkt, Wert galt korrekt als „zeitlich unsicher“; Testdatum korrigiert).

Stufe: Implementiert → Gebaut → Simulatorgetestet (nur Logik und Oberfläche mit Testdaten). Keine Hardwareprüfung.

## 10. Offene Hardwareprüfungen

Nichts davon ist an echter Hardware geprüft:
- R03: Verbindung, Akku, Firmware, Live-Puls, Zeitstempel und Auflösung des Verlaufs, Verhalten nach Firmware-Update.
- Apple Health: Freigabe-Dialog, Import, Löschungen, leere Antwort bei verweigerter Freigabe, Überlappung mit QRing-Einträgen.
- R09: nicht geliefert.
Voraussetzung bleibt TestFlight (Schritte in TESTFLIGHT-EINRICHTEN.md).
