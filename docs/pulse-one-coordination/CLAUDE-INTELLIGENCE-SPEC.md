# CLAUDE INTELLIGENCE – Fachkonzept (Master Directive 5.0, Teil VI, Release 3)

Stand: 2026-11-20 · Status aller Punkte: **Geplant** (§14) · Verfasser: Claude Code
Perspektiven: G (AI Systems Architect), I (Security & Privacy), C (Health Data Scientist), J (QA).
Abhängig von: `HEALTH-DATA-SPEC.md` und `PRODUCT-ARCHITECTURE-5.0.md` (anderer Thread), Release 2 (Analyse-Kern).
Ersetzt und erweitert: `SANIERUNG-4.0.md` §7 und §8.

> Kurz: Die App rechnet alle Zahlen **lokal**. Claude bekommt nur einen versionierten, minimierten Kontext mit
> nummerierten Fakten, antwortet in einem festen JSON-Schema und muss jede Aussage mit Fakt-IDs belegen.
> Die App prüft jede Zahl gegen die Fakten, bevor etwas angezeigt wird. Der API-Schlüssel liegt nur im Keychain.

Quellen (geprüft 2026-11-20): Anthropic-Doku „Structured outputs“, „Vision“, Modell- und Preistabelle
(`platform.claude.com/docs`), Skill-Referenz `claude-api` (Stand 2026-11-03).

---

## 1. Ausgangslage im Code

| Vorhanden | Datei | Nutzung in Release 3 |
|---|---|---|
| Normalisiertes Messwertmodell mit Herkunft und Qualität | `PulseCore/Connect/HealthSample.swift` (`SampleKind`, `SampleQuality`, `DataSourceKind`, `MeasurementMethod`) | Grundlage jedes Fakts; nur `valid`/`plausible` gehen in Kontexte (DECISIONS 2026-11-20) |
| Tageswerte je Aggregationsart mit Herkunft | `PulseCore/Connect/DailySeries.swift` | Quelle für Tages-/Wochenkennzahlen |
| Quellenwahl je Messwert | `PulseCore/Connect/SourcePolicy.swift` | Fakten tragen die gewählte Herkunft |
| Zeitliche Profilzuordnung | `PulseCore/Connect/ProfileAssignment.swift` | nur Werte des aktiven Profils, `profileID == nil` wird ausgeschlossen |
| Keychain, Netzwerk-Client, Einstellungen | – | **neu** |
| Baselines, Trends, Abdeckung | – | kommt mit Release 2 (`HEALTH-DATA-SPEC.md`); Release 3 setzt darauf auf |

Es gibt kein offizielles Anthropic-SDK für Swift. Aufruf daher per `URLSession` gegen die REST-API
(`POST https://api.anthropic.com/v1/messages`). Keine Drittanbieter-Bibliothek (CLAUDE.md: Abhängigkeiten vermeiden).

---

## 2. Einstellungen → KI-Anbieter → Anthropic Claude

| Funktion | Umsetzung | Abnahme |
|---|---|---|
| Schlüssel eingeben | `SecureField`, Einfügen erlaubt, keine Anzeige im Klartext, Prüfung auf Präfix `sk-ant-` nur als Hinweis | Schlüssel erscheint nie in Logs, Screenshots, Diagnose-Export (Test: Log-Grep in UI-Test) |
| Speicherung | Keychain `kSecClassGenericPassword`, Service `de.sommerlabs.pulseone.anthropic`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `kSecAttrSynchronizable = false` | kein iCloud-Sync, nicht im Geräte-Backup wiederherstellbar auf anderem Gerät |
| Verbindungstest | `GET /v1/models` mit `x-api-key` und `anthropic-version`; Ergebnis: erreichbar / Schlüssel ungültig (401) / kein Guthaben bzw. Limit (Fehlertext der API) / offline | Szenario C1 |
| Modellwahl | Liste aus `GET /v1/models`, gefiltert auf die drei unten freigegebenen; Vorgabe **Claude Opus 5.5** (`claude-opus-5-5`) | gewähltes Modell steht in jeder Analyse |
| Datenfreigaben | je Kategorie ein Schalter: Herz (Puls, Ruhepuls, HRV), SpO₂, Schlaf, Aktivität, Training, Ernährung (R5), Körpermaße, Ziele, Klinischer Kontext (R7, getrennt, Standard **aus**) | Kontext enthält nie eine abgeschaltete Kategorie (Unit-Test) |
| Analysehäufigkeit | Nur manuell (Vorgabe) · täglich morgens · wöchentlich Montag; automatische Läufe nur bei aktivierter Kostengrenze | |
| Kostenkontrolle | Monatsbudget in USD (Vorgabe 10 $), Warnung bei 80 %, Stopp bei 100 %; Kostenschätzung vor jedem Senden; tatsächliche Kosten aus `usage` danach | Szenario C3 |
| Analysehistorie | Liste aller Läufe: Zeit, Art, Zeitraum, Modell, Kontextversion, Token, Kosten, Ergebnis, gesendeter Kontext (einsehbar) | |
| Schlüssel entfernen | löscht Keychain-Eintrag; Historie bleibt, kann separat gelöscht werden | |

Zusätzlich empfohlen (Johannes, einmalig in der Anthropic Console): eigener Workspace „PULSE ONE“ mit eigenem Schlüssel
und **Ausgabenlimit** im Workspace. Das ist die harte Grenze, die auch bei einem App-Fehler greift.

### 2.1 Direkter Aufruf vom iPhone oder eigener Server?

| Kriterium | Direkt (empfohlen für jetzt) | Eigener Vermittlungsserver |
|---|---|---|
| Schlüssel | liegt im Keychain des iPhones, Besitzer = Nutzer | liegt auf dem Server; App braucht eigenes Login |
| Risiko | Gerät kompromittiert → Schlüssel weg; begrenzt durch Workspace-Limit und Widerruf in der Console | Server ist neues Angriffsziel, braucht Betrieb, Logging-Disziplin, Datenschutzvertrag |
| Datenfluss | iPhone → Anthropic | iPhone → eigener Server → Anthropic (zusätzlicher Empfänger von Gesundheitsdaten) |
| Kosten | 0 € | Hosting ab ca. 5 €/Monat, plus Pflegeaufwand |
| Wann | ein Nutzer, eigener Schlüssel (Stand heute) | erst bei Verteilung an Dritte; braucht Freigabe von Johannes |

**Entscheidung (vorgeschlagen):** direkt. Server nur, wenn PULSE ONE jemals an andere Personen geht.

---

## 3. Analysepipeline

```
Schritt 1  Sammeln      SampleStore (nur valid/plausible, aktives Profil, freigegebene Kategorien)
Schritt 2  Rechnen      AnalyticsEngine (R2): Basislinie, Band, Trend, Abdeckung, Ausreißer, Korrelationen
Schritt 3  Kontext      HealthAnalysisContext v1 (JSON, Fakten mit IDs) + Vorschau für den Nutzer
Schritt 4  Claude       POST /v1/messages, output_config.format = json_schema, Streaming
Schritt 5  Prüfen       ResponseValidator: Schema, Fakt-IDs, Zahlenabgleich, Sicherheitsregeln
Schritt 6  Anzeigen     Bericht mit antippbaren Belegen; bei Prüffehler: nichts Ungeprüftes zeigen
```

Module (neu, `Packages/PulseCore/Sources/PulseCore/Intelligence/`, rein logisch und mit Swift Testing testbar):
`HealthAnalysisContext`, `ContextBuilder`, `AnalysisSchema`, `ResponseValidator`, `CostEstimator`, `SafetyRules`.
App-Seite (`Sources/Intelligence/`): `AnthropicClient` (URLSession, Streaming), `KeychainStore`, `AnalysisStore` (SwiftData), Screens.

### 3.1 HealthAnalysisContext v1

Jede Zahl, die Claude sehen darf, ist ein **Fakt** mit stabiler ID (entspricht der `beleg_id` im Expertenrat/Audit). Claude darf nur Fakten zitieren, keine neuen Messwerte erfinden.
Jeder Fakt hat in der App ein „Wie berechnet?“-Blatt (Rechenweg, Daten, n, Zeitraum, Quelle; Konzept aus ygeia laut Audit).

```json
{
  "contextVersion": 1,
  "analysisType": "weekly",
  "generatedAt": "2026-11-20T07:00:00+01:00",
  "period": {"start": "2026-11-13", "end": "2026-11-19", "timezone": "Europe/Berlin"},
  "comparisonPeriod": {"start": "2026-10-16", "end": "2026-11-12"},
  "profile": {"ageRange": "40-49", "sex": "male", "goals": ["Ausdauer verbessern"], "sports": ["Laufen", "Reiten"]},
  "consentedCategories": ["heart", "sleep", "activity"],
  "facts": [
    {"id": "F1", "kind": "resting_heart_rate", "stat": "median", "value": 58, "unit": "bpm",
     "period": "2026-11-13/2026-11-19", "n": 7, "coverage": 1.0,
     "baseline": {"median": 55, "p25": 53, "p75": 57, "windowDays": 30},
     "source": "apple_health", "quality": "valid"},
    {"id": "F2", "kind": "sleep_duration", "stat": "mean", "value": 6.1, "unit": "h", "n": 6, "coverage": 0.86,
     "baseline": {"median": 7.0, "p25": 6.6, "p75": 7.4, "windowDays": 30}, "source": "apple_health", "quality": "valid"},
    {"id": "C1", "type": "correlation", "a": "sleep_duration", "b": "resting_heart_rate", "method": "spearman",
     "rho": -0.41, "n": 28, "lagDays": 1, "note": "beobachteter Zusammenhang, keine Ursache"}
  ],
  "dataGaps": [{"kind": "spo2", "reason": "keine Messwerte im Zeitraum"}],
  "events": [{"id": "E1", "date": "2026-11-15", "type": "training", "label": "Laufen 42 min, RPE 7"}],
  "clinicalContext": null
}
```

Regeln:
- **Datenminimierung:** keine Rohsamples, keine Namen, keine Geräte-IDs, kein Geburtsdatum (nur Altersspanne), keine Ortsdaten. Standard sind Tages- und Periodenkennzahlen. Stundenwerte nur für Tagesanalyse.
- **Versionierung:** `contextVersion` erhöht sich bei jeder Formatänderung; gespeicherte Analysen behalten ihre Version, damit Vergleiche nachvollziehbar bleiben.
- **Vorschau vor dem Senden:** Kategorien, Zeitraum, Anzahl Fakten, geschätzte Token und Kosten; „Gesendeten Inhalt ansehen“ zeigt das JSON lesbar.
- **Klinischer Kontext** nur, wenn Release 7 aktiv **und** separat freigegeben (siehe `CLINICAL-CONTEXT-SPEC.md` §5).

### 3.2 API-Aufruf (Release 3, geprüft gegen die aktuelle Doku)

```http
POST /v1/messages
x-api-key: <aus Keychain>
anthropic-version: 2026-10-21
content-type: application/json

{
  "model": "claude-opus-5-5",
  "max_tokens": 32000,
  "stream": true,
  "output_config": {
    "effort": "high",
    "format": {"type": "json_schema", "schema": { …AnalysisReport v1… }}
  },
  "system": [{"type": "text", "text": "<fester Systemprompt v1>", "cache_control": {"type": "ephemeral"}}],
  "messages": [{"role": "user", "content": [{"type": "text", "text": "<HealthAnalysisContext JSON>"}]}]
}
```

Technische Festlegungen (aus der Doku, nicht geraten):
- **Denken:** Bei Opus 5.5 ist „adaptive thinking“ immer an und lässt sich nicht abschalten; `thinking` wird weggelassen. Tiefe über `output_config.effort`. Vorgabe von Opus 5.5 ist `medium`; für Berichte setzen wir **`high`**, für den Chat `medium`, für Fotoanalyse (R5) `low`.
- **Strukturierte Ausgabe:** `output_config.format` mit `json_schema`. Nicht unterstützt sind u. a. `minimum`/`maximum`, `minLength`/`maxLength`, `oneOf`, rekursive Schemas; jedes Objekt braucht `additionalProperties: false`. Grenzen prüft deshalb der `ResponseValidator` lokal. Erste Anfrage mit neuem Schema hat zusätzliche Latenz (Grammatik wird 24 h gecacht).
- **Zitate:** Die API-Funktion „Citations“ ist mit `output_config.format` nicht kombinierbar. Belege laufen daher über eigene Fakt-IDs im Schema (unten).
- **Kein Prefill, keine `temperature`** (bei aktuellen Modellen abgelehnt).
- **Streaming**, weil Berichte lang sein dürfen (bis 32 000 Ausgabetoken); Fortschritt in der UI.
- **`stop_reason`** immer prüfen: `refusal` → verständlicher Hinweis, keine Teilanzeige; `max_tokens` → Bericht als unvollständig markieren und nicht validiert anzeigen.
- **Ablehnungen absichern:** Header `anthropic-beta: server-side-fallback-2026-07-01` plus `"fallbacks": "default"`, damit eine fälschliche Sicherheits-Ablehnung auf ein anderes Modell umgeleitet wird. Antwort-Modell (`model` im Response) wird gespeichert.
- **Prompt-Caching:** fester Systemprompt + Schema als gecachter Präfix; senkt Kosten bei Chat-Nachfragen. Prüfen über `usage.cache_read_input_tokens`.
- **Fehler:** 401 Schlüssel, 429 Rate-Limit (Wiederholung nach `retry-after`), 529/5xx Überlast (max. 2 Wiederholungen mit Backoff), Netzwerk offline → Analyse bleibt im Entwurf.

### 3.3 Antwortschema AnalysisReport v1 (15 Abschnitte der Directive)

```json
{
  "type": "object", "additionalProperties": false,
  "required": ["summary","dataSituation","sections","medicalReferral","openQuestions","uncertainties","actions"],
  "properties": {
    "summary":        {"$ref": "#/$defs/statementList"},
    "dataSituation":  {"$ref": "#/$defs/statementList"},
    "sections": {"type": "array", "items": {
      "type": "object", "additionalProperties": false,
      "required": ["kind","title","statements"],
      "properties": {
        "kind": {"type": "string", "enum": ["key_developments","statistical_changes","notable_patterns",
                 "possible_factors","relationships","period_comparison","personal_progress",
                 "movement_recovery"]},
        "title": {"type": "string"},
        "statements": {"$ref": "#/$defs/statementList"}}}},
    "openQuestions":  {"type": "array", "items": {"type": "string"}},
    "uncertainties":  {"$ref": "#/$defs/statementList"},
    "actions": {"type": "array", "items": {
      "type": "object", "additionalProperties": false,
      "required": ["text","domain","evidence"],
      "properties": {"text": {"type": "string"},
        "domain": {"type": "string", "enum": ["movement","recovery","sleep","nutrition","measurement","doctor"]},
        "evidence": {"$ref": "#/$defs/evidence"}}}},
    "medicalReferral": {"type": "object", "additionalProperties": false,
      "required": ["level","reason","evidence"],
      "properties": {"level": {"type": "string", "enum": ["none","mention","recommend"]},
        "reason": {"type": "string"}, "evidence": {"$ref": "#/$defs/evidence"}}}
  },
  "$defs": {
    "evidence": {"type": "array", "items": {"type": "string"}},
    "statementList": {"type": "array", "items": {
      "type": "object", "additionalProperties": false,
      "required": ["text","type","evidence"],
      "properties": {"text": {"type": "string"},
        "type": {"type": "string", "enum": ["measured","computed","observation","interpretation","recommendation"]},
        "evidence": {"$ref": "#/$defs/evidence"}}}}
  }
}
```

Die Abschnitte 1–15 der Directive bilden sich so ab: 1 `summary`, 2 `dataSituation`, 3–9 und 13 `sections[].kind`,
10 `openQuestions`, 11 `uncertainties`, 12 `actions`, 14 `medicalReferral`, 15 `evidence` an jeder Aussage.
Der Aussagetyp (`type`) trennt sichtbar: Messwert · berechnete Kennzahl · Beobachtung · KI-Deutung · Empfehlung (SANIERUNG-4.0 §8).
**Länge:** Keine künstliche Kürzung. Der Systemprompt verlangt „so ausführlich, wie die Daten tragen“; bei dünner Datenlage kurz und mit klarer Lückenbenennung.

### 3.4 ResponseValidator (Schritt 5)

Eine Analyse wird nur angezeigt, wenn alle Prüfungen bestehen. Sonst: ein automatischer Korrekturversuch
(Fehlerliste als Folgenachricht), danach Anzeige „Analyse konnte nicht geprüft werden“ mit Rohtext nur auf Wunsch und deutlich markiert.

| Prüfung | Regel | Fehlerfall |
|---|---|---|
| Schema | JSON parst, alle Pflichtfelder | Abbruch |
| Fakt-IDs | jede ID in `evidence` existiert im Kontext | Aussage verworfen |
| Belegpflicht | Typ `measured`/`computed`/`observation` braucht ≥ 1 Fakt-ID | Aussage verworfen |
| Zahlenabgleich | jede Zahl im Text (Regex inkl. Komma) muss einem zitierten Fakt entsprechen (Wert, Basislinie, n, Differenz, Prozent; Toleranz ±1 in der letzten angezeigten Stelle) | Aussage verworfen, im Prüfprotokoll |
| Kausalität | Muster wie „weil“, „verursacht“, „führt zu“ in Typ `observation`/`relationships` → Warnung; Korrelationsfakten tragen immer den Hinweis „beobachteter Zusammenhang“ | Kennzeichnung |
| Medizinische Sicherheit | `SafetyRules` aus `CLINICAL-CONTEXT-SPEC.md` §6 (keine bestätigten Diagnosen, keine Wahrscheinlichkeiten, keine Medikamentenänderung) | Aussage verworfen |
| Abdeckung | Aussage zu Kategorie mit `coverage < 0.5` ohne Unsicherheitshinweis | Warnung |

Prüfprotokoll wird mit der Analyse gespeichert (für J und für Belegnachweis in `EVIDENCE.md`).

### 3.5 Anzeige

Bericht als Abschnitte mit Aussagetyp-Kennzeichen (Design: `DESIGN-SYSTEM-5.0.md` §6). Jede Aussage hat Beleg-Chips;
Antippen öffnet den Fakt (Wert, Zeitraum, n, Abdeckung, Quelle, Qualität) und springt in das passende Diagramm im HEALTH-Bereich mit markiertem Zeitraum.

---

## 4. Analysearten

| Art | Zeitraum / Vergleich | Faktenbasis | Modell, Effort | Schätzung je Lauf* |
|---|---|---|---|---|
| Tagesanalyse | heute bzw. letzte Nacht / 30 Tage | Stundenwerte Herz, Schlafsitzung, Schritte | Opus 5.5, medium | 6k ein / 3k aus ≈ **0,08 $** |
| Wochenanalyse | 7 Tage / 4 Wochen davor | Tageswerte | Opus 5.5, high | 10k / 6k ≈ **0,16 $** |
| Monatsanalyse | Kalendermonat / 3 Monate | Tageswerte + Wochenaggregat | Opus 5.5, high | 20k / 10k ≈ **0,28 $** |
| Jahresanalyse | 12 Monate / Vorjahr | Wochen- und Monatsaggregate | Opus 5.5, high | 30k / 14k ≈ **0,40 $** |
| Langzeit-Gesamtanalyse | gesamte Historie | Monatsaggregate, Trendbrüche | Opus 5.5, high | 40k / 16k ≈ **0,48 $** |
| Schlaf | 30 Tage | Schlafdauer, -zeitpunkt, Regelmäßigkeit, Phasen falls vorhanden | Opus 5.5, high | ≈ 0,15 $ |
| Herz-Kreislauf-Daten | 30–90 Tage | Puls, Ruhepuls, HRV, SpO₂ | Opus 5.5, high | ≈ 0,18 $ |
| Belastung | 28 Tage | Trainingslast (sRPE), Erholungssignale | Opus 5.5, high | ≈ 0,15 $ |
| Ernährung (R5) | 7–30 Tage | Energie, Makros, Vollständigkeit | Opus 5.5, high | ≈ 0,15 $ |
| Training (R4) | 4–12 Wochen | Volumen, Häufigkeit, Progression | Opus 5.5, high | ≈ 0,15 $ |
| Kombiniert (R6) | frei | alle freigegebenen | Opus 5.5, high | ≈ 0,30–0,50 $ |

\*Preise Opus 5.5: 4 $ / 1 Mio. Eingabetoken, 20 $ / 1 Mio. Ausgabetoken (inkl. Denkanteil). Annahmen sind grob; die App zeigt nach jedem Lauf die echten Werte aus `usage`.
Alternativen: Sonnet 5.5 (2 $ / 10 $, etwa halbe Kosten), Haiku 5.5 (0,10 $ / 0,50 $, für Vorprüfungen).
**Beispiel-Monat** (täglich Tagesanalyse, wöchentlich Wochenanalyse, 1 Monatsbericht, 30 Chatfragen à ca. 0,06 $): ca. 2,40 + 0,64 + 0,28 + 1,80 ≈ **5–6 $/Monat**.
Option: Monats- und Jahresberichte über die Message-Batches-API (asynchron, laut Anthropic 50 % günstiger), wenn Wartezeit egal ist.

---

## 5. Gesprächsfunktion (Fragen zur eigenen Historie)

Ansatz: **Tool-Use mit lokalen Abfragewerkzeugen.** Claude bekommt nicht das ganze Archiv, sondern fragt gezielt
Kennzahlen ab; die App führt die Abfrage lokal aus und gibt nur Aggregate zurück.

| Werkzeug (`strict: true`) | Eingabe | Rückgabe (lokal berechnet) |
|---|---|---|
| `get_metric_summary` | kind, start, end, granularity (day/week/month) | Fakten wie §3.1 mit neuen IDs |
| `compare_periods` | kind, periodA, periodB | Differenz, Basislinie, n, Abdeckung |
| `get_correlation` | kindA, kindB, start, end, lagDays | Spearman ρ, n, Hinweistext |
| `list_events` | start, end, types | Trainings, Notizen, Mahlzeiten (R5) |
| `get_data_coverage` | kinds, start, end | Abdeckung, Lücken |

- `tool_choice` bleibt `auto` (erzwungene Werkzeugwahl lehnt Opus 5.5 ab).
- Jede Werkzeugantwort respektiert die Datenfreigaben; nicht freigegebene Kategorien liefern „nicht freigegeben“.
- Werkzeugaufrufe sind im Chat aufklappbar sichtbar („Claude hat abgefragt: Ruhepuls, Mai–Okt“).
- Antworten: Fließtext + Beleg-Chips. Für die Belegprüfung gibt Claude am Ende ein kurzes JSON mit Fakt-IDs je Absatz zurück (zweiter, strukturierter Abschluss-Aufruf mit `output_config.format`, effort `low`). Gleiche Zahlen- und Sicherheitsprüfung wie §3.4.
- Grenze je Frage: max. 8 Werkzeugaufrufe, geschätzte Kosten sichtbar, Abbruch-Knopf.
- Gesprächsverlauf lokal in SwiftData; „Gespräch löschen“ löscht vollständig.

Beispiel „Warum war mein Ruhepuls letzte Woche höher?“ → `compare_periods(resting_heart_rate, …)`, `get_metric_summary(sleep_duration…)`,
`list_events(training…)` → Antwort nennt beobachtete Begleitumstände („kürzerer Schlaf, zwei intensive Einheiten“), betont,
dass das keine belegte Ursache ist, und nennt bei anhaltender Abweichung den Hinweis zur ärztlichen Abklärung nach `SafetyRules`.

---

## 6. Datenschutz und Sicherheit (Perspektive I)

- Senden nur nach Freigabe: globaler Schalter + Kategorien + Vorschau je Lauf. Automatische Läufe nur, wenn der Nutzer sie einmal ausdrücklich eingeschaltet hat.
- Transport: TLS über URLSession (ATS Standard), kein Zertifikats-Pinning (Anthropic rotiert Zertifikate; Pinning würde die App brechen).
- Anthropic-API-Bedingungen: API-Inhalte werden laut Anthropic standardmäßig nicht zum Training verwendet; Aufbewahrungsdauer und Bedingungen **vor Release 3 im Anthropic Privacy Center prüfen** und in `DECISIONS.md` mit Datum festhalten. Für die private Nutzung durch Johannes selbst greift die DSGVO-Haushaltsausnahme; bei Weitergabe an Dritte nicht mehr (dann Teil XI Regulatorik).
- Analyseprotokoll: was wann gesendet wurde, ist dauerhaft einsehbar und löschbar.
- Kein Schlüssel im Repo, in CI oder in Screenshots. UI-Tests nutzen einen Mock-Client (`-uiTesting YES`, Banner „Testansicht“), nie echte API-Aufrufe.

---

## 7. Arbeitspakete (kleine PRs, Reihenfolge)

| PR | Inhalt | Tests | Abnahme |
|---|---|---|---|
| R3-1 | `KeychainStore`, Einstellungen „KI-Anbieter“, Verbindungstest, Modellliste, Schlüssel löschen | Unit (Keychain-Wrapper mit Fake), UI-Test ohne Netz | C1: Johannes gibt Schlüssel ein, Test grün |
| R3-2 | `HealthAnalysisContext` v1, `ContextBuilder`, Freigaben, Vorschau-Screen | Swift Testing: Minimierung, Freigaben, Versionsfeld | Vorschau zeigt echte Daten |
| R3-3 | `AnthropicClient` (Streaming, Fehler, Fallback-Header), `CostEstimator`, Budget | Unit mit aufgezeichneten Antworten (Fixtures, kein Netz in CI) | C3 Kostenanzeige stimmt mit Console |
| R3-4 | `AnalysisSchema` v1, `ResponseValidator`, Prüfprotokoll | Swift Testing: erfundene Zahl, fehlende ID, Kausalformulierung, Diagnoseformulierung → verworfen | – |
| R3-5 | Wochen- und Tagesanalyse Ende-zu-Ende, Bericht-UI mit Beleg-Chips, Historie | UI-Screenshots (Mock) | **C2: echte Wochenanalyse auf dem iPhone, jede Zahl antippbar und korrekt** |
| R3-6 | Monat, Jahr, Gesamt, Spezialanalysen | Fixtures je Art | Stichprobe 3 Berichte |
| R3-7 | Gesprächsfunktion mit lokalen Werkzeugen | Werkzeug-Tests, Freigabe-Tests | 6 Beispielfragen der Directive beantwortet, belegt |

Abnahme Release 3 (Directive): „Claude analysiert echte Daten und belegt seine Aussagen“ = C2 + R3-7 auf dem iPhone, Prüfprotokoll ohne verworfene Zahlen bei 3 aufeinanderfolgenden Berichten.

## 8. Risiken

| Risiko | Gegenmaßnahme |
|---|---|
| Claude erfindet Zahlen oder Ursachen | Faktenmodell, Zahlenabgleich, Typkennzeichnung, Verwerfen statt Anzeigen |
| Kosten laufen davon | Budget in App + Workspace-Limit in Console, Vorschau, keine Automatik ohne Zustimmung |
| Schema-Änderung bricht alte Analysen | Schema- und Kontextversion gespeichert, Renderer je Version |
| Modell wird abgekündigt | Modellliste live aus `/v1/models`, Vorgabe in einer Konstante, `DECISIONS.md` |
| Sicherheitsklassifikator lehnt Gesundheitsfragen ab | `fallbacks: "default"`, verständliche Meldung, Protokoll |
| Zu wenig Daten (R03-Messkette noch defekt) | Analysen nennen Abdeckung; ohne Release-1/2-Abnahme keine Release-3-Abnahme |
