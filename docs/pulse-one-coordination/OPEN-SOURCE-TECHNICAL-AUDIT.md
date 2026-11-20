# Open-Source Technical Audit (Master Directive 5.0, Teil II)

Stand: 2026-11-20. Verfasser: Claude Code (Thread „Expertenrat und Open-Source-Audit“).
Ergänzt `OPEN-SOURCE-REVIEW.md` (Directive 4.2, Implementierungs-Thread). Die dort geprüften 10 Repositories (Colmi, DayBreak, mcp-for-colmi-smartring, smart-ring, HealthBridge, pulshealth, myhealth, openFitness, Tideline, healthquery) werden **hier nicht erneut bewertet**; deren Entscheidungen gelten.

**Methode.** Jedes Repository wurde flach geklont (Stand `HEAD` am 2026-11-20) und der Quellcode gelesen, nicht nur die README. Nichts wurde ausgeführt, installiert oder gebaut. Lizenz aus der Lizenzdatei im Repo, nicht aus Badges. Testzahl = Dateien mit Tests (grobe Zählung, keine Abdeckungsmessung, weil nichts ausgeführt wurde). „Letzte Wartung“ = Datum des letzten Commits.

**Grundregeln (verbindlich):**
- Es wird **kein fremder Code kopiert**. Konzepte werden in Swift neu implementiert, mit eigenen Tests. Formeln aus Fachliteratur (z. B. Mifflin-St Jeor) sind nicht urheberrechtlich geschützt; zitiert wird die Primärquelle, nicht das Repo.
- **GPL/AGPL-Code kommt nicht in PULSE ONE**, auch nicht in Teilen (wger, OpenNutriTracker, open-health-sync, Gadgetbridge).
- Repos ohne Lizenzdatei gelten als „alle Rechte vorbehalten“: nur lesen, nichts übernehmen.
- Fremde Scores (Readiness, Strain, Recovery, Food-Quality) werden **nicht** als Kennzahl übernommen (Directive 4.2 §2).

## 1. Übersicht und Entscheidung

| Projekt | Existenz / Code | Letzte Wartung | Lizenz | Stack | Tests | Entscheidung |
|---|---|---|---|---|---|---|
| mawji/HealthTrack | ja, ~200 TS-Dateien | 2026-07-01 | MIT | Next.js-Server, SQLite, Node | 2 Testendpunkte, keine Unit-Tests | **Adaptieren** (Belegkatalog, Ernährungsziele, USDA/OFF-Cache) |
| Kaden-G/open-coach | ja, 46 Swift-Dateien | 2026-04-12 | MIT | SwiftUI, SwiftData, XcodeGen | 4 Dateien (Coach, Anpassung, Tracking, Ersatzübungen) | **Adaptieren** (Wochenanpassung, Regel-Fallback, Keychain-Muster) |
| ntsd/zerocoach | ja, ~100 TS-Dateien | 2026-11-06 | Apache-2.0 (Code); Übungsdaten **RepDB, eigene Lizenz** | React Native/Expo, lokales LLM | 16 Dateien | **Nur Referenz** (Schutz vor unbeabsichtigten KI-Schreibaktionen) |
| wger-project/wger | ja, groß, aktiv | 2026-11-17 | **AGPL-3.0** | Django | ~220 Dateien | **Verwerfen als Code**; öffentliche Übungsdaten über API nur mit Lizenzprüfung je Datensatz |
| jkguidaven/healthos | ja, ~150 TS-Dateien | 2026-04-13 | MIT | React Native/Expo, Drizzle | 17 Dateien, Formeln gut getestet | **Adaptieren** (Körperformeln mit Plausibilitätsgrenzen, Testfälle als Vorlage) |
| simonoppowa/OpenNutriTracker | ja, ~900 Dart-Dateien, sehr aktiv | 2026-11-09 | **GPL-3.0** | Flutter, Supabase-Backend | ~325 Testdateien | **Neu implementieren** (nur Konzepte; Code tabu) |
| enricsneelamkavil/Moment | ja, 57 Swift-Dateien | 2026-08-30 | **keine** („all rights reserved“ laut README) | SwiftUI, SwiftData | 0 | **Verwerfen** (nur gelesen) |
| falakiwastaken/ygeia | ja, ~57 JS-Dateien (~21 000 Zeilen) | 2026-08-29 | MIT | Vanilla-JS-PWA, IndexedDB | 1 Browser-Testseite | **Adaptieren** (Erklär-Blatt je Kennzahl, Last relativ zur eigenen Basis) |

Kommerzielle Nutzbarkeit: MIT und Apache-2.0 erlauben Wiederverwendung mit Lizenzhinweis. Da wir nur Konzepte übernehmen, entsteht keine Hinweispflicht; wir nennen die Projekte trotzdem in `DECISIONS.md` als Vorbild.

## 2. Bewertung je Repository

### 2.1 mawji/HealthTrack (MIT) – adaptieren
**Was es ist:** lokaler Next.js-Server mit Google-Health-API, Ernährungslog, Coach (OpenRouter/Ollama/OpenAI), Telegram-Frontend. Läuft auf einem Rechner, nicht auf dem iPhone.

**Relevante Dateien:**
- `lib/evidence/types.ts`, `rules.ts`, `sources.ts`: Belegkatalog. `SourceCard` (Herausgeber, URL, Rechtsraum, Lizenz, Zitierhinweis, Ausgabe) und `EvidenceRule` (Aussage, Quelle(n), Zielgruppe, Grenzen, Evidenzgrad). Regeln sind Code, keine Datenbank. Kommentar: Felder wie „zuletzt geprüft“ bewusst weggelassen, solange niemand wirklich prüft.
- `lib/coach/nutrition-targets.ts`: Energiebedarf nach Mifflin-St Jeor × Aktivitätsfaktor, Defizit max. 25 %, Untergrenze kcal, bei Schwangerschaft/Stillzeit/Minderjährigen nur Erhalt + Hinweis auf ärztliche Begleitung. Eiweiß-Spannen je Ziel.
- `lib/usda.ts`, `lib/openfoodfacts.ts`: Nährwerte je 100 g, Portion bleibt editierbare Schätzung, lokaler Cache (14 bzw. 30 Tage), „nicht gefunden“ wird mit-gecacht.
- `lib/coach/source-pills.ts`: erkennt Quellennamen im KI-Text und zeigt sie als antippbare Belege.
- `lib/readiness.ts`: ln(rMSSD), Band ± 0,75 SD um eigene Basis, gewichtete Teilscores.

**Qualität:** sauber kommentiert, Gründe dokumentiert. Kaum automatische Tests. **Risiken:** `lib/ai-provider.ts` nutzt einen inoffiziellen ChatGPT-Backend-Endpunkt (`chatgpt.com/backend-api/codex/...`) per Device-Flow – instabil und nicht durch API-Bedingungen gedeckt. Telegram-Weitergabe von Gesundheitsdaten. Demo-Key `DEMO_KEY` für USDA.

**Übernehmen (als Konzept):** Belegkatalog-Struktur → `HealthEvidence`; deterministische Ernährungsziele mit Sicherheitsgrenzen; Cache-Strategie für Lebensmittel-APIs; Quellen-Pills als UI-Idee (bei uns aber über `beleg_id` im JSON, nicht per Regex).
**Nicht übernehmen:** Readiness-Score (unbelegte Gewichte, Directive 4.2 §2), inoffizielle KI-Endpunkte, Telegram, Google-Health-Anbindung (kein Bedarf auf iOS).

### 2.2 Kaden-G/open-coach (MIT) – adaptieren
**Was es ist:** native iOS-Fitness-Coach-App (SwiftUI, SwiftData, XcodeGen, iOS 17). Am nächsten an unserem Stack.

**Relevante Dateien:**
- `Services/CoachEngine/WeeklyAdaptation.swift`: Wochenanpassung aus Abschlussquote, mittlerer RPE und Wiederholungs-Erfüllung. Volumen +10 % max. je Woche, Untergrenze 60 %. Klar, deterministisch, getestet (`OpenCoachTests/WeeklyAdaptationTests.swift`).
- `Services/CoachEngine/RuleBasedCoach.swift` + `LLMCoach.swift`: Plan zuerst regelbasiert, KI nur als Verbesserung, bei Fehler Rückfall auf Regeln.
- `Utilities/KeychainHelper.swift`: Schlüssel mit `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- `Services/LLM/LLMClient.swift`: direkter Anthropic-Aufruf (`x-api-key`, `anthropic-version`).
- `Services/DataExport/JSONExporter.swift` + `Resources/export-schema.json`: Export mit veröffentlichtem JSON-Schema.

**Qualität:** klein, verständlich, Swift 5.10 (nicht Swift 6 strict). **Risiken:** Swift-6-Concurrency fehlt; „RPE fehlt = 5“ ist ein Ersatzwert (bei uns verboten: fehlend bleibt fehlend). Projektdatei heißt `Freeletics.xcodeproj` (Markenname, für uns irrelevant).

**Übernehmen (als Konzept):** Wochenanpassung als reine Funktion mit Obergrenze; „Regeln zuerst, KI optional“ (passt zu 4.2 §5: lokale Analyse ohne Schlüssel); Export-Schema veröffentlichen. **Neu schreiben** in Swift 6, ohne Ersatzwerte.

### 2.3 ntsd/zerocoach (Apache-2.0) – nur Referenz
**Was es ist:** React-Native-Coach mit lokalem LLM (Gemma GGUF), Agent mit Werkzeugen, die App-Daten lesen und schreiben.

**Relevante Dateien:** `src/services/agent/guardRails.ts` (trennt lesende und schreibende Werkzeuge; Beratungsfragen dürfen keine Schreibaktion auslösen), `agentHarness.ts`, `src/services/device/deviceMemory.ts` (Gedächtnis mit ADD/UPDATE/DELETE/NOOP).

**Risiken:** `src/services/telemetry/readinessCalculator.ts` rechnet mit festen Bevölkerungswerten (HRV „70 ms“, Ruhepuls „48“) – fachlich nicht haltbar. Übungsdaten (`src/data/exercises.json`) stammen aus **RepDB** mit eigener Datenlizenz („other“, kommerzielle Nutzung nur gegen Bezahlung) → **nicht verwenden**. Enthält trainierte LoRA-Adapter und Upload-Skripte zu Hugging Face.

**Übernehmen (als Konzept):** Wenn Claude später Werkzeuge bekommt: Schreibende Werkzeuge nur nach ausdrücklicher Bestätigung in der App, nie aus einer Beratungsfrage heraus. Mehr nicht.

### 2.4 wger-project/wger (AGPL-3.0) – Code verwerfen, nur Referenz
**Was es ist:** etablierte Trainings-/Ernährungs-Webplattform (Django), sehr aktiv (Commit 2026-11-17), große Testbasis.

**Relevante Dateien (nur gelesen):** `wger/manager/one_rep_max.py` (Brzycki-1RM, gültig 1 ≤ Wdh < 37), `wger/manager/config_calculations/` (Progressionsregeln je Satz: Gewicht, Wdh, RIR, Pause mit Min/Max), `wger/nutrition/extract_info/off.py`, `usda.py` (Import aus Open Food Facts und USDA).

**Lizenz:** AGPL-3.0 → kein Code in PULSE ONE. Die Formel von Brzycki (1993) ist Fachwissen und darf mit Primärquelle neu implementiert werden. **Übungsdatenbank über die öffentliche API (wger.de):** Jede Übung trägt ein eigenes Lizenzfeld und Autor; nur Einträge mit freier Lizenz (z. B. CC-BY-SA) und mit Namensnennung verwenden; Share-Alike gilt dann für die Daten, nicht für unseren Code. Entscheidung, ob wir das wollen, fällt mit MOVE (später).

### 2.5 jkguidaven/healthos (MIT) – adaptieren
**Was es ist:** React-Native-App für Körper-Rekomposition (Ernährung, Training, Körpermaße, Gemini-Coach).

**Relevante Dateien:** `src/lib/formulas/` mit Tests in `__tests__/`: `body-fat.ts` (US-Navy-Methode, Hodgdon & Beckett 1984, gibt `null` bei unplausiblen Eingaben), `tdee.ts`, `bmi.ts`, `macros.ts`, `personal-record.ts`, `recomp-signal.ts` (Woche-zu-Woche-Deltas Gewicht/Taille/Arm → beschreibendes Signal). `src/lib/external/` mit MSW-gemockten Tests für Open Food Facts und wger. `src/lib/ai/api-key.ts`: genau eine Datei liest/schreibt den Schlüssel.

**Qualität:** reine Funktionen, getrennt von UI und KI, gute Testabdeckung der Formeln. **Risiken:** Körperfett-Kategorien („obese“) sind wertend → bei uns nicht anzeigen. Web-Fallback speichert Schlüssel im `localStorage` (für iOS irrelevant).

**Übernehmen (als Konzept):** Formeln als reine, getestete Funktionen mit Plausibilitätsprüfung → `HealthAnalytics/Body`; Testfälle aus den Primärquellen ableiten; „ein Ort für den Schlüssel“.

### 2.6 simonoppowa/OpenNutriTracker (GPL-3.0) – nur Konzepte, neu implementieren
**Was es ist:** reifste Ernährungs-App im Feld (Flutter, ~325 Testdateien, aktiv, Version 2.7.0).

**Relevante Dateien (nur gelesen):** `lib/core/utils/calc/` (TDEE, PAL, MET, DRI-Referenzwerte, gleitender Gewichtsmittelwert, Tagesgrenze), `lib/core/utils/bounds/` (Plausibilitätsgrenzen), `lib/features/add_meal/data/data_sources/` (Open Food Facts direkt, sonst eigenes Supabase-Backend mit USDA + BLS), `lib/core/presentation/sources_screen.dart` (jede Formel mit Literatur verlinkt).

**Wichtigstes Konzept:** Die KI (Sprach-/Texteingabe) liefert **nur Lebensmittelname und Menge**. Das Antwort-Schema hat **kein Feld für Nährwerte**, alle Zahlen kommen aus der Datenbank. Genau dieses Prinzip übernehmen wir für Claude (siehe Expertenrat, Rolle G).

**Lizenz:** GPL-3.0 → **kein Code**, keine Übersetzung von Dart nach Swift. Erlaubt ist, dieselben Primärquellen (IOM 2005, WHO TRS 916, Compendium of Physical Activities 2024) selbst zu lesen und umzusetzen. Das Supabase-Backend ist ein externer Dienst → nicht verwenden.

### 2.7 enricsneelamkavil/Moment (keine Lizenz) – verwerfen
SwiftUI/SwiftData-Tracker (Training, Gewicht, Eiweiß/Kreatin, Gemini-Mahlzeitenfoto). README: „no license specified, all rights reserved“. Keine Tests. Nur gelesen: Gemini-Aufruf mit Antwort-Schema (`Services/GeminiClient.swift`), Gewicht „ein Eintrag pro Tag, erneutes Eintragen aktualisiert“. Beides ist allgemeines Wissen; **nichts übernehmen**.

### 2.8 falakiwastaken/ygeia (MIT) – adaptieren
**Was es ist:** Offline-PWA (Ernährung, Kraft, Sport, Schlaf, Körper), Daten in IndexedDB, Coach optional mit eigenem Schlüssel.

**Relevante Dateien:** `js/explain.js` (zu jeder angezeigten Zahl eine Erklärung, wie sie berechnet wurde: Kalorienziel, Makros, 1RM, BMI, Trend), `js/domain-load.js` (Trainingslast aus Tonnage und MET-Minuten, **relativ zu den eigenen letzten 28 Tagen**; der Kommentar sagt ausdrücklich, dass die 0–21-Skala nicht mit WHOOP vergleichbar ist), `js/healthimport.js` (Apple-Health-`export.xml` streamend parsen), `js/backup.js`.

**Risiken:** „Food-Quality-Score“ und „Strength Rank“ sind eigene Scores ohne Validierung → nicht übernehmen. Lokale `devserver.py`/`legacy-cpp` irrelevant.

**Übernehmen (als Konzept):** „Erklär-Blatt“ je Zahl → in PULSE ONE als Belegansicht (Rechenweg, Datenbasis, n, Zeitraum, Quelle); Belastung relativ zur eigenen Historie statt absolut; ehrliche Kennzeichnung entlehnter Skalen.

## 3. Ergänzende Recherche

Suche über die GitHub-Suche (Sterne, Lizenz, letzte Aktivität) und Herstellerdokumentation, Stand 2026-11-20.

### 3.1 Bibliotheken und Projekte

| Thema | Kandidat | Lizenz | Befund | Entscheidung |
|---|---|---|---|---|
| SwiftUI HealthKit / Bulk-Export | StanfordSpezi/SpeziHealthKit | MIT | ~105 Swift-Dateien, Abfragen, Bulk-Export in Batches, Diagramme; zieht das Spezi-Framework nach sich | **Referenz** für Batch-Export und Abfrage-Muster; keine Abhängigkeit (Abhängigkeiten vermeiden, eigener Adapter existiert) |
| Open Food Facts (Swift) | openfoodfacts/openfoodfacts-swift | Apache-2.0 | offizielles SDK, aktiv (2026-11-09), ~50 Dateien | **Optional**; erster Schritt eigener schlanker REST-Client (eine Produktabfrage), SDK nur, wenn wir Upload/Suche brauchen → dann Eintrag in `DECISIONS.md` |
| Open Food Facts (alt) | openfoodfacts/openfoodfacts-ios | Apache-2.0 | letzte Aktivität 2023 | verwerfen (veraltet) |
| Wearable-Sync | soma-intelligence/open-health-sync | **AGPL-3.0** | Go-Server | verwerfen |
| Wearable-Sync | umutkeltek/healthsave-observatory | **Elastic-2.0** (nicht Open Source im OSI-Sinn) | Python-Server | verwerfen |
| Colmi-Protokoll | Gadgetbridge (Codeberg) | **AGPL-3.0** | wird in den Colmi-Repos als Quelle zitiert | kein Code, keine Übersetzung; Protokollfakten nur, wenn sie zusätzlich durch MIT-Quellen oder eigenen Mitschnitt belegt sind |
| Food Recognition (Core ML) | diverse kleine Repos (z. B. andrebng/Food-Diary, 2017) | MIT/keine | veraltet, ohne Modelllizenzen | verwerfen; Fotoerkennung, wenn überhaupt, über Claude-Vision (siehe 3.3) |
| AI Health Coaching, Adaptive Workout, Evidence Grounding, Longitudinal Analytics | Suche ergab nur Kleinstprojekte (≤ 10 Sterne, oft ohne Lizenz) | – | keine belastbare Vorlage über die bereits geprüften hinaus | keine Aufnahme; Tideline/healthquery (4.2) bleiben die Vorlage |

### 3.2 Datenquellen und Dienste

| Dienst | Zugang | Lizenz / Bedingungen | Kosten | Entscheidung |
|---|---|---|---|---|
| **Open Food Facts** (Barcode) | `GET /api/v2/product/{barcode}.json`, ohne Schlüssel | Datenbank **ODbL** (Namensnennung + Share-Alike für abgeleitete Datenbanken), Bilder CC BY-SA; eigener `User-Agent` Pflicht; Limit 100 Abfragen/min für Produkte, Suche deutlich strenger (~10/min) | kostenlos | **Erste Quelle für Barcode.** Nur Einzelabfragen, lokaler Cache, Quelle in der App nennen. Keine eigene abgeleitete Datenbank veröffentlichen. **Der User-Agent enthält keine persönliche E-Mail** (generischer App-Name + Repo-URL). |
| **USDA FoodData Central** | REST, Schlüssel über api.data.gov | Daten gemeinfrei (CC0), Quellenangabe erbeten | kostenlos (Rate-Limit je Schlüssel) | **Zweite Quelle** für Grundnahrungsmittel. Schlüssel gehört in Keychain/Build-Secret, nicht ins Repo. |
| **Bundeslebensmittelschlüssel (BLS 4.0)** | Download beim Max Rubner-Institut, ~7 140 Lebensmittel, bis 138 Nährstoffe | seit Dez. 2025 **kostenfrei**; genauer Lizenztext **vor Einbau prüfen** (OpenNutriTracker nennt CC BY 4.0, Primärquelle nicht bestätigt) | kostenlos | **Beste Quelle für deutsche Lebensmittel**, lokal einbettbar (offline). Erst nach Lizenzprüfung, mit Eintrag in `DECISIONS.md`. |
| **WHO ICD-11 API** | Registrierung auf icd.who.int, OAuth2 (Client Credentials) | ICD-11 unter **CC BY-ND 3.0 IGO**: Nutzung auch kommerziell erlaubt, **keine Bearbeitungen** der Klassifikation; Mappings zu anderen Systemen brauchen eigenen Vertrag mit der WHO | keine Lizenzgebühr | **Später**, nur zum Nachschlagen/Anzeigen von Diagnosen, die der Nutzer selbst einträgt. Keine automatische Kodierung, kein eigenes Mapping ICD-10-GM ↔ ICD-11. |
| **ICD-10-GM** (BfArM) | Download (Klassifikationsdateien) | Nutzungsbedingungen des BfArM (kostenfrei) | kostenlos | **Später**, für deutsche Diagnosebezeichnungen. Lokal, offline. |
| **Oura API v2** | OAuth2, persönliches Konto | Oura-Nutzungsbedingungen; Daten verlassen Oura-Cloud Richtung App | kostenlos mit Oura-Konto | bereits geplant (M2), braucht Konto |
| **Claude-Vision** (Mahlzeitenfoto) | Anthropic API | Daten gehen an Anthropic | Kosten je Bild | nur nach Freigabe (Kosten + Datenschutz); Ergebnis nur Name + Menge, Nährwerte aus Datenbank (Prinzip aus 2.6) |

### 3.3 Fotoerkennung von Mahlzeiten
Kein geprüftes, frei lizenziertes On-Device-Modell gefunden, das deutsche Gerichte zuverlässig erkennt. Optionen in Reihenfolge: (1) Barcode + Suche + Favoriten (offline, kostenlos), (2) Claude-Vision mit Schema „Name, geschätzte Menge, Unsicherheit“ und Bestätigung durch den Nutzer, (3) Apple-Frameworks (Vision für Barcode/Text auf Verpackungen). Die Nährwerte kommen immer aus OFF/USDA/BLS, nie aus der KI.

## 4. Übernehmbare Konzepte (Zusammenfassung, ergänzt 4.2)

| Konzept | Vorbild | Ziel-Modul | Prüfbar durch |
|---|---|---|---|
| Belegkatalog: Quelle (Herausgeber, URL, Lizenz, Ausgabe) + Regel (Aussage, Zielgruppe, Grenzen, Evidenzgrad) | HealthTrack `lib/evidence` | HealthEvidence | Unit-Tests: jede Regel hat ≥ 1 gültige Quelle |
| Erklärung zu jeder angezeigten Zahl (Rechenweg, Daten, n, Zeitraum) | ygeia `explain.js` | HealthEvidence + Experience | UI-Test: jede Kennzahl-Karte hat „Wie berechnet?“ |
| KI liefert nie Zahlen, die die App selbst berechnet (Schema ohne Zahlenfelder bzw. nur mit `beleg_id`) | OpenNutriTracker (Konzept) | ClaudeIntelligence | Schema-Test + Zahlenprüfer |
| Regeln zuerst, KI optional mit Rückfall | open-coach | Coach / Intelligence | Test ohne Schlüssel |
| Wochenanpassung Training, +10 %/Woche Obergrenze, ohne Ersatzwerte | open-coach | Analytics/Training | Unit-Tests |
| Energiebedarf (Mifflin-St Jeor), Defizit-Obergrenze, Sonderfälle nur Erhalt + Hinweis | HealthTrack, OpenNutriTracker (Konzept), Primärliteratur | Analytics/Nutrition | Unit-Tests gegen Literaturbeispiele |
| Körperformeln als reine Funktionen mit Plausibilitätsgrenzen, `nil` statt Fantasiewert | healthos | Analytics/Body | Unit-Tests |
| Lebensmittel-Cache inkl. „nicht gefunden“ | HealthTrack | DeviceIntegration/Nutrition | Unit-Tests |
| Belastung relativ zur eigenen Historie (28 Tage) | ygeia | Analytics/Training | Unit-Tests |
| Schreibende KI-Werkzeuge nur nach Bestätigung | zerocoach | ClaudeIntelligence | UI-Test |
| Export mit veröffentlichtem JSON-Schema | open-coach | Foundation | Schema-Validierung im Test |

## 5. Nicht übernehmbare Komponenten

- Jeglicher Code aus **wger** (AGPL), **OpenNutriTracker** (GPL), **open-health-sync** (AGPL), **Gadgetbridge** (AGPL), **healthsave-observatory** (Elastic).
- Alles aus **Moment** (keine Lizenz).
- **RepDB-Übungsdaten** aus zerocoach (eigene, kostenpflichtige Lizenz).
- Fremde Scores: Readiness (HealthTrack, zerocoach), Food-Quality und Strength Rank (ygeia), Körperfett-Kategorien mit Wertung (healthos).
- Ersatzwerte für fehlende Daten (open-coach: RPE = 5).
- Inoffizielle KI-Endpunkte (HealthTrack), Telegram-Weitergabe, Server-Backends (Supabase, Next.js), lokale LLM-Laufzeiten (zerocoach) – nicht unser Stack.

## 6. Technische Risiken

1. **Lizenzvermischung:** Wer GPL/AGPL-Code „nur übersetzt“, erzeugt ein abgeleitetes Werk. Regel: Bei GPL/AGPL-Repos wird nur die README/Architektur gelesen, Formeln kommen aus der Primärliteratur.
2. **ODbL Share-Alike:** Ein lokaler Cache ist unproblematisch; eine veröffentlichte, aus OFF abgeleitete Datenbank müsste unter ODbL stehen. Wir veröffentlichen keine.
3. **Datenschutz bei Lebensmittel-APIs:** Barcode-Abfragen verraten Essgewohnheiten an Dritte (OFF, USDA). In der App offenlegen; Offline-BLS bevorzugen, wo möglich.
4. **API-Schlüssel:** USDA- und Claude-Schlüssel nie im Repo, nie in Logs; Keychain `WhenUnlockedThisDeviceOnly`.
5. **ICD-11 CC BY-ND:** keine eigenen Übersetzungen/Kürzungen der Klassifikation, keine selbstgebauten Mappings.
6. **Medizinprodukt-Grenze:** Ernährungs- und Trainingsempfehlungen bleiben allgemein und belegt; keine Therapie- oder Diagnoseaussagen (siehe Expertenrat, Rolle D).

## 7. Konkrete Integrationsaufgaben (Vorschlag an den Implementierungs-Thread)

Die Reihenfolge der PRs 1–7 aus `OPEN-SOURCE-REVIEW.md` §7 bleibt unverändert (Ring → HealthKit → Langzeit → SpO₂ → Claude → weitere Kennzahlen). Dieses Audit ergänzt Aufgaben **für danach** und eine Aufgabe für PR 6:

| Prio | Aufgabe | Modul | Abhängigkeit |
|---|---|---|---|
| zu PR 6 | Antwort-Schema für Claude: Zahlen nur als `{wert, einheit, beleg_id}`, kein freies Zahlenfeld; Freitext-Zahlen ohne Beleg → „nicht belegt“ | ClaudeIntelligence | OPEN-SOURCE-REVIEW §6 |
| zu PR 6 | Belegkatalog v1 (`SourceCard`, `EvidenceRule`) mit den Quellen, die die SpO₂- und Pulsanalyse tatsächlich zitiert | HealthEvidence | – |
| A | „Wie berechnet?“-Ansicht je Kennzahl (Rechenweg, n, Zeitraum, Quellen, Qualität) | Evidence + Experience | PR 5 |
| B | BODY: Gewicht/Größe aus HealthKit, Körperformeln (BMI neutral, Navy-Methode optional) als getestete reine Funktionen | Analytics/Body | PR 3 |
| C | Ernährung Stufe 1: Barcode (OFF), Suche (USDA), lokaler Cache, manuelle Einträge; Nährwerte nur aus Datenbanken | DeviceIntegration + Foundation | Freigabe Johannes (Fremddienste) |
| D | Ernährung Stufe 2: BLS 4.0 offline einbetten | Foundation | Lizenzprüfung BLS |
| E | MOVE: Trainingslog, Wochenanpassung (+10 %), Last relativ zu 28 Tagen, 1RM (Brzycki, Primärquelle) | Analytics/Training | PR 7 |
| F | Coach: Regeln zuerst, Claude formuliert; schreibende Aktionen nur nach Bestätigung | Intelligence | E, PR 6 |
| G | Diagnosen (optional): Nutzer trägt selbst ein, Anzeige via ICD-10-GM/ICD-11-Suche, keine automatische Kodierung | Foundation | Registrierung WHO-API; Entscheidung Johannes |

## 8. Quellen (Recherche)
- WHO: [ICD-11 License](https://icd.who.int/docs/icd-api/license), [ICD-11 Terms of Use](https://www.who.int/publications/m/item/icd-11-terms-of-use-and-license-agreement), [WHO-FIC Interoperability Hub](https://www.who.int/standards/classifications/who-fic-interoperability-hub)
- Open Food Facts: [API-Dokumentation](https://openfoodfacts.github.io/openfoodfacts-server/api), [Lizenz](https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/tutorials/license-be-on-the-legal-side/), [ODbL](https://wiki.openfoodfacts.org/ODBL_License)
- BLS 4.0: [heise.de-Meldung](https://heise.de/-11123877), [Max Rubner-Institut](https://www.mri.bund.de/en/institutes/nutritional-behaviour/translate-to-english-arbeitsbereiche/german-nutrient-database-bundeslebensmittelschluessel-bl/)
- USDA FoodData Central: <https://fdc.nal.usda.gov/>
