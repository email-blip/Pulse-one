# Open-Source-Review nach Directive 4.2

Stand: 2026-11-20. Verfasser: Claude Code. Alle 10 Repositories wurden geklont (Stand `HEAD`, flach) und der **Quellcode** gelesen, nicht nur die README. Nichts davon wurde ausgeführt oder installiert. Es wird **kein fremder Code kopiert**. Wir bauen die Konzepte in Swift neu, mit eigenen Tests. Falls später doch ein Stück übernommen wird, kommen der Lizenzhinweis und ein Eintrag in `DECISIONS.md` dazu.

## 1. Übersicht und Entscheidung

| Projekt | Sprache | Lizenz | Tests | Entscheidung |
|---|---|---|---|---|
| anikbharadwaj129/Colmi | Swift/SwiftUI (iOS) | Apache-2.0 | 0 | **Konzepte übernehmen** (Ring) |
| reuhenbhalod/DayBreak | Kotlin (Android) | MIT | 18 Dateien | **Konzepte übernehmen** (Ring, Parser-Tests) |
| orviwan/mcp-for-colmi-smartring | Python | MIT | 3 Dateien | **Nur Referenz**, teils unzuverlässig |
| stansz/smart-ring | Python + TS (Server) | MIT | 16 Dateien | **Konzepte übernehmen** (R09, Datenqualität) |
| Polinss3/HealthBridge | Swift + Python | Apache-2.0 | 1 Datei | **Nur Referenz** (Schlaf-Intervalle) |
| PulsHealth/pulshealth | Swift-Paket (Swift 6) | Apache-2.0, Markenschutz | 52 Dateien | **Hauptvorlage HealthKit-Sync** (Konzepte) |
| rorydavidson/myhealth | Swift/SwiftData + TS | MIT | 4 iOS-Dateien | **Nur Referenz** (Tageswerte, Claude-Vorschau) |
| aninda-ghosh/openFitness | Swift (iOS) | **keine Lizenzdatei** | 0 | **Nur Referenz**, nichts kopieren |
| sahielbose/Tideline | TypeScript (Server) | MIT | 9 Dateien | **Konzepte übernehmen** (Basislinien, Trends) |
| nikira-studio/healthquery | Python (Server) | MIT | 6 Dateien | **Nur Referenz** (Dubletten, Abdeckung) |

Kommerzielle Wiederverwendung: MIT und Apache-2.0 erlauben das mit Lizenzhinweis. openFitness hat keine Lizenzdatei, rechtlich gilt deshalb „alle Rechte vorbehalten“. PulsHealth schützt Name und Marke.

## 2. Ringprotokolle

### 2.1 Relevante Dateien
- Colmi (Swift): `RingApp/RingProtocol.swift` (`UARTCommand`, `MonitoringKind`, `RealtimeSample`, Big-Data-Framer), `RingApp/RingConnection.swift` (`startRealtime`, `keepRealtimeAlive`, `measure(_:seconds:)`, Dienstsuche).
- DayBreak (Kotlin): `protocol/.../Commands.kt` (`Requests.setTime`, `startRealTime`, `getSteps`), `Parsers.kt` (`RealTimeParser`), `BigData.kt`, `BigDataReassembler.kt`, `Spo2Parser.kt`, `HeartRateLogAssembler.kt`, `SleepParser.kt`, `app/.../ble/RealRingClient.kt`, `app/.../ui/DiagnosticsScreen.kt`.
- stansz (Python): `collector/ring_client.py` (`_poll_real_time_reading`, `set_time_local`), `collector/protocol/parsers/_big_data.py`, `spo2.py`, `hrv.py`, `temp.py`, `steps.py`, `collector/analytics/data_quality.py`.
- orviwan (Python): `docs/colmi_ble_protocol_spec.md`, `tools/colmi_packet.py`.

### 2.2 Abgleich mit unserem Code (Fehlerdiagnose)

| Thema | PULSE ONE heute | Fremdprojekte | Bewertung |
|---|---|---|---|
| Echtzeitpuls starten | `69 01 01`, Antwort `69 01 <fehler> <bpm>` | identisch in Colmi, DayBreak, stansz | Kommando stimmt mit 3 Quellen überein |
| Erste Antworten | Wert 0 wurde still verworfen | alle verwerfen 0 und warten auf ≥ 6 echte Werte; stansz: bis 20 × 2 s | Wertlogik passt. **Fehler war die fehlende Rückmeldung** (mit PR #9 behoben) |
| „Weiter“-Befehl | alle 20 s `69 01 03` | Colmi: alle 20 s, „Strom endet nach ~30 s ohne Weiter“ | passt |
| Live-Puls mit RR-Abständen | nicht genutzt | Colmi: Typ `0x05` liefert RR-Intervalle (Bytes 6–7, ms) | Kandidat für HRV, erst nach Mitschnitt |
| **Uhrzeit setzen** | **UTC** + Sprachbyte | Colmi, DayBreak, stansz (laut Gadgetbridge): **Ortszeit** als BCD | **Abweichung.** Unser Ring läuft um 1 h falsch, Verläufe wären verschoben → ändern |
| Zweiter Datendienst | nicht abonniert (seit PR #9: nur mitlesen) | `DE5BF728…`, schreiben `…72A`, Benachrichtigung `…729`; Anfrage `BC <typ> 01 00 FF 00 FF` | für SpO₂, Schlaf, Temperatur nötig |
| SpO₂-Verlauf | fehlt | Big Data Typ `0x2A`: je Tag `[TageZurück][24 × (min, max)]` | 2 Quellen; **Widerspruch:** DayBreak beendet bei TageZurück = 0, stansz sieht 0 als „heute“. Nur per Mitschnitt klärbar |
| Statusmeldungen `0x73` | als „unbekannt“ gezählt | Colmi: `73 0C <akku> <lädt>` ist eine Akku-Meldung des Rings | erklärt wahrscheinlich einen Teil der 4 „unbekannten“ Antworten |
| Ring-Einstellungen | fehlen | `0x16` Puls-Intervall (bestätigt), `0x2C` SpO₂, `0x36` Stress, `0x38` HRV (geschlossen) | nur lesen, bis am R03 belegt |
| HRV-/Stress-Verlauf | fehlt | `0x39` / `0x37`, mehrteilig (Kopfpaket + Daten) | später |
| R09 | – | stansz: Firmware 3.10.21, Verbindungsfehler nach Trennen, Schritte mehrteilig, Taktung beobachtet | wertvoll für R09-Adapter |

Ergebnis: Das Pulskommando ist nach drei unabhängigen Quellen richtig. Wahrscheinlichste Ursachen für „kein Wert“: Der Ring lieferte nur Nullwerte (Sitz, Bewegung, Sensor sucht), oder er meldete einen Fehlercode, den die alte Oberfläche nicht deutlich zeigte. Belegen kann das erst der Diagnose-Mitschnitt aus PR #9. Fest steht schon jetzt ein zweiter Fehler: Die Ringuhr wird auf UTC statt auf Ortszeit gestellt.

### 2.3 Nicht übernehmen
- orviwan: Die Protokollbeschreibung enthält Fehler. Uhrzeit als `uint16`-Jahr widerspricht allen anderen Quellen. Dazu kommen „Blutzucker“ und „EKG“ als Messarten. **Nicht als Quelle für Befehle verwenden.**
- Synthetische Werte des Rings (Blutdruck Typ 2, Blutzucker Typ 9, „Fatigue“): nie anzeigen.
- Firmware-Flasher und Rohsensor-Mods: kein Bedarf.

## 3. HealthKit und Langzeitdaten

| Konzept | Quelle | Übernahme |
|---|---|---|
| Ein Beobachter für alle Typen (`HKObserverQuery(queryDescriptors:)`), Bündelung der Benachrichtigungen mit fester Frist | PulsHealth `HealthSyncEngine.swift` | ja |
| Hintergrund-Lieferung je Typ, `completionHandler` immer aufrufen | PulsHealth, myhealth | ja, ohne Echtzeitversprechen |
| Anker erst **nach** dem Speichern sichern | PulsHealth (anchor-after-ack) | ja; myhealth macht es falsch |
| Kein Abruf bei gesperrtem Gerät (`isProtectedDataAvailable`) | PulsHealth | ja |
| Status je Typ: letzter Lauf, Fehler, Pause, Anzahl | PulsHealth `SyncStateStore.swift` | ja → Einrichtungsscreen |
| Langzeitreihen mit `HKStatisticsCollectionQueryDescriptor`, Optionen aus `aggregationStyle`, Kalender-Buckets in Ortszeit, Lookback 7 Tage, monatliche Vollberechnung | PulsHealth `AggregateSync.swift` | ja |
| Tageswerte mit eindeutigem Schlüssel `Typ|Tag|Quelle`, nur betroffene Tage neu berechnen | myhealth `DailySummary`, `AggregationService` | ja, mit Ortszeit-Tagen statt UTC |
| Import-Protokoll je Lauf | myhealth `HealthImport` | ja |
| Schlaf: Sitzungen nach Lücke > 30 min, Überlappungen je Phase zusammenführen | myhealth `SleepSessionGrouper`, HealthBridge `mergedIntervals` | ja |
| Vorschau „Diese Daten gehen an Claude“ | myhealth `dataSentPreview` | ja |

Nicht übernehmen: Hochladen auf Server (HealthBridge, PulsHealth, myhealth), Quellwahl über Markennamen, Schritte von Hand summieren (Doppelzählung iPhone + Uhr), UTC-Tage, `try?` beim Ankerspeichern, SSE-Parser byteweise (zerstört Umlaute), Abo-Modell, Marke PulsHealth.

## 4. Auswertung und KI

| Konzept | Quelle | Übernahme |
|---|---|---|
| Robuste Basislinie: Median + 1,4826 × MAD, **ohne die letzten 21 Tage**, Mindestanzahl je Messart, sonst Zustand „Basislinie entsteht“ | Tideline `drift/stats.ts`, `drift/index.ts` | ja |
| Trend: lineare Steigung über 21 Tage, mindestens 4 Werte; Abweichung nur bei **anhaltenden** Werten (z. B. 2–3 in Folge) | Tideline | ja, Schwellen als „Beobachtung“, nicht als Alarm |
| Jede Aussage mit Belegobjekt (Basislinie, letzter Wert, Steigung, n) | Tideline `evidence`, healthquery `evidence[]` | ja → HealthEvidence |
| Feste Textausgabe ohne KI, wenn kein Schlüssel da ist | Tideline `explainSignalRule` | ja (Pflicht nach 4.2 §5) |
| Abdeckungsblock: abgedeckte und fehlende Tage | healthquery `reporting.py` | ja |
| Dubletten über natürliche Schlüssel `Quelle:Messart:Start:Ende` | healthquery `ingest.py` | haben wir schon (Review 3.2) |
| Prompt-Regeln: Zahlen nur wörtlich übernehmen, nicht selbst rechnen, keine Normbereiche erfinden | openFitness `AIInsightEngine.swift` | ja, als eigene Formulierung |
| ln(HRV) gegen persönliche Basislinie mit Mindest-Streuung | openFitness, stansz `hrv.py` | ja, als Statistik, nicht als „Score“ |
| Beobachtete Ring-Taktung (Puls ≈ 15 min, SpO₂ ≈ 60 min) als Vollständigkeitsmaß | stansz `data_quality.py` | ja, nach eigener Messung am R03 |

Nicht übernehmen:
- Recovery-, Strain-, Energy- und Stress-Scores (openFitness, stansz `readiness.py`, DayBreak `scoring/`). Ihre Konstanten sind unbelegt, solche Scores widersprechen 4.2 §2.
- Ersatzwerte bei fehlenden Daten (openFitness setzt SpO₂ 98 %, Atmung 14,5, Temperatur 36,6 °C): **verboten**, fehlende Daten heißen „zu wenig Daten“.
- Triage-Stufen „dringend/Notfall“ (Tideline): diagnostisch.
- KI-Text, der die geprüfte Antwort ersetzt (healthquery).
- Roh-SQL für das Modell (healthquery).

**Lücke bei allen 10 Projekten:** Keines prüft die Zahlen in der KI-Antwort gegen die Eingabedaten. Diesen Prüfer bauen wir selbst (Abschnitt 6). Keines hat eine echte SpO₂-Nachtanalyse (Entsättigungen, Artefakte). Die SpO₂-Regeln definieren und dokumentieren wir selbst.

## 5. Zielarchitektur nach 4.2 §3 (Abbildung auf den Code)

| Modul | Ort | Heute vorhanden | Neu |
|---|---|---|---|
| DeviceIntegration | `PulseCore/DeviceIntegration` + App `Bluetooth/`, `Connect/` | ColmiProtocol, ColmiCentral, HealthKitAdapter, AdapterCatalog, LiveMeasurement, BLETrace | Ortszeit, Big-Data-Dienst, `0x73`, Typ-Status HealthKit, Beobachter |
| HealthDataFoundation | `PulseCore/HealthDataFoundation` + SwiftData | HealthSample, Normalizer, SyncCoordinator, Dublettenschutz, ProfileAssignment, SourcePolicy, DailySeries | `DailyMetricSummary`, Import-Protokoll, Abdeckung |
| HealthAnalytics | `PulseCore/HealthAnalytics` | – | Basislinie (Median/MAD), Trend, Abweichung, SpO₂ zuerst |
| HealthEvidence | `PulseCore/HealthEvidence` | – | Belegkatalog, Berechnungsreferenz, Qualitätsnachweis, **Zahlenprüfer** |
| ClaudeIntelligence | `PulseCore/ClaudeIntelligence` + App | – | Keychain, Kontext v1, JSON-Schema, Prüfung, Verlauf |
| PulseExperience | App `Features/` | Verbinden, Geräte, Heart Chamber | TODAY, ANALYTICS, INTELLIGENCE, MOVE, BODY, DEVICES |

Die Module werden als Ordner im Paket `PulseCore` angelegt, nicht als eigene Pakete. Das hält die CI-Zeit klein. Abhängigkeiten laufen nur in eine Richtung: Experience → Intelligence → Evidence → Analytics → Foundation → Integration.

## 6. Belegprüfung von KI-Aussagen (eigene Entwicklung)

1. Die App baut einen `HealthAnalysisContext` (Version 1). Jede Kennzahl hat eine feste ID, z. B. `spo2.night.median.7d`, mit Wert, Einheit, Zeitraum, n und Quelle.
2. Claude antwortet nach JSON-Schema. Jede Zahl in der Antwort steht in einem Feld `{wert, einheit, beleg_id}`.
3. Der Prüfer vergleicht jeden Wert mit dem Kontextwert dieser ID (Toleranz: Rundung auf die angezeigte Stelle). Unbekannte ID, falscher Wert oder eine Zahl im Freitext ohne Beleg → die Aussage wird als „nicht belegt“ markiert und nicht als Befund angezeigt.
4. Die lokale Analyse (Abschnitt 4) liefert dieselben Kennzahlen ohne Claude. Die App bleibt ohne Schlüssel voll nutzbar.

## 7. Priorisierte Pull Requests (ersetzt SANIERUNG-4.0 §9 ab PR 2)

| # | Inhalt | Module | Nachweis |
|---|---|---|---|
| 1 | Messzustände + BLE-Diagnose (PR #9) | DeviceIntegration | CI, dann iPhone-Mitschnitt |
| 2 | Dieses Review; Ringzeit auf Ortszeit; `0x73`-Akkumeldung erkennen; neuer TestFlight-Build | DeviceIntegration | Tests, iPhone |
| 3 | HealthKit: Typ-Status, Beobachter + Bündelung, Anker nach Speichern, neue Typen (Training, Ruheenergie, VO2max, Atemfrequenz, Gewicht, Größe), Einrichtungsscreen | DeviceIntegration, Experience | iPhone |
| 4 | Langzeitreihen: `HKStatisticsCollectionQuery`, `DailyMetricSummary`, Abdeckung | Foundation | Tests |
| 5 | **SpO₂ vertikal:** Health-SpO₂ + Ring-SpO₂ (live Typ 3; Verlauf `0x2A` erst nach Mitschnitt), Basislinie, Nachtwerte, Abdeckung, Anzeige mit Diagramm | Analytics, Evidence, Experience | Tests, iPhone |
| 6 | Claude verbinden (Keychain, Test, Modelle, Kosten), Kontext v1 für SpO₂, Schema, Zahlenprüfer, INTELLIGENCE-Ansicht | ClaudeIntelligence | Tests, iPhone mit Johannes' Schlüssel |
| 7 | Übertragung auf Puls, Ruhepuls, HRV, Schlaf, Aktivität; TODAY und ANALYTICS | alle | Tests, iPhone |
| 8 | MOVE (Training), BODY, Coach | Experience | später |

## 8. Technische Risiken
- Ring-Firmware RY03_3.00.21: Alle Quellen stammen von R02 oder R09. Jede Annahme bleibt „unbelegt am R03“, bis ein Mitschnitt sie bestätigt.
- Big-Data-Format SpO₂: Die Quellen widersprechen sich (Abschnitt 2.2).
- Hintergrund-Lieferung von HealthKit wird von iOS gedrosselt, deshalb keine Echtzeitversprechen.
- Der Claude-Schlüssel liegt auf dem Gerät. Für die private Nutzung ist das vertretbar, für eine Verteilung braucht es einen Server.
- Schwellen für SpO₂-Beobachtungen sind keine klinischen Grenzwerte. Die App formuliert sie als Abweichung vom eigenen Normalband.
