# DESIGN SYSTEM 5.0 – Premium User Experience (Master Directive 5.0, Teil X, Release 8 + laufend ab Release 1)

Stand: 2026-11-20 · Status aller Punkte: **Geplant** (§14), außer wo „vorhanden“ steht · Verfasser: Claude Code
Perspektiven: H (Product Designer & 3D Experience Director), A (iOS-Architektur), J (QA, Accessibility).
Studio-Standards gelten vorrangig: `studio-premium-ui`, `studio-motion`, `studio-haptics`, `studio-sound`, `studio-graphics-3d`, `studio-visual-qa`.
Informationsarchitektur und Release-Reihenfolge werden in `PRODUCT-ARCHITECTURE-5.0.md` (anderer Thread) entschieden; dieses Dokument definiert Tokens, Komponenten und Regeln.

> Grundsatz (Directive + Expertenrat H): **Keine grafischen Effekte als Ersatz für fehlende Funktion.** Jede Karte zeigt echte Werte
> oder einen ehrlichen Leerzustand. 3D nur dort, wo es an echte Daten gebunden ist. Keine Ampelfarben, keine Wertungen wie „schlecht“.

---

## 1. Bestand im Code

| Vorhanden | Datei | Bewertung |
|---|---|---|
| Farben Obsidian, Bio Cyan, Neural Violet, Pulse Coral, Ice White + Flächen | `Sources/DesignSystem/Palette.swift` | gute Basis; nur Rohfarben, keine semantischen Rollen |
| Typo-Skala auf Text-Styles (Dynamic Type), SF Rounded, `monospacedDigit` für Werte | `Sources/DesignSystem/Typography.swift` | behalten |
| `Spacing` (4–32), `Radius.medium` 20 | `Typography.swift` | ausbauen |
| `PrimaryButtonStyle`, `SecondaryButtonStyle`, `Card` (opak, Kontrast unabhängig vom Hintergrund) | `Typography.swift` | behalten, in eigene Dateien |
| `PulseOrb`, Heart Chamber (RealityKit, prozedurales Herz), `HeartFeedback` (CoreHaptics + AVAudioEngine) | `Features/Connect/PulseOrb.swift`, `Features/HeartChamber/*`, `Services/HeartFeedback.swift` | Prototyp; siehe §8 |
| Nur dunkel, Screenshot-Matrix dunkel × Dynamic Type | DECISIONS 2026-11-20 | Light („Clinical Light“) folgt mit Token-Umbau §3 |

## 2. Informationsarchitektur (Vorschlag zur Abstimmung)

Directive 5.0 nennt 7 Bereiche; die iPhone-Tableiste zeigt sinnvoll höchstens 5 (ab dem 6. entsteht „Mehr“).

| Bereich | Ort | Begründung |
|---|---|---|
| TODAY | Tab 1 (Start) | Tageszentrale |
| HEALTH | Tab 2 | Messwerte, Trends, Quellen, Langzeit |
| INTELLIGENCE | Tab 3 | Analysen, Berichte, Gespräch |
| COACH | Tab 4 | Plan, Programme, Übungen |
| NUTRITION | Tab 5 | Tagebuch, Mahlzeiten, Rezepte |
| BODY | Vollbild aus TODAY (Heart-Kachel) und HEALTH (Herz-Detail) | Erlebnisbereich, kein täglicher Arbeitsort |
| DEVICES & SETTINGS | Profil-Knopf oben rechts in jedem Tab (Sheet) | Konfiguration, selten genutzt |

`TabView` mit `Tab(…)`-API (iOS 18), Zustand je Tab erhalten, Deep Links für Belegsprünge (`pulseone://health/metric/resting_heart_rate?from=…&to=…`).
Hinweis: Der Expertenrat nannte TODAY / ANALYTICS / INTELLIGENCE / MOVE / BODY / DEVICES. Die Namen der Directive 5.0 haben Vorrang; endgültig in `PRODUCT-ARCHITECTURE-5.0.md`.

## 3. Tokens

### 3.1 Farbrollen (semantisch, neu `Sources/DesignSystem/Theme.swift`)

Views nutzen nur Rollen, nie Rohfarben (Regel aus `Palette.swift` bleibt).

| Rolle | Cinematic Dark (vorhanden) | Clinical Light (neu) | Verwendung |
|---|---|---|---|
| `background` | Obsidian `#070D19` | `#F4F7FA` | Seiten |
| `surface` | `#0F1A2C` | `#FFFFFF` | Karten |
| `surfaceElevated` | `#16243A` | `#EEF3F7` | Sheets, Knöpfe |
| `hairline` | `#23344F` | `#D5DEE7` | Ränder |
| `ink` / `inkMuted` | `#E6F4FA` / `#BACCDA` | `#0B1424` / `#4A5A6E` | Text |
| `accent` | Bio Cyan `#15D9F3` | `#0A8FA3` | Aktionen, eigene Daten |
| `intelligence` | Neural Violet `#9B70FF` | `#6B45D6` | alles von Claude |
| `heart` | Pulse Coral `#FF644F` | `#D9472F` | Puls, Herz |
| `band` | Accent 18 % Deckkraft | Accent 14 % | persönliches Normalband in Diagrammen |
| `outsideBand` | Neural Violet | Neural Violet dunkel | Werte außerhalb des eigenen Bandes (neutral, **nicht rot**) |

Kontrast: Text ≥ 4,5 : 1, große Zahlen und Symbole ≥ 3 : 1, je Rolle in einem Unit-Test aus den Hexwerten berechnet (WCAG-Formel). Light-Werte oben sind Startwerte und werden per Test geprüft.
Keine Ampel (rot/gelb/grün) für Gesundheitswerte. Warnungen der App (z. B. Bluetooth aus) nutzen Symbol + Text, nicht nur Farbe.

### 3.2 Typografie

Bestehende Skala bleibt. Ergänzt: `metricLarge` (Wert auf Karten, `@ScaledMetric` relativ zu `.largeTitle`), `metricUnit` (`.subheadline`), `evidenceChip` (`.caption2`, semibold), `reportBody` (`.body`, Zeilenhöhe +2 pt für lange Berichte).
Zahlen immer `monospacedDigit()`, deutsche Zahlformate über `FormatStyle` (`58 bpm`, `6,1 h`, `94 %`).

### 3.3 Abstand, Form, Höhe

`Spacing` 4/8/12/16/24/32/48; `Radius` small 12, medium 20 (vorhanden), large 28 (Sheets); Karten opak (Kontrast), Glas-Effekte (Liquid Glass, iOS 26) nur für Leisten und nur hinter `if #available(iOS 26, *)`.

## 4. Komponenten (Bibliothek `Sources/DesignSystem/Components/`)

| Komponente | Inhalt | Pflichtzustände |
|---|---|---|
| `MetricCard` | Titel, Wert + Einheit, Zeitpunkt, Quelle (Symbol + Name), Mini-Verlauf 7 Tage, Einordnung zum eigenen Band („im üblichen Bereich“ / „über deinem üblichen Bereich“), „Wie berechnet?“ | geladen · keine Daten („Noch keine Werte von …“) · Basislinie entsteht („noch 9 Tage bis zum persönlichen Bereich“) · Quelle getrennt · Fehler |
| `TrendChart` | Swift Charts: `LineMark`/`BarMark`, Band als `AreaMark`, Auswahl per `chartXSelection`, Zeiträume Tag/Woche/Monat/3 M/Jahr/Alles/frei | Lücken als Lücken (keine Interpolation über fehlende Tage), Audio-Graph/VoiceOver-Beschreibung |
| `QualityBadge` | `valid`, `plausible`, `geschätzt`, `unvollständig`, `Zeit unsicher` (aus `SampleQuality`) | Text + Symbol |
| `SourceLabel` | Ring R03, Apple Health, manuell … + Gerätename | |
| `EvidenceChip` | Fakt-ID → öffnet Beleg-Sheet (Wert, Zeitraum, n, Abdeckung, Quelle, Rechenweg) | |
| `StatementRow` | Aussage mit Typ-Kennzeichen §6 + Beleg-Chips | |
| `SendPreview` | „Diese Daten gehen an Claude“: Kategorien, Zeitraum, Token, Kosten, JSON ansehen | |
| `CostLabel` | geschätzt vorher / tatsächlich nachher, Monatsbudget-Balken | |
| `PlanBlock` | Baustein des Tagesplans (Coach): Dauer, Intensität, Übungen, Erledigt | erledigt · übersprungen · angepasst (mit Grund) |
| `ExerciseCard` | Name, Muskelgruppen, Medien mit Lizenz-/Autorzeile | Medien fehlen |
| `MealRow` / `NutrientBar` | Mahlzeit, Spanne bei Schätzung, `QualityBadge` | geschätzt · bestätigt |
| `EmptyState` | ehrlicher Text + nächster Schritt (Knopf) | |
| `TestBanner` | „Testansicht“ bei `-uiTesting YES` (vorhanden als Muster) | |

## 5. Bildschirmmuster

- **TODAY:** Kopf (Gruß, Datum, Quellenstatus „Ring vor 12 min · Health vor 1 h“), Coach-Block (nächster Baustein), 4–6 `MetricCard`s, Ernährung heute (Spanne), Heart-Kachel → BODY, letzte Analyse.
- **HEALTH:** Liste der Messwertarten mit Abdeckung; Detail mit `TrendChart`, Statistik (Median, Band, n), Quellenvergleich, Rohwerte-Liste, Export.
- **INTELLIGENCE:** Analyse starten (Art, Zeitraum, Vorschau), Berichte (Abschnitte, `StatementRow`), Gespräch, Historie, Kosten.
- **COACH:** Heute, Woche, Programm, Bibliothek, Fortschritt, „Was der Coach über mich weiß“.
- **NUTRITION:** Tagesansicht mit Mahlzeiten, Hinzufügen (Suche/Barcode/Foto/Favorit), Wasser, Ziele, Rezepte, Wochenplan, Einkaufsliste.
- **DEVICES & SETTINGS:** Geräte (vorhanden, `DevicesScreen`), Profile, KI-Anbieter, Datenfreigaben, Datenschutz & Export, Gesundheitsprofil (R7), Darstellung (Profil Dark/Light, Ton, Haptik), Diagnose.

## 6. Aussagetypen sichtbar trennen (Intelligence, Coach)

| Typ | Kennzeichen | Farbe |
|---|---|---|
| Messwert | Symbol `waveform.path.ecg` + „gemessen“ | `accent` |
| Berechnet | `function` + „berechnet“ | `inkMuted` |
| Beobachtung | `eye` + „beobachtet“ | `inkMuted` |
| KI-Deutung | `sparkles` + „Deutung von Claude“ | `intelligence` |
| Empfehlung | `arrow.forward.circle` + „Vorschlag“ | `intelligence` |
| Ärztliche Abklärung | `stethoscope` + Text | `ink` auf `surfaceElevated`, kein Rot |

## 7. Bewegung, Haptik, Ton

- Animationen nach `studio-motion`: Federn (`.spring(duration: 0.35, bounce: 0.2)`) für Zustandswechsel, Zahlen mit `.contentTransition(.numericText())`, Diagramm-Einblendung ≤ 400 ms. **Reduce Motion:** nur Überblendungen, Herzschlag-Animation pausiert, Wert bleibt sichtbar.
- Haptik nach `studio-haptics`: `.sensoryFeedback` für Bestätigen/Erledigt/Auswahl; Herzschlag-Muster nur in BODY und nur bei echtem Live-Puls (CoreHaptics, vorhanden). Abschaltbar.
- Ton nach `studio-sound`: aus per Vorgabe, `.ambient` (Stummschalter wird respektiert, DECISIONS 2026-11-20). In den Einstellungen ein „Ton testen“-Knopf, damit „kein Ton“ als Stummschalter erkennbar ist (Befund F7 in SANIERUNG-4.0).

## 8. Heart Chamber und Living Twin (BODY)

| Anforderung (Directive) | Umsetzung | Abnahme |
|---|---|---|
| Echte Datenbindung | Live-Puls aus `RingStore`; sonst letzter gespeicherter Wert mit Zeitstempel und Hinweis „kein Live-Puls“ | iPhone mit R03 (Release-1-Messkette Voraussetzung) |
| Puls-Historie | `TrendChart` unter dem Herz, 24 h / 7 Tage | |
| Funktionierende Animation | Schlagfrequenz = BPM, „kein EKG“-Kennzeichen bleibt (DECISIONS) | Simulator-Video + iPhone |
| Haptik/Ton | Test-Knopf; Stummschalter-Hinweis | iPhone |
| Anatomisch besseres Modell | lizenziertes USDZ-Modell oder verfeinertes prozedurales Modell; Lizenz vor Commit in `docs/ASSETS.md`. Kostenpflichtiges Modell nur mit Freigabe (Preis nennen) | |
| Messqualität transparent | `QualityBadge` + Quelle + Alter des Werts im Overlay | |
| Living Twin (später) | 3D-Mensch (RealityKit), Körperregionen antippbar → Messwerte/Einschränkungen der Region; Hologramm-Shader nur mit Reduce-Motion-Alternative. Asset-Lizenz Pflicht | eigenes Arbeitspaket nach Release 8-1 |

Metal/Shader nur über SwiftUI `ShaderLibrary` oder RealityKit-Material, nach `studio-graphics-3d`; Leistungsziel 60 fps auf iPhone 16 Pro, gemessen mit `XCTOSSignpostMetric`/`XCTClockMetric` in einem Performance-Test.

## 9. Barrierefreiheit (verbindlich je Komponente)

- Dynamic Type bis AX5 ohne Abschneiden (Screenshot-Matrix XXXL, bestehend).
- VoiceOver: `MetricCard` als ein Element („Ruhepuls 58 Schläge pro Minute, heute 7:12 Uhr, Apple Health, über deinem üblichen Bereich“); Diagramme mit `accessibilityChartDescriptor`.
- `performAccessibilityAudit` auf jedem Screen (bestehender UI-Test, Ausnahmen nur wie in DECISIONS).
- Farbe nie alleiniger Informationsträger (§6 Symbole).
- Light-Profil wird in die Screenshot-Matrix aufgenommen, sobald es existiert (dann 3 Größen × dunkel/hell × Standard/XXXL laut ios-studio-Definition of Done).

## 10. Arbeitspakete

| PR | Inhalt | Abnahme |
|---|---|---|
| D-1 (mit Release 1/2) | `Theme` mit Rollen, Kontrast-Tests, Komponenten `MetricCard`, `QualityBadge`, `SourceLabel`, `EmptyState`, `TrendChart` | Screenshot-Matrix, `studio-visual-qa` |
| D-2 (Release 3) | `EvidenceChip`, `StatementRow`, `SendPreview`, `CostLabel` | |
| D-3 (Release 4/5) | `PlanBlock`, `ExerciseCard`, `MealRow`, `NutrientBar` | |
| D-4 (Release 8) | Clinical Light, Matrix-Erweiterung | Kontrast-Tests grün, Screenshots hell |
| D-5 (Release 8) | Heart Chamber funktional korrigiert (§8), Performance-Test | iPhone |
| D-6 (später) | Living Twin | eigenes Konzept + Asset-Lizenz |

## 11. Risiken

| Risiko | Gegenmaßnahme |
|---|---|
| Schöne Oberfläche ohne Daten (Build-4-Problem) | Pflicht-Leerzustände, keine Beispielwerte außerhalb der Testansicht |
| Klinische Anmutung durch Farben | keine Ampel, neutrale Bandfarbe, beschreibende Texte |
| 3D frisst Akku/Leistung | 3D nur in BODY, Performance-Test, Pause im Hintergrund |
| Lizenzlose Assets | `docs/ASSETS.md` vor Commit |
