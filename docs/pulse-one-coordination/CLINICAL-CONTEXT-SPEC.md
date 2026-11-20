# PULSE CLINICAL CONTEXT – Fachkonzept (Master Directive 5.0, Teil V + XI, Release 7)

Stand: 2026-11-20 · Status aller Punkte: **Geplant** (§14) · Verfasser: Claude Code
Perspektiven: D (Clinical Informatics), I (Security & Privacy), G (AI Systems Architect), J (QA).
Dies ist **keine Rechtsberatung.** Vor jeder Weitergabe an andere Personen braucht es eine fachkundige regulatorische Prüfung (Teil XI).

> Grundsatz: PULSE ONE bleibt **Wellness Intelligence**. Persönliche medizinische Angaben sind ein freiwilliger, getrennt gespeicherter
> Kontext, den der Nutzer selbst einträgt. Die App und Claude stellen **keine** Diagnosen fest, schreiben **keine** ICD-Codes eigenständig
> ins Profil und ändern **keine** Medikation. Ein „Clinical Decision Support“-Forschungsmodul wird nur als Grenze und Schnittstelle
> beschrieben und **nicht** in auslieferbare Builds kompiliert.

Hinweis zur Prüfung: Die WHO- und BfArM-Seiten waren aus der Cloud-Umgebung gesperrt. Angaben stammen aus Websuche in den offiziellen Seiten (2026-11-20);
mit „prüfen“ markierte Punkte vor Release 7 am Original verifizieren und in `DECISIONS.md` festhalten.

---

## 1. Zwei technisch getrennte Funktionsbereiche

| | Wellness Intelligence (Release 1–7) | Clinical Decision Support – Forschungsmodul |
|---|---|---|
| Zweck | persönliche Trends, Bewegung, Ernährung, Training, allgemeine Gesundheitsinformation | mögliche diagnostische/therapeutische Entscheidungsunterstützung |
| Status | wird gebaut | **nur Konzept**; kein Code in Release-Konfiguration |
| Technik | Hauptziel `PulseOne`, Pakete `PulseCore` | eigenes Swift-Paket `PulseClinicalResearch`, nur im Schema `PulseOne-Research` mit Compiler-Flag `CDS_RESEARCH`; Release- und TestFlight-Konfiguration linken es nicht. CI-Prüfung: `nm`/Symbolsuche im Release-Archiv findet keine `PulseClinicalResearch`-Symbole |
| Daten | Messwerte + freiwilliger Kontext (lesend) | nie mit echten Daten anderer Personen; Zugriff nur über definierte, lesende Schnittstelle |
| Voraussetzungen zur Aktivierung | – | Zweckbestimmung, klinische Bewertung/Validierung, Risikomanagement (ISO 14971), Software-Lebenszyklus (IEC 62304), Einstufung nach MDR, ggf. Benannte Stelle, Freigabe Johannes |

**Entscheidung (vorgeschlagen):** Release 7 baut nur den Wellness-Teil plus die Trennlinie (Paketgrenze, Flag, CI-Prüfung). Das Forschungsmodul bleibt leer.

## 2. Regulatorische Einordnung (Stand des Wissens, prüfen lassen)

- **EU MDR 2017/745:** Software ist ein Medizinprodukt, wenn ihre **Zweckbestimmung** medizinisch ist (Diagnose, Überwachung, Vorhersage, Behandlung von Krankheiten). Orientierung: MDCG 2019-11 (Qualifizierung und Klassifizierung von Software). Software für Informationen zu diagnostischen oder therapeutischen Entscheidungen fällt nach **Regel 11** (Anhang VIII) mindestens in Klasse IIa → Benannte Stelle nötig. Allgemeine Lifestyle- und Wohlbefindensfunktionen fallen nicht darunter.
- Daraus folgt für Texte, App-Store-Beschreibung und UI: keine Formulierungen wie „erkennt“, „diagnostiziert“, „überwacht Erkrankung“, „warnt vor Vorhofflimmern“. Zweckbestimmung (Entwurf): *„PULSE ONE zeigt persönliche Gesundheits- und Aktivitätsdaten, beschreibt Trends und unterstützt Bewegung, Ernährung und Regeneration. PULSE ONE ist kein Medizinprodukt und ersetzt keine ärztliche Beratung.“*
- **EU AI Act:** KI-Systeme, die Sicherheitsbauteil eines Medizinprodukts mit Konformitätsbewertung durch Dritte sind, gelten als Hochrisiko (Art. 6 Abs. 1). Solange PULSE ONE kein Medizinprodukt ist, entfällt das; für das Forschungsmodul wäre es relevant.
- **DSGVO Art. 9:** Gesundheitsdaten sind besondere Kategorien. Private Nutzung durch Johannes selbst: Haushaltsausnahme (Art. 2 Abs. 2 lit. c). Bei Weitergabe der App an andere: ausdrückliche Einwilligung, Datenschutzerklärung, Auftragsverarbeitung/Übermittlung an Anthropic (USA) prüfen.
- **Anthropic-Nutzungsrichtlinien:** Gesundheitsnahe Anwendungen mit Endnutzerkontakt haben zusätzliche Anforderungen (u. a. Hinweis auf KI, fachliche Prüfung bei Hochrisiko-Nutzung). Vor Release 7 die aktuelle Usage Policy lesen und Ergebnis in `DECISIONS.md`.

## 3. Persönliches Gesundheitsprofil

**Entschieden (Johannes, 2026-11-20):** Bekannte Diagnosen trägt der Nutzer selbst ein. Sie werden angezeigt und, nur mit Freigabe, als Kontext für Analysen genutzt. Keine weitere Verwendung.

### 3.1 Datenmodell `ClinicalEntry`

| Feld | Bemerkung |
|---|---|
| id, Profil-ID | nur eigenes Profil |
| Art | `diagnosis`, `symptom`, `medication`, `allergy`, `limitation`, `history`, `doctorTrainingLimit` |
| Bezeichnung (Freitext, Pflicht) | so, wie der Nutzer sie kennt |
| Code (optional) | System (`icd10gm`, `icd11mms`), Code, Version (z. B. `2026`, `2026-01`), offizieller Titel zum Zeitpunkt der Auswahl |
| Herkunft | `userEntered`, `fromDoctorDocument` (Nutzer sagt: steht im Arztbrief) |
| Status | `current`, `past`, `unknown`; Beginn/Ende optional |
| Medikation | Wirkstoff/Handelsname Freitext, Dosis und Rhythmus Freitext, seit |
| Ärztliche Trainingsgrenze | z. B. max. Puls, verbotene Belastungsarten, gültig bis |
| Freigabe an Claude | je Eintrag, Standard **aus** |
| Notiz | Freitext |

**Getrennte Speicherung:** eigener SwiftData-`ModelContainer` mit eigener Datei `Clinical.store` (Dateischutz `complete`), nicht im Messwert-Store.
Kein automatischer Fluss aus Sensordaten in dieses Profil und umgekehrt. Export und Löschen getrennt („Gesundheitsprofil löschen“).
Backup: Die Datenbank darf ins iCloud-Backup (Johannes, 2026-11-19); das gilt auch für `Clinical.store`. API-Schlüssel bleiben `ThisDeviceOnly` und sind nicht im Backup.
Optional: Zugriff auf diesen Bereich nur nach Face ID (`LocalAuthentication`), Standard an.

### 3.2 Was es nicht gibt

- Keine Wechselwirkungsprüfung von Medikamenten (wäre Medizinprodukt-Funktion; freie deutsche Arzneimitteldatenbanken mit Wechselwirkungen gibt es nicht kostenlos).
- Keine automatische Diagnosevorschläge, keine Risiko-Scores, keine „Wahrscheinlichkeit für …“.

## 4. ICD-Integration

| | ICD-10-GM (Deutschland) | ICD-11 MMS (WHO) |
|---|---|---|
| Zweck in PULSE ONE | Codes aus vorhandenen deutschen Arztbriefen/AU-Bescheinigungen wiederfinden | internationale, mehrsprachige Bezeichnung; Zukunft |
| Herausgeber | BfArM (im Auftrag des BMG) | WHO |
| Bezug | Download (ClaML/XML, PDF, HTML), nur Deutsch; aktuelle Version **ICD-10-GM 2026** (endgültige Fassung veröffentlicht 18.09.2025) | **ICD-API** (REST), Registrierung kostenlos; alternativ lokal installierbare API (Container) |
| Kosten | kostenlos | kostenlos, keine Nutzungsgebühren |
| Lizenz/Bedingungen | Mit dem Download kommt ein Nutzungsvertrag mit dem BfArM zustande (Downloadbedingungen als PDF). **Prüfen**, ob Einbettung in eine App und Weitergabe erlaubt sind, bevor die Datei ins App-Bundle kommt. | Inhalte: CC BY-ND 3.0 IGO (keine Bearbeitungen, Namensnennung); WHO meldet eine „offenere“ Lizenz, Details **prüfen**. Software der API eigene Lizenz. **Mappings/Crosswalks** zwischen ICD-10 und ICD-11 sind von der Lizenz ausgenommen und brauchen eine schriftliche Vereinbarung. |
| Technik | einmaliger Import der ClaML-Datei in eine lokale, durchsuchbare SQLite/SwiftData-Tabelle (Code, Titel, Inklusiva, Exklusiva, Version); Volltextsuche offline | OAuth2 Client Credentials: Token von `https://icdaccessmanagement.who.int/connect/token` (Scope `icdapi_access`, gültig ca. 1 h); Anfragen mit `API-Version: v2`, `Accept-Language: de` (deutsche Übersetzung **prüfen**), Suche über `…/icd/release/11/{release}/mms/search` |
| Geheimnis | keins | Client-ID/-Secret gehören zum registrierten Konto. Für die private App: Johannes registriert sich selbst, Eingabe in den Einstellungen, Keychain. Für Weitergabe: nicht im Bundle ausliefern → lokale Kopie oder Server |
| Versionen | Jahresversion je Eintrag gespeichert; neue Version = neuer Import, alte bleibt für alte Einträge lesbar | Release-ID (z. B. `2026-01`) je Eintrag gespeichert |

**Entscheidung (vorgeschlagen):** Release 7 startet mit **ICD-10-GM offline** (deutsche Arztbriefe nutzen ICD-10-GM). ICD-11 als zweite Stufe über die WHO-API,
nur Suche und Anzeige, unveränderte Titel mit Namensnennung „ICD-11, WHO, Lizenz …“. **Keine eigene Umschlüsselung** ICD-10 ↔ ICD-11 (Lizenzausnahme).

### 4.1 Regeln zur Code-Erfassung

- Ein Code wird **nur** durch eine Nutzeraktion gespeichert: Suche → Treffer antippen → Bestätigen („Diese Diagnose wurde ärztlich festgestellt“ / „Ich bin nicht sicher“).
- Claude hat **kein** Werkzeug zum Schreiben ins Gesundheitsprofil. Nennt Claude eine Erkrankung als mögliche Erklärung, wird daraus nie ein Eintrag.
- Fototext von Arztbriefen (später, optional): Erkennung lokal mit Vision (`VNRecognizeTextRequest`), gefundene Codes als **Vorschlag** mit Pflichtbestätigung je Code; das Bild verlässt das Gerät nicht.

## 5. Klinisch informierte Interpretation

### 5.1 Datenfluss zu Claude

`HealthAnalysisContext.clinicalContext` (siehe `CLAUDE-INTELLIGENCE-SPEC.md` §3.1) enthält nur Einträge mit Freigabe:
`{"type": "diagnosis", "label": "Asthma bronchiale", "code": "J45.9", "system": "icd10gm-2026", "status": "current", "origin": "userEntered"}`.
Medikamente nur als Wirkstoffname ohne Dosis, außer der Nutzer gibt die Dosis ausdrücklich frei. Vorschau zeigt den klinischen Teil farblich abgesetzt.

### 5.2 Claude darf / darf nicht (Systemprompt + Validator)

| Darf | Darf nicht |
|---|---|
| Messmuster beschreiben, Veränderungen benennen | Diagnosen als bestätigt darstellen, wenn sie nicht im Profil stehen |
| allgemein bekannte mögliche Einflussfaktoren erläutern (z. B. „Betablocker senken typischerweise die Herzfrequenz“, wenn der Nutzer einen eingetragen hat) | Erkrankungswahrscheinlichkeiten ausgeben |
| eingetragenen Kontext berücksichtigen | aus Ringdaten Krankheiten feststellen |
| auf Messunsicherheit hinweisen (Ring-SpO₂, optische HRV) | Medikamente oder Dosen ändern, absetzen, empfehlen |
| Fragen für das Arztgespräch vorschlagen | Behandlung ersetzen, Arztbesuch ausreden |
| bei geeigneten Anzeichen zur Abklärung raten | |

## 6. SafetyRules (gemeinsamer Validator, wird ab Release 3 genutzt)

Lokale, testbare Regeln in `PulseCore/Intelligence/SafetyRules.swift`; Ergebnis: Aussage erlauben, verwerfen oder mit Hinweis versehen.

| Regel | Prüfung | Aktion |
|---|---|---|
| S1 Diagnosesprache | Muster: „Sie haben/du hast + Krankheitsbegriff“, „Diagnose:“, „leidest an“, ICD-Code im Antworttext, der nicht im freigegebenen Profil steht | verwerfen |
| S2 Wahrscheinlichkeit | Prozent-/Risikoangaben zu Erkrankungen („70 % Wahrscheinlichkeit“, „erhöhtes Risiko für …“) | verwerfen |
| S3 Medikation | Verben „absetzen, erhöhen, reduzieren, einnehmen“ in Verbindung mit Medikament | verwerfen + Hinweis „Medikation nur mit Arzt ändern“ |
| S4 Kausalität | siehe Intelligence §3.4 | kennzeichnen |
| S5 Abklärungshinweis | Fakten über festen Schwellen erzwingen `medicalReferral.level ≥ mention` (Tabelle unten), unabhängig von Claude | ergänzen |
| S6 Notfall | Nutzer nennt im Chat Brustschmerz, Atemnot, Lähmung, Bewusstlosigkeit | feste lokale Antwort: „Bei akuten Beschwerden 112 anrufen“, kein Claude-Aufruf nötig |

Feste Schwellen für S5 (beschreibend, nicht diagnostisch; Werte mit Perspektive D vor Umsetzung gegenprüfen):

| Fakt | Schwelle | Hinweistext (Beispiel) |
|---|---|---|
| SpO₂ Einzelwerte | mehrere Werte < 90 % in Ruhe, Abdeckung ausreichend | „Mehrere niedrige Messwerte. Ringmessungen können ungenau sein; wenn sich das wiederholt oder du Beschwerden hast, ärztlich abklären lassen.“ |
| Ruhepuls | 14-Tage-Median > 100 bpm oder < 40 bpm ohne Ausdauertraining | Abklärung empfehlen |
| Ruhepuls-Trend | > 10 bpm über Basislinie über ≥ 7 Tage | erwähnen |
| Schlafdauer | 14-Tage-Mittel < 5 h | erwähnen |

## 7. Ärztliche Gesprächsvorbereitung

Analyseart „Arztgespräch vorbereiten“: Zeitraum wählen → lokale Zusammenfassung (Diagramme, Kennzahlen, Datenqualität, Quellen) + von Claude formulierte, belegte
**Fragen** an die Ärztin/den Arzt. Export als PDF (lokal erzeugt, `UIGraphicsPDFRenderer`), Teilen-Menü. Kopfzeile: „Selbst erfasste Wellness-Daten, keine medizinische Messung. Gerät/Quelle je Wert angegeben.“

## 8. Arbeitspakete

| PR | Inhalt | Abnahme |
|---|---|---|
| R7-0 | `SafetyRules` (S1–S6) als Kern mit Tests – **wird schon in Release 3 gebraucht** | 40 Testsätze (erlaubt/verboten) |
| R7-1 | `Clinical.store`, `ClinicalEntry`, Screens, Face-ID-Schutz, Löschen/Export | |
| R7-2 | ICD-10-GM-Import (nach Lizenzprüfung), Offline-Suche | 20 Codes aus echten Briefen gefunden |
| R7-3 | Freigaben je Eintrag, `clinicalContext` im Analysekontext, Vorschau | Unit: nichts ohne Freigabe |
| R7-4 | Arztgespräch-Export | |
| R7-5 | ICD-11 über WHO-API (optional) | |
| R7-6 | Trennlinie Forschungsmodul: leeres Paket, Schema, Flag, CI-Symbolprüfung | CI |

Abnahme Release 7 (Directive): korrekte Terminologie (Codes + Titel + Version stimmen mit der Quelle), sichere Datenverwendung (Freigabe-Tests), dokumentierte Produktgrenzen (dieses Dokument + Zweckbestimmung in `DECISIONS.md`).

## 9. Risiken

| Risiko | Gegenmaßnahme |
|---|---|
| App wird faktisch zum Medizinprodukt | Zweckbestimmung, Sprachregeln S1–S3, keine Risiko-Scores, Forschungsmodul nicht gelinkt |
| Lizenzverstoß ICD | Bedingungen vor Einbettung prüfen, keine eigenen Mappings, unveränderte Titel mit Namensnennung |
| Sensible Daten gehen ungewollt an Claude | getrennter Store, Standard aus, Freigabe je Eintrag, Vorschau |
| Falsche Sicherheit durch Hinweise | Hinweise sagen immer „Messung kann ungenau sein“, nie „alles in Ordnung“ |
