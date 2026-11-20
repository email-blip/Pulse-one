# Expertenrat – Architekturreview (Master Directive 5.0, Teil I)

Stand: 2026-11-20, Code-Stand `main` @ `be98cd7` (nach PR #8), 47 Swift-Dateien, ~5 800 Zeilen, 76 Swift-Testing-Tests, 3 UI-Testdateien.
Verfasser: Claude Code (Thread „Expertenrat und Open-Source-Audit“).

## Ehrlichkeitshinweis (Directive 5.0 §1)

Es gab **keine externen Experten und keine getrennten Personen**. Die zehn Fachrollen sind **getrennte, dokumentierte Review-Perspektiven**, die ein Agent (Claude Code) nacheinander gegen denselben, tatsächlich gelesenen Code eingenommen hat. Jede Aussage über den Code nennt die geprüfte Datei. Wo eine Rolle Fachwissen einbringt (z. B. Sportwissenschaft), ist das Lehrbuchwissen mit Quellenangabe, keine klinische Validierung. Der Abgleich und die Entscheidungen in §12 sind **Vorschläge an Codex** (Entwicklungsleitung) und den Implementierungs-Thread, der Architektur, Roadmap und Backlog verantwortet.

Grundlage zusätzlich: `SANIERUNG-4.0.md` (Fehlerbild Build 4), `OPEN-SOURCE-REVIEW.md` (Directive 4.2, 10 Repos), `OPEN-SOURCE-TECHNICAL-AUDIT.md` (Directive 5.0, 8 weitere Repos + Recherche).

## Gemeinsames Lagebild (alle Rollen teilen es)

| Bereich | Stand im Code | Stufe (§14) |
|---|---|---|
| R03 finden, verbinden, Akku, Firmware | `Bluetooth/ColmiCentral.swift`, `PulseCore/ColmiProtocol.swift` | **iPhone** |
| Live-Puls | Kommando korrekt (3 Quellen), Rückmeldung fehlte; Messzustände + BLE-Diagnose in PR #9 | fehlgeschlagen → Fix in Arbeit |
| Ringuhr | setzt **UTC**, Fremdquellen nutzen Ortszeit | Fehler, Fix geplant (Review 4.2 PR 2) |
| Datenmodell | `HealthSample` (14 Arten), `StoredSample` (SwiftData, eindeutiger `dedupKey`), Qualitätsstufen, Herkunft, Profilzuordnung über Zeiträume, `SourcePolicy`, `DailySeries` | Simulator / CI |
| Apple Health | `Connect/HealthKitAdapter.swift`: 9 Mengen-Typen + Schlaf, Anker je Typ, Löschungen, 30 Tage Erstimport | Gebaut, auf iPhone unbestätigt |
| Analyse, TODAY, Intelligence, Coach, Einstellungen, Ernährung, Training | – | nicht vorhanden |
| Heart Chamber | `Features/HeartChamber/*` (RealityKit, prozedural) | Prototyp |

---

## A. Chief iOS Architect

**1. Was fehlt**
- **Versioniertes SwiftData-Schema.** `App/PulseOneApp.swift` erzeugt `Schema([StoredMeasurement.self, StoredSample.self])` ohne `VersionedSchema`/`SchemaMigrationPlan`. Bisher reichte leichte Migration; für mehrjährige Daten (5.0 Teil III) braucht jede Modelländerung eine benannte Version und einen getesteten Migrationsschritt.
- **Stiller Rückfall auf In-Memory-Store.** Schlägt das Öffnen des Stores fehl, startet die App mit leerem Speicher im RAM (`makeContainer`). Der Nutzer sieht „keine Daten“, neue Messungen gehen beim Beenden verloren, ohne Hinweis. Mindestens: sichtbarer Fehlerzustand + Diagnose, kein stilles Weiterschreiben.
- **Tab-Struktur / Navigation** für TODAY, ANALYTICS, INTELLIGENCE, MOVE, BODY, DEVICES fehlt; heute ist `ConnectScreen` Startbildschirm.
- **Hintergrundverarbeitung:** keine `UIBackgroundModes` in `project.yml` (weder `bluetooth-central` noch Hintergrund-Lieferung HealthKit), kein `BGTaskScheduler`. Ring-Verlauf wird nur im Vordergrund geholt.
- **Aggregations-Cache:** `DailySeries` rechnet aus Rohwerten; für Jahresansichten fehlen materialisierte Tageswerte (`DailyMetricSummary`, Review 4.2 PR 4).

**2. Brauchbar:** Trennung Kernlogik (`Packages/PulseCore`, pure Swift, testbar ohne Simulator) vs. App; `DeviceAdapter`/`AdapterCatalog`/`DeviceRegistry` mit Integrationsstufen; idempotenter Sync über `dedupKey`; Anker werden erst nach erfolgreichem `ingest` gespeichert (`SourcesStore.sync`).

**3. Vorbilder:** PulsHealth (`AggregateSync`, Beobachter-Bündelung), myhealth (`DailySummary`), SpeziHealthKit (Batch-Export) – alle als Konzept.

**4. Architektur:** Module als Ordner in `PulseCore` (Entscheidung Review 4.2 §5), Abhängigkeit nur abwärts: Experience → Intelligence → Evidence → Analytics → Foundation → Integration. SwiftData-Modelle bleiben in der App, `PulseCore` kennt nur Werttypen. Aggregate werden **neu berechnet, nie migriert** (aus Rohdaten reproduzierbar).

**5. Risiken:** Store-Korruption ohne Sicherung; SwiftData-Leistung bei > 1 Mio. Zeilen (Pulswerte alle 5 min ≈ 105 000/Jahr nur Ring, HealthKit-Puls deutlich mehr) → Indizes (`#Index` ab iOS 18) auf `kindRaw`, `start`, `profileID`.

**6. Zuerst:** VersionedSchema v1 einfrieren (vor der nächsten Modelländerung); sichtbarer Store-Fehlerzustand; `#Index`.

## B. Wearable & Sensor Engineer

**1. Was fehlt:** Ortszeit beim Setzen der Ringuhr; Erkennen von `0x73`-Statusmeldungen; zweiter Datendienst (`DE5BF728…`) für SpO₂-, Schlaf- und Temperaturverlauf; Anbindung des Puls-Logs `0x15` (Parser existiert: `HeartRateLogParser.swift`); Schritte `0x43`; R09-Adapter; generischer BLE-Herzfrequenz-Adapter (GATT `0x180D`/`0x2A37`, Standard, keine Lizenzfrage) für Brustgurte wie Polar H10.

**2. Brauchbar:** `ColmiProtocol` als reine Funktionen mit Prüfsumme und `.unknown(hex:)` statt Absturz; `ColmiModel`, Firmware-Lesen über `180A/2A26`; `TestedFirmware`-Idee; BLE-Diagnose (PR #9).

**3. Vorbilder:** Colmi (Swift, Apache-2.0), DayBreak (Kotlin, MIT, Parser-Tests), smart-ring (R09, MIT). Nicht: orviwan-Spezifikation (fehlerhaft), Gadgetbridge (AGPL).

**4. Architektur:** Ein Adapter je Geräteprotokoll, nicht je Modell. R09 erbt vom R03-Adapter erst, wenn ein Mitschnitt Gleichheit zeigt; bis dahin eigener Katalogeintrag mit Status `protocolUnknown`. Jede neue Datenart erst nach Mitschnitt am echten Ring auf `implementedUntested` → `confirmed`.

**5. Risiken:** Alle Fremdquellen beziehen sich auf R02/R09, nicht auf RY03_3.00.21. Widerspruch beim SpO₂-Big-Data-Format (DayBreak vs. smart-ring). Der Ring erlaubt nur eine Verbindung (QRing-App muss getrennt sein).

**6. Zuerst:** Mitschnitt aus PR #9 auswerten → Ortszeit + `0x73` → Puls-Log `0x15` → generischer GATT-Puls (schnell, standardisiert, gut testbar).

## C. Health Data Scientist

**1. Was fehlt:** Basislinien (Median + 1,4826·MAD, ohne die letzten 21 Tage), Trend (Steigung, Mindestanzahl), Abweichung nur bei anhaltenden Werten, Datenabdeckung je Tag, Messlückenerkennung, Unsicherheit je Kennzahl, Messkontext (Ruhe/Schlaf/Training), frei wählbare Zeiträume.

**2. Brauchbar:** `HealthSample` mit Einheit, Qualität, Methode, Zeitzone, Herkunft; Plausibilitätsbereiche je Art (`HealthSample.swift`); `SourcePolicy` wählt **eine** Quelle statt zu mitteln (richtig – Mittelwerte verschiedener Sensoren verfälschen); `DailySeries` mit Aggregationsart je Messwert (Punkt, Summe, Intervall).

**3. Vorbilder:** Tideline (Basislinie, Trend, Belegobjekt), healthquery (Abdeckung), stansz `data_quality.py` (Messtaktung als Vollständigkeitsmaß).

**4. Architektur:** `HealthAnalytics` erhält nur Tageswerte + Abdeckung, nie Rohdaten. Jede Kennzahl ist ein Werttyp mit `value`, `unit`, `n`, `window`, `coverage`, `method`, `sources`. Zustand „Basislinie entsteht“ statt Zahl, wenn n zu klein.

**5. Risiken:**
- **HRV-Methoden:** Apple liefert SDNN (`hrv_sdnn`), Ringe und Literatur oft RMSSD. **Nie vermischen**, nie in eine Basislinie. Eigene `SampleKind` für RMSSD, falls der Ring es liefert.
- SpO₂ aus Fingerring/Uhr hat bekannte Messfehler (Bewegung, Durchblutung, Hautton); Nachtwerte nur mit Abdeckung anzeigen.
- Zeitzonen: Tagesgrenzen in Ortszeit des Messzeitpunkts (`timeZoneIdentifier` ist vorhanden).

**6. Zuerst:** Basislinie/Trend/Abdeckung als getestete reine Funktionen (Review 4.2 PR 4/5), SpO₂ als Referenz.

## D. Clinical Informatics Specialist

**1. Was fehlt:** Belegkatalog mit Quellen und Grenzen; fester Textbaukasten für nicht-diagnostische Formulierungen; Hinweis „ärztlich abklären“ bei deutlich auffälligen Werten (Projektregel); optional: vom Nutzer selbst eingetragene bekannte Diagnosen (ICD-10-GM / ICD-11, nur Anzeige).

**2. Brauchbar:** Qualitätsstufen und Ablehnungsgründe in `HealthSample`; Plausibilitätsgrenzen; ehrliche Statusbegriffe (`SupportStatus`).

**3. Vorbilder:** HealthTrack `lib/evidence` (Quelle + Zielgruppe + Grenzen), OpenNutriTracker (jede Formel mit Literatur).

**4. Architektur:** `HealthEvidence` ist die einzige Stelle, an der Schwellen und Referenzbereiche stehen, jeweils mit Quelle. Diagnosen sind **Nutzereingaben** mit Code + Version der Klassifikation, keine abgeleiteten Daten.

**5. Risiken (regulatorisch):**
- **Medizinprodukt (EU MDR):** Sobald die App aus Messwerten auf Krankheiten schließt, Diagnosen vorschlägt oder Therapie empfiehlt, kann sie ein Medizinprodukt sein. Deshalb: Trends beschreiben, relativ zum eigenen Normalband, keine Krankheitsnamen aus Messwerten, keine Ampeln mit klinischer Bedeutung. Für eine rein private App ohne Inverkehrbringen ist das Risiko gering, die Regel bleibt trotzdem (Projektgrundsatz).
- ICD-11 steht unter CC BY-ND (keine Bearbeitung), Mappings brauchen WHO-Vertrag (Audit §3.2).
- SpO₂-Schwellen sind keine klinischen Grenzwerte; Ringe sind keine Pulsoximeter nach Norm.

**6. Zuerst:** Belegkatalog v1 für SpO₂ und Puls zusammen mit PR 5; Formulierungsregeln als Test (verbotene Wörter wie „Diagnose“, „Hypoxie“, „Arrhythmie“ in generierten Texten).

## E. Sports Scientist & Strength Coach

**1. Was fehlt:** alles zu MOVE: Trainingserfassung (HealthKit-Workouts werden nicht gelesen; `trainingDuration` existiert als Art, aber kein Import), Belastungszonen, Trainingslast, Regeneration, Progression.

**2. Brauchbar:** Messkontext-Idee in `SourcePolicy` (Training will Brustgurt, Ruhe den Ring) – genau richtig für Pulszonen.

**3. Vorbilder:** open-coach (Wochenanpassung, +10 %/Woche), ygeia (Last relativ zu 28 Tagen), wger (Progressionsregeln; AGPL, nur Idee).

**4. Architektur:** Zonen aus persönlicher Herzfrequenzreserve (Karvonen), Maximalpuls nur gemessen oder als markierte Schätzung. Trainingslast als Summe Zeit × Zone (TRIMP-artig, Quelle Banister) – als **beschriebene Kennzahl**, nicht als Score. Wochenanpassung deterministisch, Claude formuliert nur.

**5. Risiken:** Formeln wie „220 − Alter“ sind ungenau → nur mit Kennzeichnung „Schätzung“. Live-Puls vom Ring ist für Intervalltraining zu träge; für Zonen braucht es GATT-Brustgurt.

**6. Zuerst:** nach PR 7: HealthKit-Workouts lesen, GATT-Brustgurt, Zonen. Coach erst danach.

## F. Nutrition Scientist

**1. Was fehlt:** Ernährung komplett (Lebensmittel, Mahlzeiten, Energiebedarf, Makros, Wasser).

**2. Brauchbar:** Datenmodell lässt sich um Nährwert-Arten erweitern (`SampleKind`, Einheit, Quelle); HealthKit kann Ernährungstypen lesen/schreiben.

**3. Vorbilder:** OpenNutriTracker (GPL, nur Konzepte: Quellen je Formel, KI liefert nur Namen), HealthTrack (Mifflin-St Jeor mit Sicherheitsgrenzen, Cache), healthos (Formeltests). Datenquellen: Open Food Facts (ODbL), USDA FDC (CC0), **BLS 4.0** (kostenfrei, deutsch, offline; Lizenztext vor Einbau prüfen).

**4. Architektur:** Lebensmittel als eigene Entität mit Herkunft (`OFF:<barcode>`, `FDC:<id>`, `BLS:<code>`) und Nährwerten je 100 g; Mahlzeit = Liste (Lebensmittel, Menge, Unsicherheit). Energiebedarf deterministisch, Defizit-Obergrenze, Sonderfälle (Schwangerschaft, Minderjährige) nur Erhalt.

**5. Risiken:** Essgewohnheiten gehen bei Online-Abfragen an Dritte; Portionsschätzung per Foto ist ungenau; Essstörungen (Hinweis und „nicht für mich“-Option, kein Streak-Druck).

**6. Zuerst:** nicht vor PR 7. Dann Barcode + Suche + manuelle Einträge, danach BLS offline.

## G. AI Systems Architect

**1. Was fehlt:** alles zu Claude: Keychain, Verbindungstest, Modellwahl, Kostenanzeige, `HealthAnalysisContext` v1, JSON-Schema, Zahlenprüfer, Verlauf, Rückfragen (Spezifikation in `SANIERUNG-4.0.md` §7 und `OPEN-SOURCE-REVIEW.md` §6).

**2. Brauchbar:** Datenmodell mit Herkunft und Qualität ist die Voraussetzung für belegte Aussagen.

**3. Vorbilder:** open-coach (Keychain `WhenUnlockedThisDeviceOnly`, Regel-Rückfall), OpenNutriTracker (Schema ohne Zahlenfelder), zerocoach (schreibende Werkzeuge nur nach Bestätigung), Tideline/healthquery (Belegobjekte).

**4. Architektur:**
- Kontext enthält nur berechnete Kennzahlen mit fester `beleg_id`, keine Rohdaten, keine Namen, keine Geräte-IDs.
- Antwort-Schema: jede Zahl als `{wert, einheit, beleg_id}`; Freitext mit Zahl ohne Beleg → „nicht belegt“, nicht als Befund angezeigt.
- Rückfragen laufen über dasselbe Schema; Werkzeugaufrufe (später) nur lesend, schreibend erst nach Tipp in der App.
- „KI-Gedächtnis“: lokal, vom Nutzer einsehbar und löschbar, nie stillschweigend an Claude gesendet.
- Ohne Schlüssel: identische lokale Analyse mit festen Texten (4.2 §5).

**5. Risiken:** Kosten (vor Nutzung freigeben, Zahlen in SANIERUNG §7); Schlüssel auf dem Gerät (privat vertretbar); Halluzinierte Zahlen (Prüfer); Prompt-Injection über Freitexte des Nutzers (Kontext strikt strukturiert).

**6. Zuerst:** PR 6 nach SpO₂ (PR 5), mit Zahlenprüfer als Pflichttest.

## H. Product Designer & 3D Experience Director

**1. Was fehlt:** Informationsarchitektur mit 6 Bereichen; TODAY als Startpunkt; Diagramme (Swift Charts) mit Zeiträumen; Leer- und Fehlerzustände („zu wenig Daten“, „Basislinie entsteht“); Heart Chamber als Prototyp gekennzeichnet; Zustand „kein Puls“.

**2. Brauchbar:** Designsystem (`DesignSystem/Palette.swift`, `Typography.swift`), Orb (`PulseOrb`), Heart Chamber mit RealityKit, Haptik und Ton (`Services/HeartFeedback.swift`), Testszenarien mit Banner „Testansicht“, Screenshot-Matrix in CI.

**3. Vorbilder:** ygeia (Erklär-Blatt je Zahl), myhealth (Vorschau „diese Daten gehen an Claude“).

**4. Architektur:** Jede Kennzahl-Karte zeigt Wert, Einheit, Zeit, Quelle, Mini-Verlauf, Einordnung zum eigenen Band und „Wie berechnet?“. 3D erst an echten Daten (Puls), nicht als Dekoration.

**5. Risiken:** Schöne Oberfläche ohne Daten wirkt wie Scheinfunktion (genau das Problem aus Build 4). Ampelfarben vermeiden (Klinik-Anmutung).

**6. Zuerst:** Tab-Gerüst + TODAY mit echten Leerzuständen (Review 4.0 PR 4), danach Detail mit Diagrammen.

## I. Security & Privacy Architect

**1. Was fehlt:**
- Keychain-Speicher für Claude- und USDA-Schlüssel.
- **Dateischutz des SwiftData-Stores** wird nicht explizit gesetzt (Standard `completeUntilFirstUserAuthentication`); die Geräte-Registry hat `.completeFileProtection` (`SourcesStore.save`). Gesundheitsdaten sollten mindestens gleich geschützt sein. Abwägung: `.complete` verhindert Hintergrund-Sync bei gesperrtem Gerät → bewusst entscheiden.
- Export/Backup/Löschen-Funktionen (5.0 Teil III) und Einwilligungsprotokoll („wann wurde was an Claude gesendet“).
- App-Sperre (Face ID) – in MyBody beschlossen, in PULSE ONE noch nicht.

**2. Brauchbar:** Daten lokal; BLE-Diagnose-Export ohne Geräte-ID (PR #9); `PrivacyInfo.xcprivacy` vorhanden (UserDefaults deklariert); keine Secrets im Repo.

**3. Vorbilder:** open-coach / healthos (ein Ort für den Schlüssel), myhealth (Sendevorschau).

**4. Architektur:** Schlüssel nur Keychain, nie Logs/Screenshots/Diagnose; jede externe Übertragung (Claude, OFF, USDA, Oura) in einem Datenfluss-Register in den Einstellungen sichtbar und einzeln abschaltbar.

**5. Risiken:** Repo ist öffentlich → keine echten Messdaten, keine Mitschnitte mit Geräte-ID, keine Screenshots mit echten Werten ins Repo. iCloud-Backup des Stores ist laut Johannes erlaubt (MyBody-Entscheidung 2026-11-19); für PULSE ONE bestätigen lassen.

**6. Zuerst:** Keychain mit PR 6; Store-Dateischutz-Entscheidung + Export/Löschen vor dem ersten Langzeitbetrieb.

## J. Quality Assurance Lead

**1. Was fehlt:** Hardware-Testprotokoll je Szenario (Ring, Health, Claude) mit Belegablage in `EVIDENCE.md`; Regressionstests für Parser mit **echten** Mitschnitten (Hex aus PR #9 als Testfixture, ohne Geräte-ID); Leistungstests für große Datenmengen (Jahresdaten synthetisch, nur in Tests); Migrationstests je Schemaversion.

**2. Brauchbar:** 76 Swift-Testing-Tests im Kern, UI-Tests mit Barrierefreiheits-Audit und Screenshot-Matrix, ehrliche Statusstufen (§14), Testszenarien nur mit `-uiTesting YES`.

**3. Vorbilder:** DayBreak (Parser-Tests mit Bytefolgen), healthos (Formeltests), OpenNutriTracker (Testkultur, nur als Maßstab).

**4. Architektur:** Definition of Done aus 4.2 §6 gilt: Code + Tests + geprüfte Berechnung + UI + echter Datenfluss + iPhone (wo Hardware nötig). CI läuft nur bei Änderungen unter `apps/**` (spart Minuten); Doku-PRs haben keinen Build.

**5. Risiken:** Grüne CI täuscht Hardware-Funktion vor (Build 4). Simulator hat kein Bluetooth und keine echten HealthKit-Daten.

**6. Zuerst:** Mitschnitt-Fixtures aus dem nächsten iPhone-Test; Testprotokoll-Vorlage für Johannes (sehr einfach, Schritt für Schritt).

---

## 11. Widersprüche zwischen den Rollen

| # | Widerspruch | Rollen | Vorschlag zur Entscheidung |
|---|---|---|---|
| W1 | Store-Dateischutz `.complete` (Sicherheit) vs. Hintergrund-Sync bei gesperrtem Gerät (Architektur, Sensor) | I ↔ A, B | `completeUntilFirstUserAuthentication` beibehalten (Hintergrund-Sync möglich), dafür App-Sperre per Face ID und Keychain für Schlüssel. Bewusst in `DECISIONS.md` festhalten. |
| W2 | Readiness-/Recovery-Score gewünscht (Produkt, Sport) vs. unbelegte Scores verboten (Datenwissenschaft, Klinik, 4.2 §2) | H, E ↔ C, D | **Kein Score.** Stattdessen drei beschriebene Einzelkennzahlen (Ruhepuls, HRV, Schlaf) relativ zum eigenen Band mit Beleg. |
| W3 | Frühe Ernährung/Coach (5.0 Mission) vs. erst Datenbasis und SpO₂-Referenz (4.2 §8) | F, E ↔ A, C, J | Reihenfolge aus 4.2 bleibt; Ernährung und MOVE starten nach PR 7. Grund: ohne funktionierende Messkette wären es Scheinfeatures (5.0 „keine Scheinfeatures“). |
| W4 | Fotoerkennung von Mahlzeiten (Produkt) vs. Kosten/Datenschutz (KI, Sicherheit) | H, F ↔ G, I | Zuerst Barcode/Suche offline-freundlich; Foto nur über Claude-Vision nach Kostenfreigabe, Ergebnis nur Name + Menge, Bestätigung durch Nutzer. |
| W5 | Fremde SDKs (Open Food Facts Swift, SpeziHealthKit) sparen Zeit vs. „Abhängigkeiten vermeiden“ | A ↔ F | Eigene schlanke Clients; SDK nur mit `DECISIONS.md`-Eintrag, wenn der eigene Client nachweislich nicht reicht. |
| W6 | Ring-Datenarten früh anzeigen (Produkt) vs. erst nach Mitschnitt (Sensor, QA) | H ↔ B, J | Nur belegte Datenarten anzeigen; übrige im Gerätescreen als „Protokoll unbekannt“. |
| W7 | Wertende Kategorien (Körperfett „obese“, Ampeln) vs. nicht-diagnostische Sprache | E, F ↔ D | Keine wertenden Kategorien; Lage relativ zum eigenen Verlauf beschreiben, Referenzbereiche nur mit Quelle im Belegblatt. |

## 12. Gemeinsame Priorität (Vorschlag)

Unverändert die Reihenfolge des Implementierungs-Threads (`OPEN-SOURCE-REVIEW.md` §7), ergänzt um Querschnittsaufgaben, die mehrere Rollen als Voraussetzung sehen:

| Schritt | Inhalt | Rollen |
|---|---|---|
| 0 (quer, sofort) | VersionedSchema v1 einfrieren; sichtbarer Store-Fehler statt stillem In-Memory-Rückfall; `#Index` auf Art/Zeit/Profil | A, J |
| 1 | Messzustände + BLE-Diagnose (PR #9), Mitschnitt auswerten | B, J |
| 2 | Ortszeit, `0x73`, Testflight-Build | B |
| 3 | HealthKit: Status je Typ, Beobachter, neue Typen inkl. **Workouts**, Gewicht, Größe, Atemfrequenz, VO₂max | A, B, E |
| 4 | Langzeit: Tageswerte materialisiert, Abdeckung, Lücken | A, C |
| 5 | SpO₂ vertikal + Belegkatalog v1 + „Wie berechnet?“ | C, D, H |
| 6 | Claude: Keychain, Kontext v1, Schema mit `beleg_id`, Zahlenprüfer, Datenfluss-Register | G, I |
| 7 | Übertragung auf Puls, Ruhepuls, HRV (SDNN/RMSSD getrennt), Schlaf, Aktivität; TODAY/ANALYTICS | C, H |
| 8 | MOVE: Workouts, GATT-Brustgurt, Zonen, Last relativ zu 28 Tagen | B, E |
| 9 | Ernährung: Barcode (OFF), Suche (USDA), BLS offline | F, I |
| 10 | Coach: Regeln zuerst, Claude formuliert, schreibende Aktionen nur nach Bestätigung | E, F, G |
| 11 | Export/Backup/Löschen, Face-ID-Sperre | I |

## 13. Entscheidungen von Johannes

1. **Claude-Kosten:** freigegeben (2026-11-20; eigenes Anthropic-Konto vorhanden).
2. **Lebensmittel-Abfragen an Dritte** (Open Food Facts, USDA): erlaubt (2026-11-20). In der App offenlegen, generischer User-Agent ohne persönliche Daten.
3. **iCloud-Backup** der Datenbank: erlaubt (Johannes, 2026-11-19, projektweit). Damit gilt W1: Dateischutz `completeUntilFirstUserAuthentication`, Backup nicht ausschließen.
4. **Diagnosen selbst eintragen** (ICD, nur Anzeige): gewünscht (2026-11-20). Keine Auswertung oder Kodierung aus Messwerten.
