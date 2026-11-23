# PULSE ONE – Neubau von Oberfläche, Diagrammen und KI

Stand: 2026-11-23 · Grundlage: Build 17 (main `2c5dae4`), 8 Screenshots von Johannes, Marktvergleich.
Status: **Phase 1 (Analyse und Plan)**. Gebaut wird erst, wenn die ChatGPT-Vorgaben eingearbeitet sind und Johannes „los“ sagt.

---

## 1. Was Johannes nicht passt (Zusammenfassung)

1. **Optik und Bedienung:** statisch, textlastig, wirkt wie eine Liste von Textkarten. Nicht vergleichbar mit Oura, QRing, Whoop.
2. **Keine Bewegung:** Zahlen und Ringe erscheinen einfach, nichts lebt, nichts reagiert auf neue Messungen.
3. **Verlauf unbrauchbar:** Der Tab „Verlauf“ ist eine Liste („62 bpm · 3 Tage mit Daten“). Man sieht nicht, welcher Wert wann gemessen wurde.
4. **Schlaf ohne Phasen:** Es gibt nur „5,8 h“. Kein Hypnogramm mit Leicht-, Tief-, REM- und Wachphasen auf der Uhrzeit-Achse.
5. **KI redet über Lücken statt zu deuten:** Sätze wie „Für deine Basislinie fehlen mir Vergleichswerte“, „kann ich nur als Verlauf lesen“, „Normalbereich gibt der Hersteller nicht her“, „3 von 3 Messsignalen sind noch unbekannt“, „lernt noch (12 Tage)“, „Noch 5 Tage bis zu deinem üblichen Bereich“.
6. **KI-Ton:** zu technisch und zu vorsichtig. Gewünscht: locker, cool, konkret. „So geht's dir heute, so lief dein Tag.“ Nachfragen „warum?“ jederzeit. Auch per Sprache.
7. **Startseite:** Alle Werte sollen als Kacheln frei anordenbar sein.
8. **Anspruch:** mindestens so gut wie die Marktführer, Ziel deutlich besser.
9. **Vorgehen:** kompletter Neubau, alter Code raus, mehrere Teams parallel, ein Koordinator führt zusammen.

## 2. Marktanalyse: Was die Großen zeigen

| | Startseite | Diagramme | Schlaf | KI | Bewegung/Gefühl |
|---|---|---|---|---|---|
| **Oura** (Redesign Okt./Nov. 2025) | Tab „Heute“ mit 3 Scores oben (Schlaf, Erholung, Aktivität) und **einer** Tageserkenntnis („One Big Thing“). Tabs: Heute · Vitals · My Health | Puls-Tageskurve mit Messpunkten, Tag/Woche/Monat/Jahr, persönliches Band | Hypnogramm (Wach/REM/Leicht/Tief über Uhrzeit), Puls- und HRV-Kurve der Nacht darunter, Beiträger mit Balken | „Advisor“: Chat, kennt Schlaf, Aktivität, Mahlzeiten, analytischer Ton, merkt sich Dinge | Ruhig, edle Farbverläufe, Zahlen zählen hoch, Ringe füllen sich |
| **QRing** (Colmi, gleicher Ring) | Kacheln je Wert (Puls, Schlaf, SpO₂, Stress, HRV, Schritte) mit Mini-Diagramm | Tagesdiagramm: **jeder 5-Minuten-Messwert als Balken/Punkt** mit Uhrzeit beim Antippen | Phasenbalken über Uhrzeit, Summen je Phase | keine | einfach, aber zeigt jeden Messpunkt |
| **Whoop** (Home-Redesign 2025, KI 2026) | 3 große Zahlenräder (Schlaf, Erholung, Belastung), Wochenplan, iOS-Widgets | Belastung über den Tag, Wochenvergleich | Phasen, Schlafbedarf, Schlafschuld | „Whoop Coach“ in jeder Ansicht, Gedächtnis, **Spracheingabe**, KI erstellt Trainings | kräftige Farben, Haptik |
| **Ultrahuman** (Update 2026) | „UltraSphere“: Vorschläge statt Diagramme, eigener KI-Tab „Jade“ | Stress-Rhythmus, zirkadianer Rhythmus | Schlaf-Screener + smarter Wecker in einer Ansicht | Jade-Assistent mit eigenem Tab | dynamische Scores, alles auch offline |
| **Garmin Connect** | „Mein Tag“: frei anordenbare Karten, ein-/ausblendbar | Body Battery über den Tag, Puls-Tageskurve, Stress-Balken | Phasen-Zeitachse, Schlaf-Coach | „Active Intelligence“-Kurzsätze | funktional, sehr vollständig |
| **Apple Health / Fitness** | Favoriten anheften, Highlights | Swift-Charts-Stil, Antippen und Wischen zeigt Wert mit Zeit | Phasen-Diagramm (Wach/REM/Kern/Tief) mit Uhrzeit | Highlights als Sätze | Aktivitätsringe mit Feder-Animation, Haptik |

Quellen: [Oura Redesign (TechCrunch)](https://techcrunch.com/2025/10/20/oura-launches-redesigned-app-and-cumulative-stress-feature), [Oura Advisor (Droid Life)](https://www.droid-life.com/2025/11/13/oura-ring-app-gets-big-facelift-ai-gets-more-access-to-your-metrics/), [Whoop Home Screen](https://www.whoop.com/us/en/thelocker/the-all-new-whoop-home-screen/), [Whoop 2026](https://www.whoop.com/es/es/thelocker/2026-whats-new/), [Ultrahuman Emerald](https://www.wareable.com/wearable-tech/ultrahuman-emerald-platform-ai-ultrasphere-app-update). QRing, Garmin und Apple aus deren aktuellen App-Ständen.

**Was alle gemeinsam haben (Pflicht für uns):**
- 3 Haupt-Scores als animierte Ringe oben, darunter **ein** Satz, der den Tag deutet.
- Jeder Wert hat ein **Tagesdiagramm mit echten Messpunkten**, antippen zeigt Wert und Uhrzeit.
- Schlaf = **Hypnogramm** plus Nachtkurven von Puls/HRV/SpO₂.
- Tag/Woche/Monat/Jahr per Wischen, mit persönlichem Band.
- Kacheln/Karten frei anordenbar.

**Wo PULSE ONE besser sein soll (unser Vorsprung):**
1. **KI-Markierungen direkt im Diagramm:** An der Stelle, wo etwas passiert ist (Pulsspitze 14:20, Tiefschlafloch 03:10), sitzt ein Symbol mit Nox' Deutung. Antippen → „Warum?“-Gespräch. Das hat keiner.
2. **Live-Takt:** Kommt ein neuer Messwert vom Ring, „landet“ er sichtbar im Diagramm und in der Kachel (Punkt fliegt ein, Zahl zählt um, kurzer Haptik-Tick). Oura und Whoop aktualisieren nur beim Öffnen.
3. **Nox spricht:** Morgenbericht als Sprachausgabe, Rückfragen per Sprache. Locker, frech, konkret.
4. **Kein Abo, alles auf dem iPhone**, alle Rohpunkte sichtbar (wie QRing) **und** schön (wie Oura).
5. **Querbezüge:** „Dein Puls blieb nach dem Kaffee um 16 Uhr bis Mitternacht 6 Schläge höher, dein Tiefschlaf kam erst um 2.“ Kurven übereinanderlegen (Puls + Stress + Schlaf).

## 3. Befund Build 17: Warum es so aussieht

| Problem | Ursache im Code |
|---|---|
| Kein Hypnogramm möglich | Schlafphasen kommen vom Ring (`BC 27`, `ColmiHistory.swift`), werden aber nur als Text-Zusammenfassung in `rawDataReference` gespeichert (`session.stageSummary`). Es gibt keine Phasen mit Uhrzeit in der Datenbank. |
| Verlauf ist eine Liste | `Features/Health/HealthScreen.swift` listet Messarten; Diagramme (Swift Charts) gibt es nur in 3 Detailansichten, ohne Messpunkt-Auswahl. |
| KI spricht über Lücken | Prompt `CheckInPrompts` (`PulseCore/Companion/CheckIn.swift`): „Bei dünner Datenlage: sag ehrlich, was fehlt“ und „Trenne Messung und Deutung (gemessen: …)“. Dazu `IntelligencePrompts.rules` mit Basislinien-Pflicht. |
| „lernt noch“, „Noch 5 Tage …“ | `DailyScores.swift` (Erholung erst ab 14 Tagen) und `PersonalBaseline.swift` (Band erst ab 7 Tagen). |
| Kacheln = Textkarten | `Features/Today/*`, `DesignSystem/Components.swift`: Zahl + Fließtext, kein Mini-Diagramm, keine Größen, kein Drag & Drop. |
| Keine Bewegung | Im ganzen App-Code nur ~10 Animationsstellen; kein Hochzählen, keine Übergänge zwischen Zeiträumen, keine Live-Updates. |
| Zu viele Bereiche | Begleiter, Sprechstunde, Expertenrunde, Detektiv, Labor, Herz-3D, Ernährung: viele Module nebeneinander, die alle eigenen Text erzeugen. |

Die **Grundlage ist gut und bleibt:** Ring-Protokoll und Verlauf-Abruf (alle Verlaufsarten am R03 bestätigt), 5-Minuten-Puls, Datenbank mit Zeitstempel und Quelle je Messwert, HealthKit-Import, Score-Logik, Coach-Logik, Claude-Anbindung mit Schlüssel im Schlüsselbund, CI-Pipeline.

## 4. Zielbild

### 4.1 Aufbau (Tabs)
**Heute · Verlauf · Nox · Coach**, Profil/Ring oben rechts.
- **Heute:** oben 3 Score-Ringe (Schlaf, Erholung, Aktivität), darunter Nox' Tagessatz (2–3 Sätze, Lautsprecher-Knopf). Darunter **Kacheln** für alle Werte, frei anordenbar.
- **Verlauf:** eine große, interaktive Diagramm-Ansicht je Wert. Oben Wert-Auswahl als wischbare Chips, Zeitraum Tag/Woche/Monat/Jahr. Kein Listenbildschirm mehr.
- **Nox:** ein einziges Gespräch (ersetzt Sprechstunde, Expertenrunde, Detektiv, Berichte). Morgen-, Mittag-, Abendbericht als Nachrichten im Verlauf, „Warum?“ und Spracheingabe.
- **Coach:** Logik bleibt, Optik wird ans neue Design angepasst.

### 4.2 Kachel-Katalog (Startseite)
Größen: klein (1×1), breit (2×1), groß (2×2). Jede Kachel: Wert, Uhrzeit der letzten Messung, **Mini-Diagramm des Tages mit echten Messpunkten**, pulsierender Punkt bei Live-Verbindung. Antippen → Verlauf dieses Werts. Langes Drücken → Bearbeiten (wackeln, ziehen, Größe, ausblenden).

Kacheln: Puls (live), Ruhepuls, HRV, SpO₂, Stress, Schlaf (Mini-Hypnogramm), Schritte (Stundenbalken), Aktive Energie, Erholung, Aktivität, Ring/Akku, Coach heute, Training, Tagesabschluss. Später: Temperatur (R09), Polar H10.

Leere Kachel: zeigt den letzten bekannten Wert mit Datum („gestern 23:10“), **nie** „lernt noch“ oder „keine Daten“.

### 4.3 Diagramme (ein gemeinsamer Baukasten)
- **Tag:** jeder Messpunkt (Puls 5 min, Stress 30 min, HRV, SpO₂, Live-Messungen hervorgehoben) als Punkt/Balken auf der Uhrzeit-Achse. Finger drüberziehen = Wert + Uhrzeit + Quelle (Ring-Verlauf / Live / Apple Health), Haptik-Tick je Punkt. Schlafzeit grau hinterlegt.
- **Woche/Monat/Jahr:** Tageswerte als Balken oder Spanne (min–max), persönliches Band, Trendlinie. Wechsel per Wischen, Balken wachsen animiert in den neuen Zeitraum.
- **Überlagern:** zweiten Wert einblenden (z. B. Puls + Stress, Schlaf + Ruhepuls).
- **Nox-Markierungen:** Symbole an Zeitpunkten mit Deutung; Antippen öffnet Gespräch.
- **Live:** neuer Ringwert erscheint mit Einflug-Animation, Kurve verlängert sich.

### 4.4 Schlaf
- **Hypnogramm:** Wach/REM/Leicht/Tief als Stufenbalken über Uhrzeit (Einschlaf- bis Aufwachzeit), Farbe je Phase, antippen zeigt Phase + Dauer + Uhrzeit.
- Darunter synchron: Puls, HRV, SpO₂ der Nacht auf derselben Zeitachse (Wischen über eine Kurve markiert alle).
- Summen je Phase als Ringsegmente, Schlafscore mit Beiträgern (Dauer, Tiefschlaf, REM, Effizienz, Ruhepuls, Timing).
- Wochenansicht: Schlafenszeiten als Balken über 7 Nächte (wann ins Bett, wann wach).
- Nox-Satz zur Nacht oben.

### 4.5 Bewegung und Stil
- Dunkel, edel, ruhig, aber lebendig: animierter Farbverlauf im Hintergrund (MeshGradient), der die Tagesverfassung spiegelt (Erholung hoch = wärmer/heller).
- Score-Ringe füllen sich beim Öffnen mit Federbewegung, Zahlen zählen hoch (`contentTransition(.numericText)`).
- Übergang Kachel → Detail als fließender Zoom (`matchedTransitionSource` / `navigationTransition(.zoom)`).
- Diagramme bauen sich von links auf, Zeitraumwechsel morpht.
- Haptik bei Scrubbing, Bearbeiten, neuem Messwert. Optional Sound (abschaltbar).
- Reduce Motion: alle Bewegungen auf Überblenden reduziert (Pflicht laut Studio-Standard).
- Feinheiten (Farben, Schrift, Kartenform) kommen aus den ChatGPT-Vorgaben.

### 4.6 KI „Nox“: neue Regeln
1. **Nur deuten, was da ist.** Nie erwähnen, dass etwas fehlt, nicht messbar ist, keine Basislinie hat oder „noch lernt“. Wenn nur ein Wert da ist, wird dieser eine gedeutet.
2. Ohne eigenen Vergleichszeitraum vergleicht Nox mit allgemeinen Erfahrungswerten für Alter/Geschlecht und mit gestern/vorgestern, ohne das anzukündigen.
3. Ton: locker, cool, frech, Du-Form, kurze Sätze, konkrete Uhrzeiten und Zahlen. „So geht's dir heute, so lief dein Tag.“ Keine „gemessen: …“-Aufzählungen, kein Fachjargon, keine Floskeln.
4. Jede Aussage ist begründbar: Antippen von „Warum?“ zeigt die Werte und Zeitpunkte, auf die sich Nox stützt (im Diagramm markiert).
5. **Bleibt:** deutlicher Hinweis bei gefährlichen Werten (S5/S6, Notruf 112), verordnete Medikamente nie umstellen lassen, Einordnung „passt gut/teilweise/kaum“ statt Prozenten.
6. Sprache: Ausgabe mit der besten deutschen Apple-Stimme auf dem Gerät (kostenlos, offline); Eingabe per Diktat (Apple Speech, auf dem Gerät).
7. Datenschutz unverändert: Zusammenfassungen nur gemäß bestehender Freigabe (3 Checks täglich + Gespräch).

Diese Regeln ersetzen in `CheckInPrompts`, `IntelligencePrompts.rules` und `MorningForecaster` alle Anweisungen zu „ehrlich sagen, was fehlt“. Neuer Eintrag in `DECISIONS.md` (Entscheidung Johannes 2026-11-23). Auch „lernt noch (12 Tage)“ entfällt: Erholung wird ab Tag 1 berechnet (Startwerte aus Erfahrungswerten, wird mit jeder Nacht persönlicher).

## 5. Was weg muss (Löschliste)

| Weg | Umfang (Zeilen) | Ersatz |
|---|---|---|
| Ernährung komplett: `Features/Nutrition`, `PulseCore/Nutrition`, `StoredNutrition` (mit Schema-Migration) | ~2.350 | entfällt (Entscheidung 2026-11-22) |
| Herz-3D: `Features/HeartChamber`, `HeartGeometry.swift` | ~470 | entfällt |
| Labor/Detektiv/Experimente/Biografie/Zwei Gehirne: `LabViews`, `BodyDetective`, `ExperimentLab`, `BodyBiography`, `TwoBrains` | ~1.200 | Nox-Gespräch |
| Sprechstunde + Expertenrunde: `ConsultationView`, `ConferenceView/Runner`, `CompanionConference` | ~1.120 | Nox-Gespräch |
| Nachtforscher, Kleidungsberater: `ResearchNightResearcher`, `ClothingAdvisor` | ~520 | Nox-Morgenbericht |
| Alte Oberfläche: `Features/Today`, `Features/Health`, `Features/Scores` (UI), `Features/Companion` (UI-Teile), `DesignSystem` | ~6.700 | Neubau A–D, F |
| Alte Texte: „lernt noch“, „Noch X Tage bis …“, „N von N Messsignalen unbekannt“ | – | entfällt |

Insgesamt rund **12.000 von ~33.000 Zeilen** App-Code gehen raus. Die zugehörigen UI-Tests und Screenshot-Szenarien werden mit entfernt bzw. neu geschrieben.

**Bleibt (Kern):** `Bluetooth`, `Connect`, `Persistence` (ohne Ernährung), `PulseCore` Ring-Protokoll/Verlauf/Sync, `Scores`-Logik, `Coach`-Logik, `Activation`, Check-in-Motor (`CheckInGate`, `NightAssembler`), `AnthropicClient`, `KeychainStore`, HealthKit-Import, Wecker, CI.

## 6. Arbeitspakete (parallel)

Jedes Paket = eigener Thread, eigener Branch, eigene Dateien (keine Überschneidung). Gemeinsame Schnittstellen legt Paket 0 fest, danach laufen A–F gleichzeitig.

| Paket | Inhalt | Besitzt Dateien | Hängt ab von |
|---|---|---|---|
| **0 Fundament & Aufräumen** (Integrator) | Löschliste umsetzen, neue Tab-Struktur leer, Ordner `Features/Home`, `Features/Trends`, `Features/Sleep`, `Features/Nox`, `DesignKit`; Schnittstellen `MetricSeriesProvider` (Messpunkte je Wert und Zeitraum), `TileKind`, `NoxMarker`; Testdaten-Szenarien | `App/*`, `project.yml`, `PulseSchema`, Workflows | – |
| **A Design-System & Bewegung** | Farben je Messart, Schrift (Zahlen), Karten, animierter Hintergrund, Score-Ringe, Hochzähl-Zahlen, Zoom-Übergänge, Haptik/Sound-Bausteine, Reduce Motion; danach Coach und Profil im neuen Stil | `DesignKit/*`, `Features/Coach` (UI) | 0 |
| **B Startseite mit Kacheln** | Kachel-Katalog, 3 Größen, Mini-Diagramme, Live-Punkt, Bearbeiten (ziehen, Größe, ausblenden), Layout speichern, Nox-Satz oben | `Features/Home/*` | 0, nutzt A + C-Mini-Charts |
| **C Diagramme & Verlauf** | Diagramm-Baukasten (Tag mit Messpunkten, Woche/Monat/Jahr, Scrubbing, Band, Überlagern, Nox-Markierungen, Live-Einflug), Verlauf-Tab | `Features/Trends/*`, `DesignKit/Charts/*` | 0 |
| **D Schlaf** | Hypnogramm, synchrone Nachtkurven, Phasen-Summen, Beiträger, Schlafenszeiten-Woche | `Features/Sleep/*` | 0, E (Phasen-Daten); bis dahin Testdaten |
| **E Datenpipeline Ring** | Schlafphasen mit Uhrzeit speichern (neues Modell, Migration, alte Nächte aus Text nachrechnen), alle Messpunkte mit Zeit+Quelle über `MetricSeriesProvider`, Live-Strom an die UI, „zuletzt gemessen“, Hintergrund-Sync prüfen, Erholung ab Tag 1 | `Bluetooth`, `Connect`, `Persistence`, `PulseCore` (Ring, Scores, Baseline) | 0 |
| **F KI Nox** | Neue Prompts nach 4.6, Nox-Tab (ein Gespräch, „Warum?“, Spracheingabe, Sprachausgabe), Berichte morgens/mittags/abends, Markierungen an C liefern, alte KI-Oberflächen weg | `Features/Nox/*`, `PulseCore/Companion`, `PulseCore/Intelligence` | 0 |
| **G Integration & Abnahme** (Koordinator) | Merge-Reihenfolge, CI, Screenshot-Prüfung aller Bildschirme, Simulator-Video, TestFlight-Build, Testanleitung | – | A–F |

**Merge-Reihenfolge:** 0 → E und A → C → B, D, F → G.

**Abnahme je Paket:** CI grün, Screenshots (3 Größen, große Schrift) geprüft, Reduce Motion geprüft, Szenario mit Testdaten-Banner, keine verbotenen Sätze (automatischer Textwächter in CI: „fehlt“, „Basislinie“, „lernt noch“, „nicht lesen“, „unbekannt“ in KI-Ausgaben und UI-Texten).

**CI-Engpass:** Ein Lauf belegt alle 5 Gratis-Mac-Jobs (~15–20 Min.). Bei 6 parallelen Teams heißt das: jedes Team pusht gebündelt, Branch-Läufe nur per Start auf Anfrage, PulseCore-Logik wird zuerst mit den Linux-Prüfungen getestet. Der Integrator plant die Läufe.

**Ergebnis:** ein TestFlight-Build „Neubau 1“ mit allen Paketen gleichzeitig, kein halbfertiger Zwischenstand auf dem iPhone.

## 7. Grenzen, ehrlich (intern, nicht in der App)

- R03 misst keine Hauttemperatur und keine Atemfrequenz → Erholung wird aus Ruhepuls, HRV, Schlaf und Belastung berechnet. R09 bringt Temperatur, sobald der Realtest den Befehl bestätigt.
- Ring-Verlauf liefert Puls in 5-Minuten-Schritten, Stress in 30 Minuten; dichter wird es nur bei Live-Messungen. Das Diagramm zeigt genau diese echten Punkte.
- Die KI erwähnt Lücken nicht mehr; im Diagramm sieht man sie trotzdem (Lücke in der Kurve), so bleibt es nachvollziehbar.

## 8. Was von ChatGPT kommt und hier einfließt

Siehe `UEBERGABE-CHATGPT.md`. Nach Eingang: Abschnitte 4.1–4.5 und Paket A anpassen, dann Freigabe durch Johannes, dann startet der Koordinator die Threads 0, A–F.
