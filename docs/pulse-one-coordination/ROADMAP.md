# PULSE ONE – Ideen-Roadmap (Auftrag P1-002)

Stand: 2026-11-20. Verantwortlich: Claude Code (Umsetzung und Planung), Leitung: Codex, Entscheidung: Johannes.

Diese Datei führt drei Ideensammlungen zu einer Liste mit stabilen IDs zusammen:

| Kürzel | Quelle | Umfang |
|---|---|---|
| `C01`–`C26` | Codex-Ideenbacklog aus P1-002 (Eigentümer-Sammlung im Codex-Chat), unten in §6 wortgetreu | 26 Ideen |
| `P`, `I`, `L`, `E`, `H`, `X`, `G` + Nummer, `K1`–`K8` | `CREATIVE-LAB-2.md` §3 | 102 Ideen + 8 technische Hebel |
| `CL1-1`–`CL1-20` | `CREATIVE-LAB.md` §4 | 20 Ideen |

Keine Idee wird gestrichen. Jede Quell-ID steht genau einmal in §4 (Abdeckung in §5).

**Spielregeln dieser Roadmap**

- Die A–D-Stufen aus CREATIVE-LAB-2 sind **Recherchehinweise, keine Abnahme**. Eine Studie mit Oura, Fitbit oder Polar ist kein Nachweis für Colmi R03/R09. Deshalb steht in der Spalte „Evidenz“ überall noch „nicht geprüft“, bis jemand die Primärquelle gelesen und die Übertragbarkeit auf R03/R09 bewertet hat.
- Status nach Master-Directive §14: Geplant → Implementiert → Gebaut → Simulator → iPhone → Abgenommen. „Spezifiziert“ heißt: Feature-Card liegt vor, kein Code.
- Prognosen sowie Infekt-, Burnout-, Emotions- und Unverträglichkeitsdeutungen und die R09-Temperatur stehen im **Forschungsbacklog** (`RF-…`), bis Quellen, Hardware und Validierung belegt sind. Kamera-Puls, KI-Ärzterat und Werte wie „80 % Leistung“ werden nirgends als geprüfte Funktion behauptet.
- Kein Cloud-KI-Versand echter Gesundheitsdaten ohne ausdrückliche Freigabe im Moment des Sendens. Erste Ausgaben aller Karten sind lokal und deterministisch.
- Keine Jahres- oder Fünfjahresvergleiche ohne vorhandene Historie. Die App zeigt dann „noch nicht genug Daten“, nie einen erfundenen Wert.

---

## 1. Voraussetzungen zuerst (P1-002 Punkt 4a)

Keine Zusatzfunktion wird gebaut, bevor diese Zeilen mindestens „iPhone“ erreichen. Details und Arbeitspakete: `IMPLEMENTATION-ROADMAP.md` (Release 1, R1-1 bis R1-11).

| Voraussetzung | Stand | Beleg | Was fehlt |
|---|---|---|---|
| Signierte, installierbare iPhone-App | iPhone | TestFlight-Lauf #4 (Commit `ffd33cc`) grün, Johannes hat die App installiert und getestet | Neuer Build mit Diagnose-Export (nach PR #14) |
| Echte R03-Daten | iPhone: Verbindung ja, Pulsmessung **scheitert** | Erster Gerätetest von Johannes (2026-11-20) | Diagnose-Datei vom iPhone (Build aus PR #9 + #14), dann gezielte Korrektur |
| Profilisolation | Simulator (Logik getestet) | PR #6, Tests in `Review32Tests.swift`, CI-Lauf 19 | Mehrere Profile in der Oberfläche; heute ein Eigentümerprofil |
| HealthKit | Gebaut (Lesen von 9 Typen, Knopf „Jetzt synchronisieren“) | PR #4, CI-Lauf 12 | R1-6 in Arbeit: mehr Typen, Trainings, Status je Typ, automatischer Abgleich; danach R1-7 Hintergrund. Am iPhone nicht belegt |
| Fortsetzbares Onboarding | Geplant | – | Ersteinrichtung mit Zwischenstand (R1-8) |
| Lokale Speicherung ohne stillen Verlust | Implementiert (nicht gepusht) | R1-5 | Hinweis-Banner bei Datenbankfehler; geht mit dem nächsten PR in CI |

---

## 2. Nächste drei Feature-Cards (P1-002 Punkte 4b und 5)

Nur spezifiziert. Umsetzung erst, wenn §1 erfüllt ist. Alle drei laufen ohne Claude und ohne Netz.

### FC-1 · Wochenrückblick mit Quellen und Datenlücken (RM-01)

- **Nutzerablauf:** Montags erscheint auf HEUTE eine Karte „Deine Woche“. Antippen öffnet fünf Abschnitte: Schlaf, Ruhepuls, Aktivität, Messungen, Datenlücken. Jede Zahl ist antippbar und zeigt Quelle (Ring, Apple Health), Zeitraum und Anzahl der Werte.
- **Datenbedarf:** Tageswerte der letzten 7 Tage aus `DailySeries`; Vorwoche zum Vergleich; Abdeckung je Tag (Stunden mit Werten).
- **Vorhandene Komponenten:** `StoredSample`, `DailySeries`, `SourcePolicy` (Quellwahl je Messart), Qualitätsstufen (nur gültig/plausibel zählen).
- **Lücken:** Wochenaggregat-Typ in PulseCore; Abdeckungsberechnung je Tag; Karte auf HEUTE (Tab-Struktur kommt mit R1-8); Text-Bausteine.
- **Abnahmekriterien:**
  1. Jede angezeigte Zahl lässt sich auf Quelle, Zeitraum und Wertanzahl zurückführen (Test: jede Zahl hat eine Beleg-ID).
  2. Tage ohne Daten erscheinen als Lücke mit Grund („Ring nicht getragen“, „kein Abgleich“), nie als 0.
  3. Weniger als 4 Tage mit Daten: statt Vergleich der Satz „Für einen Vergleich fehlen noch Daten“.
  4. Texte beschreiben, ohne Diagnose oder Ampel (Wortliste-Test).
  5. Swift-Testing-Fälle mit festen Datensätzen (volle Woche, Woche mit Lücken, leere Woche, Quellwechsel).

### FC-2 · Zeitvergleich nur für vorhandene Historie (RM-03)

- **Nutzerablauf:** In jedem Diagramm gibt es „Vergleichen mit …“. Angeboten werden nur Zeiträume, für die Daten existieren: Vorwoche, Vormonat, gleicher Zeitraum vor 1 Jahr. Fehlt ein Zeitraum, steht dort, ab welchem Datum er möglich wird.
- **Datenbedarf:** Tageswerte des aktuellen und des Vergleichszeitraums; Abdeckung beider Zeiträume.
- **Vorhandene Komponenten:** `DailySeries`, Normalband/Baseline-Konzept aus `HEALTH-DATA-SPEC.md` (Median + MAD), Swift-Charts-Ansicht aus R1-9.
- **Lücken:** Verfügbarkeitsprüfung je Zeitraum; Mindestabdeckung (Vorschlag: 60 % der Tage in beiden Zeiträumen); überlagerte Darstellung.
- **Abnahmekriterien:**
  1. Ein Vergleichszeitraum ohne ausreichende Daten wird nicht angeboten (Test mit 10 Tagen Historie: kein Monats- oder Jahresvergleich).
  2. Unterschiede werden mit beiden Mittelwerten und der Wertanzahl gezeigt, nicht als Prozent-Urteil.
  3. Datenquelle beider Zeiträume ist sichtbar; Quellwechsel (z. B. Health → Ring) wird markiert.
  4. Kein Jahres- oder Fünfjahreswert ohne echte Daten aus diesem Zeitraum (Test).

### FC-3 · Eigener Schlaf-Tipp am Abend mit Abgleich (RM-04)

- **Nutzerablauf:** Abends (Zeit wählbar) fragt die App: „Wie wirst du heute schlafen?“ mit drei Antworten (besser, wie immer, schlechter) und optional geschätzter Schlafdauer. Am Morgen: „Wie hast du geschlafen?“ (gleiche Skala). Danach zeigt die Karte Tipp, Selbstbericht und, falls vorhanden, Ringwerte (Schlafdauer, Nachtpuls) nebeneinander. Die App gibt **keine** eigene Prognose ab.
- **Datenbedarf:** zwei Selbstauskünfte pro Nacht (neuer Eintragstyp); Schlafdauer und Nachtpuls aus Ring oder Health, wenn vorhanden.
- **Vorhandene Komponenten:** `StoredSample` für Sensorwerte, Schlafimport aus Health (R1-6), Ring-Schlaf erst mit R2 (Big-Data-Protokoll 0x27, am R03 ungeprüft).
- **Lücken:** Datentyp „Selbstauskunft“ mit Zeitstempel und Profil (Kontextereignis, siehe CREATIVE-LAB §6 `ContextEvent`); lokale Benachrichtigung; Trefferstatistik nach 14 Nächten.
- **Abnahmekriterien:**
  1. Tipp und Selbstbericht werden lokal gespeichert, profilgebunden, mit Zeitstempel und Zeitzone.
  2. Fehlen Sensorwerte, zeigt die Karte das ausdrücklich; nichts wird geschätzt.
  3. Trefferquote erst ab 14 Nächten mit beiden Einträgen, als einfache Zählung („9 von 14 Nächten richtig eingeschätzt“).
  4. Keine Aussage über Ursachen; keine Empfehlung mit Gesundheitsbezug.
  5. Benachrichtigung lässt sich abschalten; ohne Antwort passiert nichts.

---

## 3. Reihenfolge danach

1. **Release 1** (laufend): §1 vollständig auf „iPhone“.
2. **Release 2 Health Analytics:** FC-1, FC-2, FC-3 bauen; Kontextereignisse/Notizen (RM-05) als gemeinsame Grundlage; Ring-Historie (Schlaf, SpO₂, HRV) nach Protokolltest.
3. **Danach, je nach Entscheidung von Johannes:** Hypothesen (RM-06), Selbstversuche (RM-07), Coach (RM-11). Live-Funktionen (RM-12, RM-13) erst nach belegter Messqualität und stabiler Verbindung.
4. **Forschungsbacklog (RF-…):** eigener Bereich mit Quellenprüfung und Validierungsplan, getrennt von Produktfunktionen.

---

## 4. Zusammengeführte Liste

Spalten: **Evidenz** = Stand der wissenschaftlichen Prüfung; **Hardware** = was nötig ist; **Implementierung** = Status §14; **Tests** = was die Abnahme braucht; **Ab** = frühestes Release laut `IMPLEMENTATION-ROADMAP.md`.

### 4.1 Produkt-Spur

| ID | Thema | Codex | CREATIVE-LAB-2 | CREATIVE-LAB | Evidenz | Hardware | Implementierung | Tests | Hängt ab von | Ab |
|---|---|---|---|---|---|---|---|---|---|---|
| RM-01 | Wochenrückblick mit Quellen und Lücken; Erzählung aus Sicht des Herzens nur als getrennte, gekennzeichnete Ebene | C08 | – | CL1-12 (Monatsbrief) | beschreibend, keine Studie nötig | R03 oder Health | Spezifiziert (FC-1) | FC-1 §Abnahme | §1, R1-9 | R2 |
| RM-02 | Jahresrückblick, Jahres-Chronik, Körperkalender-Heatmap, Nacht-Kunst | C09 | I9, I12, X6, G22 | CL1-12 | beschreibend | R03 oder Health | Geplant | Datenabdeckung sichtbar; nur vorhandene Monate | RM-01, ≥ 12 Monate Daten | R3+ |
| RM-03 | Zeitvergleich, Zeitkapsel, Brief an dein Ich, Saisonvergleich | C10 | L9, P11 | – | beschreibend; P11 (Saison) nicht geprüft | R03 oder Health | Spezifiziert (FC-2) | FC-2 §Abnahme | §1, R1-9 | R2 |
| RM-04 | Eigener Schlaf-Tipp mit Abgleich; Prognose-Turnier; Schlafrezept | C26 | P17, X5, L4 | – | Selbstbericht-Vergleich ohne Studie; Turnier mit App-Modell gehört zu RF-07 | Health-Schlaf oder R03-Schlaf | Spezifiziert (FC-3, nur Selbsttipp) | FC-3 §Abnahme | RM-05 (Selbstauskunft) | R2 |
| RM-05 | Notizen und Kontextereignisse (Sprachnotiz lokal, Stalltagebuch, behutsames Nachfragen bei Lebensereignissen) | – | H5, G11 | CL1-4 | G11 nicht geprüft | iPhone | Geplant (`ContextEvent`, CREATIVE-LAB §6) | lokale Spracherkennung, Audio gelöscht | §1 | R2 |
| RM-06 | Hypothesen und Zusammenhänge: Analogtage, Signaturen, Körper-Wörterbuch, Frag & Zeig, selbstlernende Regeln, Nachtschicht-Forscher, Körperbiografie | C11 | I1, I2, I3, I10, I23, I24 | CL1-2, CL1-5 | nicht geprüft; immer als Frage, nie als Wirkung | R03 oder Health | Geplant | Gegenprobe, Mehrfachvergleich-Korrektur, Beleg-IDs | RM-05, R2-Analytik; I1 braucht Claude-Freigabe | R3 |
| RM-07 | N-of-1-Selbstversuche, placebo-ehrlicher Test, Essensfenster, Kälte/Sauna, Nickerchen, Mondphase als Selbsttest | C12, C13 | L6, E12, G12, G13, G15 | CL1-3 | Methodik (ABAB, Blockebene) nicht geprüft; Verblindbarkeit je Versuch prüfen | R03 | Geplant | vorab festgelegte Zielgröße, Kontrolltage, Blockstatistik lokal | RM-05, RM-06 | R3 |
| RM-08 | Ernährung: Tageskoch, Tellerfoto, Kühlschrank-/Speisekarten-Foto, Wochenplan, Koch-Assistent, Reste, Saisonkalender, Gäste | C14, C15 | E1, E2, E3, E4, E5, E8, E9, E10, E11 | – | Nährwerte nur aus Datenbank (OFF/USDA), nicht aus KI-Schätzung; E4 kleine Studien, nicht geprüft | iPhone | Geplant (`NUTRITION-SPEC.md`) | Allergien explizit erfasst; Nährwert-Herkunft sichtbar | Fotos an Claude nur mit Freigabe | R5 |
| RM-09 | Koffein- und Alkoholfenster, Alkohol-Fingerabdruck, Koffein-Rechner, Kater-Prognose | C17 | I4, I5, P16 | – | I4 Studienhinweis, nicht auf R03 geprüft; keine präzisen Grenzzeiten | R03 | Geplant | Dosis nur aus eigenen Einträgen; Unsicherheit sichtbar | RM-05 | R3 |
| RM-10 | Umwelt: Wetter, Luft, Pollen (Open-Meteo), Zimmerklima, Lärm | C18 | I6, I13, I14 | CL1-16 | Nullbefund möglich; Luftdruck kaum untersucht | Raumsensor optional | Geplant | Mehrfachvergleiche, Quellenangabe Open-Meteo | RM-06 | R2+ |
| RM-11 | Coach und Tagesbegleitung: Trainingsplan, Tagesdrehbuch, Wenn-Dann, Licht, Werte-Kompass, Mikro-Pausen, Saisons, Stoischer Abend, Gesprächs-Timing, Morgen-Podcast, Training-Ernährung | C19 | L1, L3, L5, L7, L8, L10, L11, L12, X1, E6 | CL1-8, CL1-9, CL1-10, CL1-11, CL1-17 | nicht geprüft; Änderungen erklärt und übersteuerbar | R03 | Geplant (`COACH-ENGINE-SPEC.md`) | jede Empfehlung mit Begründung und Abschaltung | RM-05, R2-Analytik | R4/R6 |
| RM-12 | Live-Sprachcoach, Siri, Widgets, Live-Puls auf dem Sperrbildschirm | C20 | X7 | CL1-20 | Messqualität live am R03 unbelegt | R03 (Live), H10 besser | Geplant | Ausfälle, Audio-Unterbrechung, Bedienung ohne Hinschauen | belegte Live-Messung (R1-4) | R6/R8 |
| RM-13 | Atem-Biofeedback mit Heart Chamber, Atem-Schrittmacher, Meditation live, Herz-Musik live | C21 | G14, X3 | CL1-15 | Atemführung und gemessener Puls getrennt darstellen | R03; H10 für G14/X3 | Heart Chamber gebaut (Simulator), Puls-Kopplung geplant | Reduce Motion, Haptik aus, kein Puls = klar angezeigt | R1-10, belegte Live-Messung | R4 |
| RM-14 | Pferd und Reiter: Herzkopplung, Gangarten, Ritt-Bericht, Pferde-Fitness, Reiter-Körper, Pferdeform | C22 | H1, H2, H3, H4, H6, P18 | CL1-14 | Gleichlauf und Stressdeutung getrennt validieren | 2× Polar H10 + Equine-Gurt | Geplant | zwei Profile, getrennte Ströme, Zeitabgleich | Profil „Pferd“, H10-Adapter (M7) | R7+ |
| RM-15 | Klang aus Daten, Hör deine Woche | C24 | X4 | CL1-19 | kreativ, keine Gesundheitsaussage | – | Geplant | erklärbare Zuordnung Wert → Klang | RM-01 | R8 |
| RM-16 | KI-Rollen und zweite Meinung (als KI gekennzeichnet, kein ärztlicher Rat) | C25 | I11, G19 | CL1-6 | kein Evidenznachweis durch KI-Rollen | – | Geplant (`CLAUDE-INTELLIGENCE-SPEC.md`) | Kennzeichnung „KI-Rolle“, Zahlen gegen Fakten-IDs geprüft | Claude-Freigabe, R3 | R3+ |
| RM-17 | Digitaler Zwilling, Was-wäre-wenn, Lebenspfade, Zwei Wege, Körperwetter-Landschaft, Zukunfts-Ich | C06, C07 | P13, P14, G4, G20, X2, X8 | CL1-13, CL1-18 | Szenarien = Annahmen; Vorhersagemodell gehört zu RF-07 | R03 | Geplant (Darstellung getrennt vom Modell) | Annahmen und Unsicherheit sichtbar | RM-07, ausreichende eigene Daten | R6/R8 |
| RM-18 | Zwei Gehirne (Apple Foundation Models + Claude) und KI-Hebel | – | K1–K8 | CL1-1 | technisch; Apple-KI nur hinter `#available(iOS 26)` | iPhone 16 Pro | Geplant | Vorschau „Das verlässt dein iPhone“, fester Textrückfall | R3 | R3 |
| RM-19 | Foto als Quelle über Mahlzeiten hinaus, Laborbefunde neben Trends | – | G6 | CL1-7 | Zusammenhang ≠ Ursache | iPhone | Geplant | Fotos nur mit Freigabe an Claude | `CLINICAL-CONTEXT-SPEC.md` | R5/R7 |
| RM-20 | Zusatzsensoren: Glukose, aerobe Schwelle, Herzfrequenz-Erholung, Atemfrequenz aus EKG, Partner-Ring | – | I19, I20, I21, I22, G10 | – | jeweils eigene Validierung | CGM, H10, zweiter Ring | Geplant (je Adapter) | Adapter-Test je Gerät | Adapter-Schnittstelle (M7) | R7 |
| RM-21 | Gangbild-Wächter (iPhone-Gangdaten aus Health) | – | I8 | – | nicht geprüft | iPhone | Geplant | Health-Typen Gehtempo/Schrittlänge | R1-6 | R2+ |
| RM-22 | Sich selbst erweiternde App (Feature-Vorschläge aus offenen Fragen) | – | G18 | – | – | – | Geplant | Vorschlag nur nach Bestätigung, keine Gesundheitsdaten im Text | R3 | R3+ |

### 4.2 Forschungs-Spur (keine Produktaussage vor Validierung)

| ID | Thema | Codex | CREATIVE-LAB-2 | Evidenz | Hardware | Validierung nötig | Ab |
|---|---|---|---|---|---|---|---|
| RF-01 | Infekt-Radar, Stimm-Biomarker | C01 | P3, G3 | Studien mit anderen Geräten; Vorlaufzeit 1–3 Tage und Übertragbarkeit auf Colmi nicht geprüft | R09 (Temperatur) nach Realtest | Zielgröße, zeitlich getrennte Prüfung, Fehlalarmrate | offen |
| RF-02 | Tagesform, Leistungsfenster, Energie-Konto | C02 | P6, L2 | nicht geprüft; keine Prozentwerte, keine präzisen Uhrzeiten | R03 | eigene Rückmeldungen als Referenz | offen |
| RF-03 | Stimmung/Energie morgen, Emotionen aus HRV | C03, C23 | P5 | nicht geprüft; keine Emotionsbestimmung aus HRV allein | R03 | Selbsteinschätzung als Referenz | offen |
| RF-04 | Burnout-/Übertrainings-Frühzeichen, Verletzungshinweis | C04 | P4, P15 | nicht geprüft; keine Diagnose | R03 | Langzeitdaten, Trainingslast | offen |
| RF-05 | Eigene Formzyklen | C05 | – | Stabilität vs. Zufall prüfen | R03 | Mindestdauer, Permutationstest | offen |
| RF-06 | Unverträglichkeits-Spur, Mahlzeiten-Antwort, Essens-Reaktionsprofil | C16 | I18, E7 | keine Unverträglichkeit aus Ringwerten | R03, optional CGM | Beschwerden-Einträge als Referenz | offen |
| RF-07 | Prognosen: Morgen, Schlaf heute Nacht, VO₂max-Schätzung, Gewicht, Reise/Jetlag | – | P1, P2, P9, P10, P12 | nicht geprüft | R03, Health | Zielgröße, Vergleichsbasis, Abdeckung, Unsicherheit | offen |
| RF-08 | Körper-Tempo, Langfrist-Spiegel, Gesundheitsspanne, Bevölkerungsvergleich | – | P7, P8, G16, G17 | Studienwerte nicht auf Einzelperson übertragbar ohne Prüfung | R03 | Quellen je Kennzahl | offen |
| RF-09 | Kamera-Puls, Selfie-Puls, Gefäßalter | – | G1, G2, I17 | **kein** verifiziertes Feature | iPhone-Kamera | eigene Validierung gegen Referenzgerät | offen |
| RF-10 | SpO₂-Nachtmuster, Rhythmus-Auffälligkeiten | – | I15, I16 | R03 nur stündlich; Rhythmus nur mit EKG | Fingerclip, H10 | medizinnahe Aussagen nur als „mit Arzt besprechen“ | offen |
| RF-11 | Innere-Uhr-Phase aus Temperatur | – | G5 | R09-Temperatur erst nach Hardware-/Firmwareprüfung | R09 | Realtest R09 | offen |
| RF-12 | Kalender-Stress, Gen-Rohdaten, Musik, Orte, Schlafphasen-Wecker | – | I7, G7, G8, G9, G21 | nicht geprüft; G21 mit Ring fraglich | iPhone | Datenschutz je Quelle, Mehrfachvergleiche | offen |

---

## 5. Abdeckung (jede Quell-ID genau einmal)

- **Codex:** C01 RF-01 · C02 RF-02 · C03 RF-03 · C04 RF-04 · C05 RF-05 · C06 RM-17 · C07 RM-17 · C08 RM-01 · C09 RM-02 · C10 RM-03 · C11 RM-06 · C12 RM-07 · C13 RM-07 · C14 RM-08 · C15 RM-08 · C16 RF-06 · C17 RM-09 · C18 RM-10 · C19 RM-11 · C20 RM-12 · C21 RM-13 · C22 RM-14 · C23 RF-03 · C24 RM-15 · C25 RM-16 · C26 RM-04
- **Prognosen P:** P1 RF-07 · P2 RF-07 · P3 RF-01 · P4 RF-04 · P5 RF-03 · P6 RF-02 · P7 RF-08 · P8 RF-08 · P9 RF-07 · P10 RF-07 · P11 RM-03 · P12 RF-07 · P13 RM-17 · P14 RM-17 · P15 RF-04 · P16 RM-09 · P17 RM-04 · P18 RM-14
- **Deutung I:** I1 RM-06 · I2 RM-06 · I3 RM-06 · I4 RM-09 · I5 RM-09 · I6 RM-10 · I7 RF-12 · I8 RM-21 · I9 RM-02 · I10 RM-06 · I11 RM-16 · I12 RM-02 · I13 RM-10 · I14 RM-10 · I15 RF-10 · I16 RF-10 · I17 RF-09 · I18 RF-06 · I19 RM-20 · I20 RM-20 · I21 RM-20 · I22 RM-20 · I23 RM-06 · I24 RM-06
- **Lebensanleitung L:** L1 RM-11 · L2 RF-02 · L3 RM-11 · L4 RM-04 · L5 RM-11 · L6 RM-07 · L7 RM-11 · L8 RM-11 · L9 RM-03 · L10 RM-11 · L11 RM-11 · L12 RM-11
- **Ernährung E:** E1–E5 RM-08 · E6 RM-11 · E7 RF-06 · E8–E11 RM-08 · E12 RM-07
- **Pferd H:** H1–H4 RM-14 · H5 RM-05 · H6 RM-14
- **Erlebnis X:** X1 RM-11 · X2 RM-17 · X3 RM-13 · X4 RM-15 · X5 RM-04 · X6 RM-02 · X7 RM-12 · X8 RM-17
- **Hebel K:** K1–K8 RM-18
- **Grenzgänger G:** G1 RF-09 · G2 RF-09 · G3 RF-01 · G4 RM-17 · G5 RF-11 · G6 RM-19 · G7 RF-12 · G8 RF-12 · G9 RF-12 · G10 RM-20 · G11 RM-05 · G12 RM-07 · G13 RM-07 · G14 RM-13 · G15 RM-07 · G16 RF-08 · G17 RF-08 · G18 RM-22 · G19 RM-16 · G20 RM-17 · G21 RF-12 · G22 RM-02
- **CREATIVE-LAB 1:** CL1-1 RM-18 · CL1-2 RM-06 · CL1-3 RM-07 · CL1-4 RM-05 · CL1-5 RM-06 · CL1-6 RM-16 · CL1-7 RM-19 · CL1-8 RM-11 · CL1-9 RM-11 · CL1-10 RM-11 · CL1-11 RM-11 · CL1-12 RM-01/RM-02 · CL1-13 RM-17 · CL1-14 RM-14 · CL1-15 RM-13 · CL1-16 RM-10 · CL1-17 RM-11 · CL1-18 RM-17 · CL1-19 RM-15 · CL1-20 RM-12

---

## 6. Codex-Ideenbacklog (wortgetreu übernommen, Stand 20.11.2026)

Quelle: ungefilterte Ideensammlung des Eigentümers im Codex-Chat. Alle 26 Ideen bleiben erhalten. Dies ist kein freigegebener Implementierungsauftrag und kein Wirksamkeitsnachweis. 🧪 übernimmt die experimentelle Kennzeichnung des Eigentümers; auch unmarkierte Ideen können Forschung und Validierung benötigen. Die im Ausgangstext genannten Studien wurden hier noch nicht recherchiert.

| ID | Idee | Inhalt / zu prüfende Frage |
|---|---|---|
| C01 | 🧪 Infekt-Radar | Gemeinsame Abweichungen von Ruhepuls, HRV und Hauttemperatur untersuchen. Behauptete Vorlaufzeit von 1–3 Tagen und Übertragbarkeit von Oura/Fitbit auf Colmi separat recherchieren. |
| C02 | 🧪 Leistungs-Wetterbericht | Tagesform und mögliche Tagesrhythmen aus Schlaf, HRV und eigenen Rückmeldungen untersuchen; keine unbelegten Leistungsprozente oder präzisen Uhrzeiten ausgeben. |
| C03 | 🧪 Stimmung/Energie morgen | Freiwillige Notizen mit späteren Selbsteinschätzungen vergleichen. |
| C04 | 🧪 Burnout-/Übertrainings-Frühzeichen | Langfristige Veränderungen untersuchen; daraus keine Diagnose oder bestätigte Früherkennung ableiten. |
| C05 | 🧪 Eigene Formzyklen | Wochen-/Monatsmuster auf Stabilität und Zufall prüfen. |
| C06 | Digitaler Zwilling | Eigene Daten verständlich erkunden; etwa Schlafenszeit-Szenarien als Annahmen darstellen. Die 3D-Figur und ein wissenschaftliches Vorhersagemodell sind getrennte Funktionen. |
| C07 | Was-wäre-wenn | Regler für Schlaf, Training und Alkohol; Szenarien mit Annahmen, Unsicherheit und ausreichender eigener Datengrundlage. |
| C08 | Körpergeschichte | Wochenrückblick als literarische Erzählung aus Sicht des Herzens; Fakten und erzählerische Ausschmückung trennen. |
| C09 | Jahresrückblick | Persönliche Meilensteine, Nächte, Fortschritte und Datenabdeckung nachvollziehbar zusammenstellen. |
| C10 | Zeitkapsel | Heute mit 1, 3 oder 5 Jahren zuvor vergleichen, sofern entsprechende Daten vorhanden sind. |
| C11 | Automatische Hypothesen | Auffällige Zusammenhänge als Fragen vorschlagen, nicht als bewiesene Wirkungen. |
| C12 | N-of-1 | Freiwillige Selbstversuche mit Kontrolltagen, vorab festgelegten Zielgrößen und nachvollziehbarem Ablauf; Beispiele Kaffee, spätes Essen und Bildschirmzeit. Magnesium/Kälte aus der ursprünglichen Sammlung bleiben als gesondert zu bewertende Vorschläge erhalten. |
| C13 | Placebo-ehrlicher Test | Randomisierte Abläufe und tatsächliche Verblindbarkeit prüfen; eine zufällige Tagesplanung allein ist noch keine Verblindung oder Placebokontrolle. |
| C14 | Tagesgericht | Rezept und Einkaufsliste passend zu selbst gewählten Zielen und Vorlieben; Allergien und Einschränkungen explizit erfassen. |
| C15 | Tellerfoto | Ungefähre Mahlzeitenerfassung mit manueller Korrektur; mögliche Zusammenhänge mit späteren Daten untersuchen. |
| C16 | 🧪 Unverträglichkeits-Spur | Mahlzeiten und eigene Beschwerden/Beobachtungen vergleichen; keine Unverträglichkeit aus Ringwerten diagnostizieren. |
| C17 | Koffein-/Alkoholfenster | Konsumzeit, Schlaf und eigene Reaktionen untersuchen; präzise persönliche Grenzzeiten nicht ohne belastbare Grundlage behaupten. |
| C18 | Wetter/Mond/Luftdruck | Externe Faktoren als explorative Hypothesen prüfen, einschließlich möglichem Nullbefund; Mehrfachvergleiche berücksichtigen. |
| C19 | Adaptiver Trainingsplan | Tagesform, Ziele und Belastung einbeziehen; Änderungen erklären und vom Nutzer übersteuerbar machen. |
| C20 | Live-Sprachcoach | Live-Pulszonen und Training begleiten; Messqualität, Ausfälle, Audio und sichere Bedienbarkeit berücksichtigen. |
| C21 | Atem-Biofeedback | Heart Chamber mit tatsächlichem Puls verbinden; Atemführung und gemessenen Puls getrennt darstellen. |
| C22 | Pferd und Reiter | Zwei getrennte Sensor-/Profilströme zeitlich vergleichen; Gleichlauf und Stressinterpretation getrennt validieren. |
| C23 | 🧪 Emotionen aus HRV | Freiwillige Selbsteinschätzungen/Sprachnotizen als Referenz; keine verlässliche Emotionsbestimmung allein aus HRV behaupten. |
| C24 | Musik aus Daten | Persönliche Daten als Klang/Ambient übersetzen; kreative Sonifikation mit erklärbarer Zuordnung. |
| C25 | KI-Experten-Personas | Unterschiedliche fachliche Perspektiven zur Diskussion; als KI-Rollen kennzeichnen, kein tatsächlicher ärztlicher Expertenrat oder unabhängiger Evidenznachweis. |
| C26 | Vorhersage-Wetten | Eigene Schlafprognose mit späterem Selbstbericht und verfügbaren Messungen vergleichen; Unterschiede sichtbar machen. |

Codex-Anforderungen für spätere Architektur und Abnahme (übernommen): profilgebundene Messdaten mit Herkunft, Qualität, Zeitstempel und Zeitzone; subjektive Einträge und versionierte Auswertungen; Beschreibung, beobachteter Zusammenhang, Szenario und Prognose sichtbar unterscheiden; keine Gleichsetzung von HRV-, Schlaf- oder Temperaturdefinitionen verschiedener Geräte; vor Prognosen Zielgröße, Vergleichsbasis, zeitlich getrennte Validierung, Abdeckung und Unsicherheit festlegen; keine ungefragte externe Verarbeitung von Gesundheitsdaten, Fotos oder Sprachnotizen; Wirksamkeitsaussagen zu Interventionen vorher an Primärquellen prüfen. Erweiterungen erst bei konkretem Auftrag, kein vorsorglicher Großumbau.
