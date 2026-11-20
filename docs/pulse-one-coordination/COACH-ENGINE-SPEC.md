# PULSE COACH und UNIFIED DAILY COACH – Fachkonzept (Master Directive 5.0, Teil VII + IX, Release 4 + 6)

Stand: 2026-11-20 · Status aller Punkte: **Geplant** (§14) · Verfasser: Claude Code
Perspektiven: E (Sports Scientist & Strength Coach), C (Health Data Scientist), G (AI Systems Architect), D (Clinical Informatics, Grenzen), J (QA).
Abhängig von: Release 2 (Basislinien), Release 3 (`CLAUDE-INTELLIGENCE-SPEC.md`), Profile/Onboarding (`PRODUCT-ARCHITECTURE-5.0.md`).
Open-Source-Bewertung: `OPEN-SOURCE-TECHNICAL-AUDIT.md` (gemergt): wger-Code (AGPL) verworfen, open-coach (MIT) adaptieren, RepDB-Daten aus ZeroCoach verworfen, keine fremden Readiness-Scores. Hier nur die Datennutzung von wger über dessen öffentliche API.

> Grundsatz: **Die Trainings-Engine entscheidet, Claude formuliert und schlägt vor.** Jede Planänderung, auch eine von Claude
> vorgeschlagene, läuft durch dieselben lokalen Regeln (Belastungsgrenzen, Einschränkungen, Ausrüstung, Zeit).
> Ohne API-Schlüssel funktioniert der Coach vollständig regelbasiert, nur ohne freie Sprache.

---

## 1. Ausgangslage im Code

| Vorhanden | Nutzung |
|---|---|
| `SampleKind.trainingDuration`, `.activeEnergy`, `.steps`, `.heartRate`, `.restingHeartRate`, `.heartRateVariability`, `.sleepDuration` (`HealthSample.swift`) | Erholungs- und Aktivitätssignale |
| `HealthKitAdapter` liest Mengentypen + Schlaf; **keine Workouts** (`HKWorkout`) | Release 4 ergänzt Workout-Import (Typ, Dauer, Energie, Puls) |
| `UsageContext` in `SourcePolicy.swift` | Kontext „Training“ für Quellenwahl beim Trainingspuls |
| Coach, Plan, Übungen, Benachrichtigungen | **neu** |

Neues Paketmodul: `Packages/PulseCore/Sources/PulseCore/Coach/` (reine Logik, Swift Testing). App: `Sources/Features/Coach/`, SwiftData-Modelle.

---

## 2. Onboarding (Release 4)

Erfasst, jeweils überspringbar und später änderbar; jede Angabe hat einen sichtbaren Zweck.

| Feld | Werte | Verwendung |
|---|---|---|
| Alter | Geburtsjahr | Pulszonen-Schätzung, Belastungsobergrenzen |
| Körpermaße | Größe, Gewicht (oder aus Apple Health) | Energie, Bodyweight-Skalierung |
| Fitnessniveau | Einsteiger / regelmäßig aktiv / trainiert / leistungsorientiert + 3 Testfragen (Liegestütz-Anzahl, 2-km-Gehzeit oder 5-km-Laufzeit, Wochenstunden) | Startstufe der Progression |
| Ziele | Ausdauer, Kraft, Beweglichkeit, Gewicht, Wohlbefinden, Sportart-spezifisch (max. 2 Hauptziele) | Wochenstruktur |
| Lieblingssportarten | Liste §4 | Auswahl der Hauptaktivität |
| Verfügbare Zeit | Tage pro Woche, Minuten pro Tag, bevorzugte Tageszeit | Planlänge |
| Trainingsmöglichkeiten | zu Hause, Studio, draußen, Verein, Bahn/Strecke, Wasser, Stall/Reithalle (Auswahl im Profil, kein Default; P1-004) | Übungsfilter |
| Ausrüstung | keine, Matte, Kurzhanteln, Kettlebell, Langhantel, Klimmzugstange, Widerstandsbänder, Rudergerät, Fahrrad/Ergometer | Übungsfilter |
| Gesundheitliche Einschränkungen | Körperregion + Art (Schmerz, OP, ärztlich begrenzt) + freie Notiz; ärztliche Grenzen aus Release 7 | **harte Ausschlüsse** |
| Coaching-Intensität | ruhig / ausgewogen / fordernd; Ton: knapp / erklärend | Formulierung, Progressionstempo |
| Gesundheitsfragebogen | Kurzfragen in Anlehnung an PAR-Q+ (Herzbeschwerden, Brustschmerz bei Belastung, Schwindel, ärztliches Bewegungsverbot) | bei „ja“: Hinweis auf ärztliche Rücksprache, Plan nur leichte Intensität bis zur Bestätigung |

Der PAR-Q+-Wortlaut ist urheberrechtlich geschützt und wird **nicht** übernommen; eigene Fragen mit gleichem Zweck.

---

## 3. Tagesplanung

Fünf Bausteine pro Tag, jeweils optional; der Nutzer wählt, welche er sehen will.

| Baustein | Dauer | Inhalt | Regel |
|---|---|---|---|
| Morning Activation | 3–8 min | Mobilität, Aktivierung, Atemübung | immer leicht (RPE ≤ 3) |
| Main Workout | 15–90 min | Haupteinheit nach Wochenplan | Intensität aus Readiness §6 |
| Movement Snacks | 1–3 min, 2–4 × | Kniebeugen, Treppen, Dehnen | ausgelöst durch Inaktivität > 60 min (Schritte aus Health), nur innerhalb Wachzeit |
| Recovery Session | 5–20 min | Mobilität, lockeres Gehen, Dehnen | an Ruhetagen und nach harten Einheiten |
| Evening Review | 1–2 min | Erledigt? RPE (CR-10), Stimmung, Schmerzen, Notiz | Eingabe für Anpassung und Belastung |

---

## 4. Sportarten und Trainingsmodelle

| Sportart | Modell | Belastungsmaß | Progression |
|---|---|---|---|
| Krafttraining | Ganzkörper (Einsteiger) → Ober-/Unterkörper (trainiert); 1–4 Sätze, 6–15 Wdh. | Sätze × RIR, sRPE | doppelte Progression (erst Wdh., dann Gewicht), RIR 1–3 |
| Bodyweight | Bewegungsmuster: Drücken, Ziehen, Kniebeuge, Hüftbeugung, Rumpf | Wdh., Varianten-Stufe | Stufenleiter je Muster (z. B. Wand- → Knie- → Liegestütz) |
| Laufen | Zonen nach Herzfrequenzreserve oder RPE; 80/20 locker/intensiv | Dauer × RPE, Distanz | Wochenumfang moderat steigern, jede 4. Woche Entlastung |
| Radfahren | wie Laufen, Zonen nach Puls/RPE | Dauer × RPE | wie Laufen |
| Wandern | Dauer, Höhenmeter (`elevationGain`) | Dauer × RPE | Dauer, dann Höhenmeter |
| Rudern | Technik → Intervalle | Dauer × RPE | Intervalllänge |
| Fußball | Spiel/Training als Ereignis + Prävention (Sprungkraft, Adduktoren, Nordic Hamstrings) | sRPE | Präventionsprogramm 2 × / Woche |
| Reiten | Reiteinheit als Ereignis; Ergänzung Rumpf, Hüftmobilität, Gleichgewicht | sRPE | Ergänzungsprogramm |
| Mobilität | Gelenkregionen, Haltezeiten | Minuten | Umfang |
| Allgemeines Ausdauertraining | Gehen, Crosstrainer, Schwimmen | Dauer × RPE | Dauer |

Pulszonen: Standard nach RPE; Herzfrequenzzonen nur, wenn eine verlässliche Pulsquelle im Training vorhanden ist
(Ring-Livepuls ist noch nicht belegt, `STATUS.md`). Maximalpuls geschätzt (z. B. Tanaka 208 − 0,7 × Alter) und als **Schätzung** gekennzeichnet;
Nutzer kann einen gemessenen Wert eintragen.

---

## 5. Übungsbibliothek

### 5.1 Datenmodell `Exercise`

| Feld | Pflicht | Bemerkung |
|---|---|---|
| id, Name (de), Name (en) | ja | |
| Beschreibung, Ausführungsschritte | ja | deutsch; eigene Texte oder lizenzkonform übernommen |
| Muskelgruppen primär/sekundär | ja | |
| Bewegungsmuster | ja | drücken, ziehen, Kniebeuge, Hüftbeugung, Ausfallschritt, Rumpf, Ausdauer, Mobilität |
| Schwierigkeit 1–5 | ja | |
| Ausrüstung | ja | |
| Dauer oder Sätze/Wdh./Pause (Standard) | ja | |
| Alternativen (leichter/schwerer/ohne Gerät) | ja | ids |
| Kontraindikationen | ja | Körperregionen → Ausschluss bei Einschränkung |
| Sicherheitshinweise | ja | |
| Medien | nein | Bild/Animation mit **Lizenz, Urheber, Quelle** je Datei |
| Herkunft + Lizenz des Eintrags | ja | z. B. `wger`, `CC-BY-SA-4.0`, Autorenliste |

### 5.2 Quellen

| Quelle | Inhalt | Lizenz | Entscheidung |
|---|---|---|---|
| **wger** öffentliche REST-API (`https://wger.de/api/v2/exerciseinfo/`, lesend ohne Anmeldung) | mehrere hundert Übungen, Muskeln, Ausrüstung, Bilder, mehrsprachig inkl. Deutsch | Code: AGPL-3.0 (**nicht übernehmen**). Übungsdaten: Creative Commons, laut Projekt-README je Eintrag angegeben, überwiegend CC-BY-SA (4.0); Bilder mit eigenen Lizenzangaben | **Daten adaptieren:** einmaliger Import als gebündelte JSON-Datei mit Lizenz/Autor je Eintrag; Anzeige der Namensnennung in der App („Quelle: wger.de, Autor, Lizenz“). Share-Alike: die abgeleitete Übungsdatei bleibt unter CC-BY-SA und liegt getrennt vom App-Code. Feldnamen und Lizenzfelder **am Live-Endpunkt prüfen**, bevor der Import gebaut wird (Doku war aus der Cloud nicht erreichbar). |
| open-coach (MIT, SwiftUI/SwiftData) | Wochenanpassung, Regel-Rückfall ohne KI, Ersatzübungen | MIT | **adaptieren** laut Audit; aber **keine Ersatzwerte** (open-coach setzt fehlendes RPE = 5 → bei uns bleibt es „fehlt“) |
| ZeroCoach | Übungsdaten aus RepDB | RepDB-Datenlizenz, kommerziell kostenpflichtig | **verwerfen**; nur das Muster „schreibende KI-Werkzeuge nur nach Bestätigung“ übernommen (§6.4) |
| Eigene Einträge | Reiten-Ergänzung, Fußball-Prävention, Atem- und Mobilitätsübungen | eigen | neu schreiben, fachlich geprüft durch Perspektive E |

Kosten: 0 €. Kein Laufzeitzugriff auf wger nötig (Snapshot im Bundle, Aktualisierung per App-Update).
Medien: anfangs nur wger-Bilder mit Lizenz; Animationen später (eigene SF-Symbol-/Lottie-freie SwiftUI-Animationen, keine zugekauften Assets ohne `docs/ASSETS.md`-Eintrag).

---

## 6. Adaptive Planung (Trainings-Engine)

### 6.1 Belastung

- **Session-RPE-Last** = Dauer (min) × RPE (CR-10, Evening Review). Etabliertes, gerätefreies Maß.
- Wochenlast, 4-Wochen-Mittel, Monotonie (Mittel/Standardabweichung der Tageslasten) als Hinweise.
- Kein ACWR als harte Regel (wissenschaftlich umstritten); nur als Hintergrundkennzahl.

### 6.2 Erholungssignale (keine Gesamtpunktzahl)

Je Signal Abweichung vom persönlichen 30-Tage-Band (Release 2):

| Signal | „auffällig“ wenn | Quelle |
|---|---|---|
| Ruhepuls | über Band (p75 + 0,5 × IQR) an ≥ 2 Tagen | Health / Ring |
| HRV (SDNN, nur gleiche Methode vergleichen) | unter Band an ≥ 2 Tagen | Health (Ring-HRV unbelegt) |
| Schlafdauer | < Basislinie − 1 h in 2 von 3 Nächten | Health / Ring |
| Subjektiv | Muskelkater ≥ 7/10, Schmerz, „fühle mich krank“ | Evening Review / Chat |

Regeln (Beispiele, vollständige Tabelle in `CoachRules.swift` mit Tests):
- 0 Signale → Plan wie vorgesehen.
- 1 Signal → Intensität eine Stufe niedriger anbieten, Nutzer entscheidet.
- ≥ 2 Signale → Hauptaktivität als „locker“ oder Recovery vorschlagen.
- „Krank“ / Fieber / Brustschmerz → kein Training, Hinweis; bei Brustschmerz, Atemnot, Ohnmacht: sofort ärztliche Hilfe (Notruf 112).
- Zu wenig Daten (Abdeckung < 50 % im Band) → Signal „unbekannt“, nicht „gut“.

Texte beschreiben („dein Ruhepuls liegt seit zwei Tagen über deinem üblichen Bereich“), keine physiologische Ursache, keine Diagnose.

### 6.3 Mehrwöchige Programme

Mesozyklus 4 Wochen (3 Aufbau + 1 Entlastung mit ca. −30–40 % Umfang). Progression je Modell §4.
**Harte Grenzen der Engine** (Claude kann sie nicht überschreiben):
- Wochenlast höchstens +10 % gegenüber dem 4-Wochen-Mittel (Einsteiger: +5 %), Ausnahme nach Entlastungswoche.
- Max. 2 harte Einheiten (RPE ≥ 7) in Folge; mindestens 1 Ruhetag pro Woche.
- Ausgeschlossene Übungen bei Einschränkungen und ärztlichen Grenzen (Release 7: z. B. „max. Puls 140“ → nur RPE ≤ 5 bzw. Zonen darunter).
- Zeitbudget des Tages wird nie überschritten.

### 6.4 Interaktion

| Nutzer sagt | Intent | Engine-Aktion | gespeichert als |
|---|---|---|---|
| „Heute habe ich nur 15 Minuten.“ | `time_limit(15)` | Haupteinheit auf Kernübungen kürzen, Intensität gleich | `PlanRevision` |
| „Ich möchte lieber Rad fahren.“ | `swap_activity(cycling)` | gleichwertige Last in Radfahren | `PlanRevision` + Präferenzsignal |
| „Die Übung ist zu schwer.“ | `adjust_difficulty(exercise, −1)` | leichtere Alternative, Progressionsstufe −1 | `PlanRevision` + Feedback |
| „Ich habe Muskelkater.“ | `soreness(region, level)` | Region entlasten, Recovery anbieten | Subjektivsignal |
| „Plane mir nächste Woche drei Trainingstage.“ | `plan_week(days: 3)` | Wochenplan neu verteilen | neuer Wochenplan |

Intent-Erkennung: mit Claude über Werkzeug `propose_plan_change` (strict JSON, Enum der Intents); ohne Schlüssel feste Knöpfe für dieselben Intents.
Jede Änderung zeigt **vorher/nachher** und wird erst nach Bestätigung gespeichert. Verlauf aller Revisionen mit Grund.

### 6.5 Benachrichtigungen

Lokal (`UNUserNotificationCenter`), kein Server. Morgens Tagesplan, Erinnerung Haupteinheit, Movement Snacks, Abendrückblick.
Ruhezeiten (Vorgabe 21–7 Uhr), Tageslimit 4, jede Art einzeln abschaltbar. Keine „zeitkritischen“ Mitteilungen.

### 6.6 Apple Health

Release 4 liest `HKWorkout` (Typ, Dauer, Energie, Distanz, Puls). Schreiben von Workouts aus dem Coach erst nach eigener Entscheidung (DECISIONS), weil es Daten anderer Apps beeinflusst.

---

## 7. Unified Daily Coach (Release 6)

### 7.1 Gemeinsamer Kontext statt drei Chatbots

`DailyCoachContext` (Erweiterung von `HealthAnalysisContext`, eigene Version) mit: Schlaf letzte Nacht + 7-Tage-Trend, Aktivität,
Trainingslast und Plan, Erholungssignale §6.2, Ernährung heute/7 Tage (Release 5), Ziele, verfügbare Zeit, Einschränkungen, Coach Memory §7.3.
**Ein** Systemprompt, **ein** Gesprächsverlauf, Werkzeuge aus Intelligence (§5 dort), Coach (`propose_plan_change`) und Nutrition (`propose_meal_change`).

### 7.2 Tagesablauf

| Zeit | Inhalt | lokal / Claude |
|---|---|---|
| Morgens | Tagesüberblick, Schlafrückblick (beschreibend), Aktivierung, Trainingsvorschlag aus Engine | Engine + Claude-Formulierung (optional) |
| Mittags | optionaler Ernährungshinweis (Protein/Trinken relativ zum Ziel), Movement Snack | lokal |
| Nachmittags | Haupteinheit, Alternative oder Regeneration | Engine |
| Abends | Rückblick Bewegung, Ernährung, Erholung; Evening Review | lokal + optional Claude |

Kosten R6: Morgen- und Abendtext mit Sonnet 5.5 (2 $ / 10 $): ca. 5k ein / 1k aus ≈ 0,02 $ je Text → ca. **1,20 $/Monat**; mit Opus 5.5 ca. 2,40 $. Monats-/Jahresbericht kombiniert siehe `CLAUDE-INTELLIGENCE-SPEC.md` §4.

### 7.3 Coach Memory

| Kategorie | Beispiel | Herkunft |
|---|---|---|
| Langfristige Ziele | „Halbmarathon Herbst 2027“ | Nutzer |
| Sportvorlieben | „lieber draußen als Studio“ | Nutzer / bestätigte Beobachtung |
| Trainingsfortschritte | „Liegestütz-Stufe 4 seit 12.03.“ | Engine (automatisch, Fakt) |
| Ernährungspräferenzen | „vegetarisch unter der Woche“ | Nutzer |
| Wiederkehrende Hindernisse | „mittwochs keine Zeit“ | bestätigte Beobachtung |
| Nutzerfeedback | „Burpees nie wieder“ | Nutzer |
| Kommunikationsstil | „knapp, ohne Emojis“ | Nutzer |

Regeln: Claude darf Erinnerungen nur **vorschlagen** (Werkzeug `propose_memory`); gespeichert wird erst nach Bestätigung.
Jeder Eintrag: Text, Kategorie, Herkunft, Datum, letzte Nutzung. Ansicht „Was der Coach über mich weiß“ mit Bearbeiten und Löschen (einzeln und alles).
Keine Diagnosen oder Medikamente im Coach Memory (gehören in den klinischen Kontext, Release 7). Memory wird nur mit Freigabe „Ziele & Vorlieben“ an Claude gesendet.

### 7.4 Beispiel vorsichtige Anpassung

Daten: 3 Nächte < Basislinie − 1 h, zwei intensive Einheiten mit RPE 9 bei Ziel 7. Engine: Signal Schlaf + Subjektiv → Intensität −1 Stufe.
Claude-Text (erlaubt): „Du hast drei Nächte kürzer geschlafen als üblich, und die letzten harten Einheiten waren anstrengender als geplant. Ich schlage heute eine lockere Einheit vor.“
Nicht erlaubt: „Dein Schlafmangel zeigt eine Überlastung deines Nervensystems.“ (Ursache, nicht belegt) → `SafetyRules` verwerfen.

---

## 8. Arbeitspakete

| PR | Inhalt | Abnahme |
|---|---|---|
| R4-1 | `Coach`-Kernmodelle (Plan, Einheit, Übung, Revision), Engine-Regeln §6.3 mit Tests | CI |
| R4-2 | wger-Import-Skript (einmalig, außerhalb der App), Übungs-JSON mit Lizenzfeldern, Bibliotheks-Screen mit Namensnennung | Stichprobe 20 Übungen, Lizenzen korrekt |
| R4-3 | Onboarding Coach (§2) | Screenshots |
| R4-4 | Tagesplan + Evening Review + sRPE | 7 Tage Nutzung durch Johannes |
| R4-5 | Workout-Import aus Health | iPhone |
| R4-6 | Erholungssignale + Anpassung | Unit-Szenarien + iPhone |
| R4-7 | Interaktion (Knöpfe, dann Claude-Intents) | 5 Beispielsätze der Directive |
| R4-8 | Mehrwöchige Programme, Benachrichtigungen | **Abnahme R4: vollständiger Tages- und Wochenablauf** |
| R6-1 | `DailyCoachContext`, gemeinsamer Verlauf | |
| R6-2 | Coach Memory mit Ansicht/Löschen | |
| R6-3 | kombinierte Monats-/Jahresberichte | **Abnahme R6: ein durchgängiger Begleiter über 2 Wochen** |

## 9. Risiken

| Risiko | Gegenmaßnahme |
|---|---|
| Überlastung durch Plan | harte Engine-Grenzen, Entlastungswochen, Schmerz-Abfrage |
| Falsche Erholungsdeutung bei dünnen Ringdaten | Signal „unbekannt“ statt „gut“, Abdeckung sichtbar |
| Lizenzverstoß bei Übungsbildern | Lizenz/Autor je Datei Pflichtfeld, Import bricht bei fehlender Lizenz ab |
| Coach wirkt wie Medizinprodukt | nur allgemeine Bewegungsempfehlungen; ärztliche Grenzen werden übernommen, nie erzeugt (`CLINICAL-CONTEXT-SPEC.md`) |
