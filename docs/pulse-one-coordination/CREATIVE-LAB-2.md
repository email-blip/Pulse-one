# CREATIVE LAB 2 – Ohne Grenzen: Was eine KI aus deinen Körperdaten herauslesen kann

Stand: 2026-11-20 · Status: **Ideensammlung** (§14: Geplant) · Verfasser: Claude Code
Auftrag Johannes (2026-11-20 22:38): „Verwerfe erstmal nichts … auf wackeligen Füßen möglichst auch Prognosen …
begrenze das Kreativteam nicht … voll austesten … Gerichtsvorschläge … blow my mind.“
Ersetzt die Vorauswahl aus `CREATIVE-LAB.md` (dort verworfene Ideen sind hier wieder drin und neu bewertet). Reine Doku, kein App-Code.

> **Spielregeln dieser Runde (102 Ideen):** Nichts wird vorab gestrichen. Dafür bekommt **jede** Idee ein ehrliches Etikett,
> wie belastbar sie ist. „Wackelig“ ist erlaubt, aber nie getarnt. Das Team besteht aus Perspektiven eines
> einzelnen Agenten (keine echten Fachleute). Studienzahlen stammen aus den Quellen in §9; alles andere ist als Schätzung markiert.

---

## 0. Kurzfassung (für das Handy)

**Belastbarkeits-Etikett für jede Idee**

| Stufe | Bedeutung | So zeigt die App es |
|---|---|---|
| **A – belastbar** | gut untersucht, mit deinen Geräten messbar | normale Aussage |
| **B – ansatzweise** | Studien zeigen Hinweise; bei dir persönlich prüfbar | „Hinweis, wird mit deinen Daten geprüft“ |
| **C – wackelig** | Spekulation mit etwas Grundlage; Ergebnis kann falsch sein | Label „Prognose-Labor: experimentell“ |
| **D – Zukunft** | mit heutigen Geräten nicht messbar, aber mit Zusatzgerät/Rohdaten denkbar | „braucht …“ |

**Die 10 Ideen, die am meisten können (Details §5):**

| # | Idee | Was du im Alltag davon hast | Stufe |
|---|---|---|---|
| 1 | **Nachtschicht-Forscher** | Claude rechnet einmal im Monat mit echtem Python-Code Hunderte Zusammenhänge in deinen (anonymisierten) Daten durch und legt dir die 5 überraschendsten Funde mit Beweisdiagramm hin. | B |
| 2 | **Morgen-Vorhersage** | Abends sagt dir die App, wie dein Ruhepuls und deine Erholung morgen früh voraussichtlich aussehen, und morgens siehst du, ob sie recht hatte. | B |
| 3 | **Persönlicher Wetterbericht des Körpers** | Die App verbindet Wetter, Pollen und Luft mit deinen Nächten und sagt: „Schwüle Nacht angekündigt, bei dir waren solche Nächte meist unruhiger.“ | B |
| 4 | **Infekt-Frühwarnung** | Steigen Ruhepuls und (mit R09) Fingertemperatur über mehrere Nächte, sagt die App: „So sah es bei dir vor deiner letzten Erkältung aus.“ | B |
| 5 | **Tageskoch** | Jeden Tag drei Gerichte, abgestimmt auf deine letzte Nacht, dein Training (z. B. Reiten um 17 Uhr), die Jahreszeit und was im Kühlschrank ist (Foto genügt). | B |
| 6 | **Alkohol- und Koffein-Fingerabdruck** | Du siehst schwarz auf weiß, wie stark ein Glas Wein oder ein später Kaffee deinen Nachtpuls und Schlaf verschiebt, nur bei dir. | A/B |
| 7 | **Körper-Tempo („biologisches Alter“ als Trend)** | Ein spielerischer Wert, ob dein Körper gerade „jünger oder älter läuft“ als dein Kalenderalter, mit klarer Warnung, dass es nur eine Annäherung ist. | C |
| 8 | **Ärzte-Konferenz-Simulation** | Vier KI-Rollen (Herz, Schlaf, Sport, Ernährung) diskutieren deinen Monat und einigen sich auf eine Empfehlung, und du kannst die Diskussion mitlesen. | B |
| 9 | **Morgen-Podcast** | Zwei Minuten gesprochenes Briefing über deine Nacht und deinen Tag, auf dem Weg zum Stall anhörbar. | A |
| 10 | **Reiter-Pferd-Herzkopplung** | Mit einem Pulsgurt am Pferd siehst du nach dem Ritt, wann eure Herzen im Gleichklang waren und wer zuerst angespannt war. | B (braucht H10 + Equine-Gurt) |

**Was heute schon ginge, ohne neue Hardware:** 1, 2, 3, 5, 6, 8, 9 (und 4 schwächer, ohne Temperatur).

**Die mutigsten Grenzgänger (§3.9):** Roh-Pulswelle per Finger auf der iPhone-Kamera (G1), Puls aus dem Selfie-Video (G2), Stimm-Biomarker (G3), Digitaler Zwilling Stunde für Stunde (G4), Laborwerte × Wearables (G6), Orte und Musik, die dich beruhigen (G8, G9), eine App, die sich aus deinen Fragen selbst erweitert (G18).

---

## 1. Das erweiterte Kreativteam (16 Perspektiven)

| Rolle | Beitrag |
|---|---|
| KI-Forscherin | was Claude 2026 kann: Code ausführen, 1-Mio.-Token-Kontext, Gedächtnis, Vision, Werkzeuge |
| Prognostiker / Statistiker | Vorhersagen, Unsicherheit, Fehlalarme, persönliche Modelle |
| Kardiologin | Puls, HRV, Erholung, Rhythmus, Fitness |
| Schlafmediziner | Schlafphasen, SpO₂, Atmung, Regelmäßigkeit |
| Chronobiologin | innere Uhr, Jahreszeiten, Licht, Jetlag |
| Umweltmediziner | Wetter, Hitze, Luftqualität, Pollen, Lärm |
| Psychologe / Psychiater | Stimmung, Stress, Gewohnheiten, Motivation |
| Ernährungswissenschaftlerin + Koch | Gerichte, Timing, Saison, Einkauf |
| Sportwissenschaftler | Belastung, Schwellen, Übertraining |
| Pferdewissenschaftlerin | Pferd als zweites Lebewesen in der App |
| Maker / Hardware-Hacker | Rohdaten, günstige Zusatzsensoren |
| Game Designer | Motivation ohne Zwang |
| Storyteller | Daten als Geschichte, Audio, Briefe |
| Philosoph (Lebenskunst) | Sinn, Gelassenheit, „gutes Leben“ statt Optimierungswahn |
| Zukunftsforscher | was in 2–5 Jahren kommt |
| Datenschutz-Berater (ohne Veto) | sagt bei jeder Idee, was das iPhone verlässt |

---

## 2. Was in deinen Daten wirklich steckt (Inventar)

### 2.1 Quellen heute und bald

| Quelle | Rohsignale | Taktung | Stand |
|---|---|---|---|
| **Colmi R03** | Puls, HRV, Stresswert, SpO₂, Schritte/kcal/Distanz, Schlaf mit Phasen | Puls 5 min, HRV/Stress 30 min, SpO₂ stündlich Min/Max, Schritte 15 min (laut Gadgetbridge/colmi_r02_client; am R03 teils ungeprüft) | Live-Puls am R03 bisher fehlgeschlagen (STATUS.md) |
| **Colmi R09** (bestellt) | wie R03 + **Hauttemperatur** | Gadgetbridge unterstützt Temperatur bei R09 seit 12/2024 | erst nach Realtest behaupten |
| **iPhone / Apple Health** | Schritte, Etagen, Distanz, **Gangbild** (Gehgeschwindigkeit, Schrittlänge, Asymmetrie, Doppelstandphase, Gangstabilität), Treppensteiggeschwindigkeit, Kopfhörer-Lautstärke, Workouts, GPS, Gewicht (falls Waage), **Gemütszustand** (iOS-17-„State of Mind“-Einträge) | je nach Typ | vorhanden, Lese-Adapter gebaut |
| **Polar H10** (geplant) | **Roh-EKG 130 Hz**, RR-Intervalle, Beschleunigung | Echtzeit | Polar BLE SDK |
| **Kontext ohne Sensor** | Wetter, Luftqualität, Pollen (Open-Meteo, kostenlos), Kalender, Sprachnotizen, Mahlzeiten, Fotos, Zeitzone/Reisen, Mondphase, Feiertage | stündlich / Ereignis | alles lokal oder kostenlose API |

**Ehrliche Grenzen:** Der Colmi-Ring liefert nach heutigem Protokollwissen **keine Roh-PPG-Kurve**, sondern fertige Werte. Analysen, die die Pulswellenform brauchen (Gefäßalter, Vorhofflimmern aus PPG), sind mit dem Ring deshalb Stufe D, mit dem H10-EKG teilweise B.

### 2.2 Was Kombinationen freischalten

| Kombination | Was daraus lesbar wird |
|---|---|
| Nachtpuls + HRV + Temperatur | Erholung, Infekt-Muster, Alkohol-Spur, Hitze-Nächte |
| Schlaf + Wetter + Raumklima | persönliche Wetterfühligkeit |
| Schlaf + Mahlzeit-Zeitpunkt + Koffein | dein Schlafrezept |
| Puls in Ruhe + Schritte + Alter | Fitness-Schätzung, Körper-Tempo |
| GPS + Puls + Beschleunigung (iPhone) | Ritt-Analyse, Gangarten, Belastung je Abschnitt |
| H10 Mensch + H10 Pferd | Herzkopplung Reiter–Pferd |
| Kalender + Puls tagsüber | Stress-Signaturen bestimmter Termintypen |
| Sprachnotiz + alles | die „Warum“-Ebene, die Sensoren nicht kennen |
| Gangbild (iPhone) über Monate | schleichende Veränderungen der Beweglichkeit |

---

## 3. Ideenkatalog (102 Ideen, nichts vorab gestrichen)

Spalten: **Alltag** (ein Satz), **Daten**, **Wie** (lokal = auf dem iPhone, Claude = API mit Freigabe), **Stufe** (A–D), **Aufwand** (S/M/L), **Kosten** (laufend, Schätzung, Claude-Preise wie `CLAUDE-INTELLIGENCE-SPEC.md` §4).

### 3.1 Prognosen: Was morgen, nächste Woche, nächstes Jahr passiert

| # | Idee | Alltag | Daten | Wie | Stufe | Aufwand | Kosten |
|---|---|---|---|---|---|---|---|
| P1 | **Morgen-Vorhersage** | Abends: „Morgen früh erwartet: Ruhepuls 56–60, HRV eher unter deinem Schnitt“, morgens der Abgleich mit der Wirklichkeit. | Nachtpuls, HRV, Schlaf, Aktivität, Notizen | lokales persönliches Modell (Regression auf eigenen Tagen), Trefferquote sichtbar | B | M | 0 € |
| P2 | **Schlaf-Vorhersage für heute Nacht** | „Mit Training um 19 Uhr und spätem Essen: Einschlafen wahrscheinlich später, Nachtpuls höher.“ | Tagesereignisse, Wetter, Koffein | lokal | B | M | 0 € |
| P3 | **Infekt-Frühwarnung** | „Ruhepuls seit 2 Nächten über deinem Band, Temperatur leicht erhöht: so sah es vor deiner Erkältung im März aus.“ | Nachtpuls, HRV, Temperatur (R09), Notizen | lokal, Analogtage | B (Studien: Ruhepuls oft Tage vor Symptomen erhöht) | M | 0 € |
| P4 | **Übertrainings-Radar** | „Nachtpuls steigt seit 9 Tagen bei gleichbleibendem Training: Erholung hinkt hinterher.“ | Nachtpuls, HRV-Wochenmittel, Trainingslast, Gefühl | lokal | B (kleine Studien) | M | 0 € |
| P5 | **Stimmungs-Vorhersage** | „Nach Wochen wie dieser lag deine Stimmung oft etwas tiefer, plane dir etwas Gutes ein.“ | Schlafregelmäßigkeit, Ruhepuls, Aktivität, State-of-Mind-Einträge | lokal + Claude-Text | C (gute Ergebnisse vor allem bei bipolaren Störungen, kaum bei Gesunden) | M | 0 € |
| P6 | **Leistungsfenster heute** | „Dein Körper war an Tagen wie heute zwischen 16 und 19 Uhr am belastbarsten.“ | Puls, Training mit RPE, Schlaf | lokal | C | M | 0 € |
| P7 | **Körper-Tempo / „biologisches Alter“** | „Dein Körper läuft gerade wie mit ca. 44“ als Trendkurve, ausdrücklich als Annäherung. | Ruhepuls, Schritte, Schlaf, SpO₂-Nacht, Alter | lokal, angelehnt an Google „Coachable Health Age“ (Ruhepuls, Schritte, Schlaf, Aktivminuten) | C | M | 0 € |
| P8 | **Langfrist-Spiegel** | „In großen Studien ging pro 10 Schläge höherem Ruhepuls ein höheres Sterberisiko einher (z. B. relatives Risiko 1,09 in einer Meta-Analyse). Dein Trend: −3 Schläge seit Mai.“ | Ruhepuls-Trend | lokal + Studienwerte als Text | C (Bevölkerungszahlen gelten nicht 1:1 für dich) | S | 0 € |
| P9 | **Fitness-Schätzung (VO₂max)** | Grobe Ausdauer-Schätzung aus Ruhepuls und Alltag, deutlich besser mit H10-Lauf. | Ruhepuls, Alter, Aktivität; später H10 | lokal | C ohne Belastung (Meta-Analyse: Ruhe-basierte Schätzungen ungenau), B mit H10-Lauf | M | 0 € |
| P10 | **Gewichts- und Form-Prognose** | „Wenn die letzten 4 Wochen so weitergehen: Mitte Januar ca. X kg.“ | Waage (Health), Ernährung | lokal | B | S | 0 € |
| P11 | **Jahreszeiten-Prognose** | „Letzten Winter stieg dein Ruhepuls im Januar um 2 Schläge, das ist bei dir saisonal normal.“ | Langzeitdaten | lokal | B (große Kohorte zeigt saisonale Schwankung des Ruhepulses) | S | 0 € |
| P12 | **Jetlag- und Reise-Prognose** | Vor einer Reise: Plan, wann Licht, Schlaf, Essen; danach, wie viele Tage dein Puls zum Einpendeln brauchte. | Schlaf, Zeitzone, Kalender | lokal + Claude | B | M | Cent |
| P13 | **„Was wäre wenn“-Simulator** | Schieberegler: „1 h früher ins Bett, kein Alkohol unter der Woche“ → erwartete Wirkung auf deine Werte, aus deinem eigenen Modell. | alle | lokales Kausalmodell (vereinfachter Wirkungsgraph aus Experimenten) | C | L | 0 € |
| P14 | **Lebenspfade (Monte Carlo)** | Zwei Fächer möglicher Verläufe für dein Ziel, z. B. Ausdauer bis Sommer, mit Streuung. | Trends, Experimente | lokal | C | M | 0 € |
| P15 | **Verletzungs-Risikohinweis** | „Belastung steigt schneller als in deinen bisherigen Blöcken.“ | Trainingslast (akut/chronisch) | lokal | C (Belege schwach, Schlaf ist besser belegt als HRV) | S | 0 € |
| P16 | **Kater-Prognose** | Nach dem Abend mit Getränken: „Erwartete Erholungszeit bei dir: ca. 1,5 Nächte.“ | Alkohol-Notiz, frühere Nächte | lokal | B | S | 0 € |
| P17 | **Prognose-Turnier** | Lokales Modell, Claude und du selbst tippen jeden Abend auf morgen, und eine Rangliste zeigt, wer deinen Körper am besten kennt. | P1 | lokal + Claude | B | S | ca. 1 $/Monat |
| P18 | **Pferdeform-Prognose** | „Ruhepuls deines Pferdes vor dem Ritt höher als üblich: heute eher locker.“ | H10 am Pferd | lokal | C | M | 0 € (H10 nötig) |

### 3.2 Deutung: Muster, Signaturen, Detektivarbeit

| # | Idee | Alltag | Wie | Stufe | Aufwand | Kosten |
|---|---|---|---|---|---|---|
| I1 | **Nachtschicht-Forscher** | Monatlich rechnet Claude mit echtem Code Hunderte Zusammenhänge durch und bringt die stärksten mit Diagramm und Gegenprobe. | Claude **Code Execution** (Python-Sandbox) + **Files API** auf anonymisierter Tabelle (Tageswerte, ohne Namen/Orte), Korrektur für Mehrfachtests | B | M | Schätzung 0,50–3 $ je Lauf (Token + Container-Gebühr laut Preisliste prüfen) |
| I2 | **Körper-Detektiv mit Analogtagen** | (aus Lab 1) frühere, ähnliche Tage und was danach kam. | lokal + Claude | B | M | ca. 0,05 $/Fall |
| I3 | **Signaturen-Bibliothek** | Die App lernt, wie Reiten, Streit, Sauna, Wein, lange Autofahrten in deiner Nacht „aussehen“, und erkennt sie wieder. | Ereignis-Notizen + Nachtkurven, Mustervergleich | B | M | 0 € |
| I4 | **Alkohol-Fingerabdruck** | Dosis-Wirkungs-Kurve: Glas 1, 2, 3 → so stark steigt dein Nachtpuls, so sinkt HRV. | lokal | A/B (Studie mit ca. 21 000 Personen: dosisabhängig höherer Nachtpuls, niedrigere HRV) | S | 0 € |
| I5 | **Koffein-Rechner** | Halbwertszeit-Modell: „Um 22 Uhr sind noch ca. X mg im Blut“, gekoppelt an deine Einschlafzeit. | lokal | B | S | 0 € |
| I6 | **Wetterfühligkeits-Profil** | Persönliche Empfindlichkeit für Hitze, Luftdruck-Sprünge, Pollen, Feinstaub. | Open-Meteo Wetter + Luft + Pollen (Europa), lokal korreliert | B (Temperatur, Luftverschmutzung belegt; Luftdruck kaum untersucht) | M | 0 € (kostenlos, nicht kommerziell, Quellenangabe nötig) |
| I7 | **Stress-Signaturen im Kalender** | „Termine mit ‚Bank‘ im Titel erhöhen deinen Puls tagsüber messbar.“ | EventKit lokal, Titel bleiben auf dem iPhone | C | M | 0 € |
| I8 | **Gangbild-Wächter** | Langsame Veränderung von Gehtempo, Schrittlänge, Asymmetrie (iPhone in der Tasche), z. B. nach Sturz vom Pferd. | Health-Gangdaten | B | S | 0 € |
| I9 | **Körperkalender-Heatmap** | Ein Jahr auf einen Blick, jedes Kästchen eine Nacht; Claude markiert Muster wie „Montagsdelle“. | lokal + Claude Vision liest die Heatmap | B | S | Cent |
| I10 | **Körper-Wörterbuch** | Claude baut ein persönliches Lexikon: „Wenn Muster X auftritt, folgte bei dir meist Y.“ | Insight-Karten mit Verfallsdatum (Lab 1) | B | M | 0 € |
| I11 | **Ärzte-Konferenz-Simulation** | Herz-, Schlaf-, Sport- und Ernährungs-Agent diskutieren, dann Synthese; Diskussion lesbar. | Multi-Agent wie Google Personal Health Agent (Datenwissenschaft, Fachexperte, Coach) | B | M | Schätzung 0,30–0,80 $ je Konferenz |
| I12 | **1-Jahres-Gesamtblick** | Claude bekommt dein ganzes Jahr als Tageswerte (passt in 1 Mio. Token) und schreibt deine „Körperbiografie 2027“. | Langkontext | B | S | Schätzung 0,50–1,50 $ einmal im Jahr |
| I13 | **Schlafumgebung** | Raumtemperatur/-feuchte (Xiaomi-Sensor mit pvvx, wenige €) und später CO₂ zeigen, welches Zimmerklima deine besten Nächte hatte. | neuer Adapter | B | M | wenige € bis ca. 150 € (CO₂-Sensor, Preis prüfen) |
| I14 | **Lärm-Spur** | Kopfhörer-Lautstärke und Umgebungslärm (falls in Health) gegen Puls und Schlaf. | Health | C | S | 0 € |
| I15 | **SpO₂-Nacht-Muster** | Häufung niedriger Nachtwerte über Wochen → „mit Arzt besprechen“-Karte. Mit R03 nur stündliche Min/Max, daher schwach. | lokal | C mit R03; B mit Fingerclip-Oximeter (Ring-Oximetrie zeigte in Studien gute Trennschärfe für mittel-schwere Schlafapnoe) | S | 0 € |
| I16 | **Rhythmus-Auffälligkeiten** | Mit H10-EKG: unregelmäßige RR-Abstände erkennen und als „EKG-Ausschnitt dem Arzt zeigen“ speichern. | H10, lokal; Claude Vision kann den Ausschnitt beschreiben | D mit Ring, B mit H10 (Erkennung), C für jede Deutung | M | 0 € |
| I17 | **Gefäß-Alter aus der Pulswelle** | Schätzung, wie „elastisch“ deine Gefäße wirken. | braucht Roh-PPG (Ring liefert es nicht) | D (Studie mit Oura-PPG: Fehler ca. 7 Jahre) | L | – |
| I18 | **Mahlzeiten-Antwort ohne Glukosesensor** | Wie stark steigt dein Puls in den 2 h nach bestimmten Gerichten (Verdauungsarbeit)? | Puls 5 min + Mahlzeitenzeit | C | M | 0 € |
| I19 | **Glukose-Experimentmonat** | 14 Tage Glukosesensor (z. B. FreeStyle Libre, Preis grob 50–70 €, prüfen) → persönliche Reaktion auf Gerichte, Schlaf und Training. | CGM-Werte via Health | B (PREDICT: große individuelle Unterschiede, Schlaf und Tageszeit beeinflussen die Reaktion) | M | einmalig ca. 50–70 € (Schätzung) |
| I20 | **Aerobe Schwelle ohne Labor** | Beim lockeren Lauf mit H10 erkennt die App, wo deine aerobe Schwelle liegt (DFA-α1 ≈ 0,75). | H10 RR, lokal | B (validiert vor allem bei Läufern auf dem Laufband; Artefakte beachten) | M | 0 € |
| I21 | **Herzfrequenz-Erholung** | Nach jeder Belastung: Wie schnell fällt dein Puls in der ersten Minute? Trend über Monate. | H10 (oder Ring-Live, ungenauer) | B | S | 0 € |
| I22 | **Atemfrequenz aus dem EKG** | Atemzüge pro Minute im Schlaf/Training aus der EKG-Kurve des H10. | lokal | B | M | 0 € |
| I23 | **„Frag & Zeig“** | Du fragst „Wie hängen Reiten und Schlaf zusammen?“, Claude entwirft das passende Diagramm, die App zeichnet es mit echten Daten. | Claude liefert Diagramm-Spezifikation (JSON), Swift Charts rendert lokal | A | M | Cent |
| I24 | **Selbstlernende Regeln** | Claude schlägt neue lokale Hinweisregeln vor („Wenn Nachtpuls > X und Notiz ‚Wein‘ …“), du bestätigst, dann laufen sie ohne Claude. | Regel-Schema, lokaler Interpreter | B | M | Cent |

### 3.3 Lebensanleitung: vom Wissen zum Tun

| # | Idee | Alltag | Stufe | Aufwand | Kosten |
|---|---|---|---|---|---|
| L1 | **Tagesdrehbuch** | Morgens ein Plan in 5 Zeilen: Energie-Erwartung, bester Moment für Training/Reiten, Essen, Licht, Zubettgehzeit. | B | M | ca. 0,02 $/Tag (Sonnet) oder 0 € (Apple-KI) |
| L2 | **Energie-Konto** | Ein Akku-Bild aus Schlaf, Nachtpuls und Tagesbelastung, das zeigt, wie viel „Reserve“ heute da ist. | C (ähnlich Garmin Body Battery; Methode nicht offen validiert) | M | 0 € |
| L3 | **Wenn-Dann-Pläne zum richtigen Moment** | (Lab 1) kleine Pläne, die ausgelöst werden, wenn sie helfen. | B | M | Cent |
| L4 | **Schlafrezept** | Deine persönliche Liste: welche Abende zu deinen besten Nächten führten (Essen, Training, Bildschirm, Zimmer). | B | S | 0 € |
| L5 | **Licht-Coach** | Morgenlicht- und Abend-Dimm-Hinweise passend zu deinem Chronotyp und Sonnenaufgang am Wohnort. | B | S | 0 € |
| L6 | **Experiment-Labor** | (Lab 1) Selbstversuche mit Plan und Auswertung, jetzt auch mit Ernährung und Nahrungsergänzung als Thema, wenn du willst. | B | M | ca. 0,10 $/Versuch |
| L7 | **Stoischer Abend** | Drei Fragen zum Tag, Claude spiegelt sie mit deinen Daten („Du warst heute ruhiger als dein Puls vermuten lässt“). | C | S | Cent |
| L8 | **Werte-Kompass** | (Lab 1) Lebensziele als Wochensignale. | B | M | Cent |
| L9 | **Brief an dein Ich in einem Jahr** | Zeitkapsel mit deinen Werten heute; in 12 Monaten öffnet die App sie und vergleicht. | A | S | 0 € |
| L10 | **Gesprächs-Timing** | „Schwierige Telefonate legst du besser nicht auf Tage nach kurzen Nächten.“ | C | S | 0 € |
| L11 | **Mikro-Pausen** | Wenn der Puls tagsüber lange erhöht ist ohne Bewegung: 2 Minuten Atem-Haptik anbieten. | B | S | 0 € |
| L12 | **Saisons statt Streaks** | (Lab 1) 6-Wochen-Themen statt Serien. | B | S | 0 € |

### 3.4 Ernährung: der Tageskoch (Gerichtsvorschläge)

Grundsatz: **Claude erfindet Rezepte und Kombinationen, die Nährwerte rechnet die App lokal** aus Lebensmitteldatenbanken
(Open Food Facts/USDA, laut Owner-Entscheidung erlaubt). Grund: Studien zeigen, dass Sprachmodelle Kalorien unterschiedlich genau schätzen und zusammengesetzte Gerichte schwer zerlegen (NutriGen; Nutrients 2025).

| # | Idee | Alltag | Daten | Stufe | Aufwand | Kosten |
|---|---|---|---|---|---|---|
| E1 | **Tageskoch: 3 Gerichte am Morgen** | Frühstück, Mittag, Abend passend zu: letzter Nacht, heutigem Training (z. B. Reiten 17 Uhr → kohlenhydratreicher Mittag, leichter Abend), Proteinziel, Saison (November: Kohl, Kürbis, Rote Bete, Äpfel), Vorlieben, Kochzeit. | Schlaf, Kalender, Ziele, Coach Memory | B | M | ca. 0,03 $/Tag (Sonnet, Schätzung) |
| E2 | **Kühlschrank-Foto** | Foto vom offenen Kühlschrank → drei Gerichte nur mit dem, was da ist. | Claude Vision | B | S | ca. 0,02 $/Foto |
| E3 | **Speisekarten-Foto** | Im Restaurant: Foto der Karte → „heute für dich passend: …“ mit Begründung aus deinem Tag. | Vision | B | S | ca. 0,02 $/Foto |
| E4 | **Schlaf-Abendessen** | Abends Gerichte, die zu deinen besten Nächten passten (Zeitpunkt, Menge), plus Ideen mit kleiner Studienlage (z. B. Kiwi am Abend, Sauerkirsche, beides nur kleine Studien). | Ernährungstagebuch + Schlaf | C | S | Cent |
| E5 | **Wochenplan + Einkaufsliste** | Sonntags Plan für die Woche, die Einkaufsliste landet in der Erinnerungen-App. | EventKit Reminders | A | M | ca. 0,10 $/Woche |
| E6 | **Training-Ernährung** | Vor/nach Reiten oder Kraft: was, wann, wie viel; danach Abgleich, wie du dich gefühlt hast. | Coach | B | S | Cent |
| E7 | **Persönliches Essens-Reaktions-Profil** | Über Wochen lernt die App: Nach Pasta abends ist dein Nachtpuls höher, nach Fisch nicht. | Mahlzeiten + Nachtpuls (I18), optional CGM (I19) | C (B mit CGM) | M | 0 € |
| E8 | **Koch-Assistent per Sprache** | Schritt für Schritt vorlesen, „weiter“ sagen, Timer setzen. | AVSpeechSynthesizer, lokal | A | M | 0 € |
| E9 | **Rest-Retter** | Was übrig ist, wird zu einem Gericht für morgen, damit nichts wegkommt. | Vision/Text | A | S | Cent |
| E10 | **Saison- und Regionalkalender** | Gerichte bevorzugt aus dem, was gerade in Deutschland Saison hat. | lokale Tabelle | A | S | 0 € |
| E11 | **Gäste-Modus** | „Samstag 4 Personen, einer vegetarisch“ → Menü, das trotzdem zu deinem Plan passt. | Text | A | S | Cent |
| E12 | **Fasten- und Essensfenster-Experiment** | Selbstversuch: Wie verändern 10 h Essensfenster deinen Nachtpuls und Schlaf? | Experiment-Labor | B | S | Cent |

### 3.5 Pferd und Reiten

| # | Idee | Alltag | Stufe | Aufwand | Kosten |
|---|---|---|---|---|---|
| H1 | **Herzkopplung Reiter–Pferd** | Nach dem Ritt: Phasen im Gleichklang, wer reagiert zuerst. | B (Sci. Rep. 2025 mit Polar Equine; iScience 2024) | L | 2. H10 + Equine-Gurt, grob 150–200 € (prüfen) |
| H2 | **Gangarten-Erkennung** | iPhone in der Tasche erkennt Schritt/Trab/Galopp aus der Beschleunigung, Karte färbt die Route nach Gangart. | C (Gangart-Erkennung aus Bewegungssensoren ist erforscht, am iPhone in der Reithosen-Tasche ungeprüft) | M | 0 € |
| H3 | **Ritt-Bericht** | GPS + Puls + Gangart → Claude schreibt eine kurze Ritt-Geschichte mit Belastungskurve. | B | M | Cent |
| H4 | **Pferde-Fitness** | Ruhepuls und Erholung des Pferdes nach festem Trainingsstück über Monate. | B (H10 am stehenden Pferd gut validiert, in Bewegung vorsichtig) | M | H10 |
| H5 | **Stalltagebuch** | Sprachnotiz „Hufschmied, Wurmkur, Weidegang“ → Pferdeprofil mit Ereignissen. | A | S | 0 € |
| H6 | **Reiter-Körper** | Sitz und Rücken: Wie verändern Reittage deinen Gang (I8) und Schlaf? | C | S | 0 € |

### 3.6 Erlebnis, Klang, Spiel

| # | Idee | Alltag | Stufe | Aufwand | Kosten |
|---|---|---|---|---|---|
| X1 | **Morgen-Podcast** | Claude schreibt ein 2-Minuten-Skript, das iPhone liest es vor (lokale Stimme, kostenlos). | A | S | ca. 0,02 $/Tag |
| X2 | **Körperwetter-Landschaft** | Deine Woche als Landschaft, Nebel = kurze Nächte, antippbar. | A (Darstellung) | L | 0 € |
| X3 | **Herz-Musik live** | H10-RR steuert Tempo und Klang einer Ambient-Musik; zum Runterkommen. | A | M | 0 € |
| X4 | **Hör deine Woche** | 20-Sekunden-Sonifikation. | A | S | 0 € |
| X5 | **Prognose-Turnier** | siehe P17. | B | S | ~1 $/Monat |
| X6 | **Jahres-Chronik** | Buch zum Durchblättern, inkl. Experimente und Erkenntnisse. | A | M | im Monatsbudget |
| X7 | **Siri und Widgets** | „Hey Siri, wie war meine Nacht?“, Live-Puls beim Reiten auf dem Sperrbildschirm. | A | M | 0 € |
| X8 | **Living Twin reagiert** | Das 3D-Herz/der Körper zeigt Erholung und Prognose (z. B. etwas „gedämpfter“ bei Infekt-Muster). | A (Darstellung), Inhalt wie P3 | L | 0 € |

### 3.7 KI-Superkräfte (technische Hebel, die alles oben möglich machen)

| # | Hebel | Was er ermöglicht | Stand |
|---|---|---|---|
| K1 | **Code Execution + Files API** | Claude rechnet selbst in Python, statt nur zu lesen (I1, I12). | in der Claude-API vorhanden; Modell- und Versionsliste vor Umsetzung gegen die aktuelle Doku prüfen |
| K2 | **Memory Tool** | Claude führt eigene Notizdateien, die **die App speichert** (lokal), z. B. das Körper-Wörterbuch. | in der Claude-API (Dateien liegen beim Client) |
| K3 | **1-Mio.-Token-Kontext** | ganzes Jahr auf einmal ansehen (I12). | Opus 5.5 mit 1M-Kontext |
| K4 | **Vision** | Kühlschrank, Speisekarte, Laborbefund, eigene Diagramme, EKG-Ausschnitte. | vorhanden |
| K5 | **Tool Use mit lokalen Werkzeugen** | Claude fragt gezielt ab, statt alles zu bekommen. | geplant (Intelligence-Spec §5) |
| K6 | **Batch-API** | Monats-/Jahresläufe ca. 50 % günstiger. | vorhanden |
| K7 | **Apple Foundation Models** | kostenlose, lokale Texte und Stichworte. | iOS 26, iPhone 16 Pro geeignet |
| K8 | **Multi-Agent** | Ärzte-Konferenz (I11), Prognose-Turnier (P17). | mit normaler API baubar |

### 3.8 Zusatzsensoren (nur wenn du willst)

| Gerät | Was es freischaltet | Kosten (Schätzung, vor Kauf prüfen) |
|---|---|---|
| Polar H10 (2×, + Equine-Gurt) | EKG, RR, Schwelle, Herzkopplung mit Pferd | ca. 90 € je Gurt, Equine-Gurt extra |
| Colmi R09 | Temperatur → Infekt, Zyklus der inneren Uhr | bestellt |
| Glukosesensor 14 Tage | Essens-Reaktion | ca. 50–70 € |
| Raumsensor (Xiaomi + pvvx) | Zimmerklima | wenige € |
| CO₂-Sensor mit Bluetooth | Luft im Schlafzimmer | ca. 100–200 € |
| Bluetooth-Waage / Blutdruckgerät mit Standardprofil | Gewicht, Blutdruck-Trend | ca. 30–80 € |
| Fingerclip-Oximeter mit Aufzeichnung | Nacht-SpO₂ durchgehend (I15 → B) | ca. 50–150 € |

### 3.9 Grenzgänger: mutig, teils spekulativ, bewusst über den Rand gedacht

| # | Idee | Alltag | Stufe | Aufwand | Kosten |
|---|---|---|---|---|---|
| G1 | **Finger auf die iPhone-Kamera** | 30 Sekunden Finger auf Kamera und Blitz liefern die **Roh-Pulswelle**, die der Ring nicht hergibt → Gefäß-Steifigkeit, Rhythmus-Check, Atemfrequenz. | B (Kamera-PPG ist gut erforscht), C für Gefäßalter | M | 0 € |
| G2 | **Puls aus dem Selfie-Video** | Morgens 20 s ins Gesicht filmen: Puls und Atmung aus feinsten Hautfarbwechseln (rPPG), dazu Claude Vision: „wirkst müder als sonst“. | C | M | Cent |
| G3 | **Stimm-Biomarker** | 10 Sekunden vorlesen am Morgen → Veränderungen der Stimme (Heiserkeit, Tempo, Energie) als frühes Infekt-/Müdigkeitssignal neben Puls und Temperatur. | C (aktive Forschung, keine verlässlichen Verbraucher-Werte) | M | 0 € (lokal) |
| G4 | **Digitaler Zwilling, Stunde für Stunde** | Die App simuliert deinen Puls für die nächsten 24 h aus Kalender, Schlaf, Wetter; jede Abweichung der Wirklichkeit ist ein Hinweis („heute angespannter als erwartet“). | C (Forschung zu persönlichen Herzmodellen vorhanden) | L | 0 € |
| G5 | **Innere-Uhr-Phase aus Temperatur** | Mit R09: Tiefpunkt deiner Körpertemperatur in der Nacht als Zeiger der inneren Uhr; Jetlag- und Schichtplanung minutengenau. | C | M | 0 € |
| G6 | **Laborwerte × Wearables** | Fotos alter Blutbilder (Ferritin, Vitamin D, Schilddrüse …) werden mit Puls-, HRV- und Schlaftrends daneben gelegt: „Dein HRV-Tief im Februar fiel mit niedrigem Ferritin zusammen.“ | C (Zusammenhang, keine Ursache) | M | Cent/Foto |
| G7 | **Gen-Rohdaten-Import** | Falls du je einen DNA-Test machst: Chronotyp-, Koffein- und Laktose-Varianten als zusätzliche Hypothesen, die die App mit deinen echten Daten gegenprüft („Gen sagt schneller Koffein-Abbau, deine Nächte sagen: eher nicht“). | C | M | Test extern, App 0 € |
| G8 | **Musik, die dich beruhigt** | Welche Lieder (Apple Music, zuletzt gespielt) gingen mit sinkendem Puls einher? Eigene „Puls-runter-Playlist“. | C | M | 0 € |
| G9 | **Orte, die dir guttun** | Wo (Stall, Wald, Büro, Zuhause) ist dein Puls in Ruhe am niedrigsten? Karte deiner Ruheorte, Koordinaten bleiben auf dem iPhone. | C | M | 0 € |
| G10 | **Paar- oder Familien-Sync** | Zweiter Ring beim Partner (mit dessen Einverständnis): Schlafen eure Nächte im Gleichtakt? Wer weckt wen? | C | M | zweiter Ring ca. 20–40 € (prüfen) |
| G11 | **Lebensereignis-Erkennung** | Die App merkt aus Daten, dass sich etwas Großes verändert hat (Umzug, Trauer, neues Pferd, neuer Job), und fragt behutsam nach. | C | M | 0 € |
| G12 | **Mondphase und Schlaf** | Spielerischer Selbsttest einer umstrittenen Hypothese: schläfst **du** bei Vollmond anders? Nach einem Jahr gibt es eine Antwort nur für dich. | C | S | 0 € |
| G13 | **Kälte-, Sauna-, Eisbad-Profil** | Wie reagieren Nachtpuls und HRV auf Sauna oder kaltes Duschen, persönliche Dosis-Wirkungs-Kurve. | B | S | 0 € |
| G14 | **Meditationstiefe live** | Mit H10: Atem und HRV während einer Meditation; Klang wird ruhiger, je kohärenter dein Herzrhythmus wird. | B | M | H10 |
| G15 | **Nickerchen-Optimierer** | Welche Länge und Uhrzeit des Mittagsschlafs führte bei dir zu guten Nächten statt schlechten? | B | S | 0 € |
| G16 | **Gesundheitsspanne-Uhr** | Aus Ruhepuls, Fitness, Schlaf, Bewegung eine „Healthspan-Uhr“, die zeigt, wohin deine Gewohnheiten langfristig zeigen; ausdrücklich Modell, nicht Schicksal. | C | M | 0 € |
| G17 | **Bevölkerungs-Spiegel** | Wo liegst du im Vergleich zu großen öffentlichen Datensätzen (Ruhepuls, Schritte, Schlaf nach Alter)? Perzentil statt Urteil. | B | M | 0 € |
| G18 | **Sich selbst erweiternde App** | Claude erkennt eine Frage, die die App noch nicht beantworten kann, und formuliert daraus automatisch einen Feature-Vorschlag als GitHub-Issue für die Entwicklung. Die App wächst mit deinen Fragen. | B (technisch einfach; Umsetzung bleibt bei der Entwicklung) | S | 0 € |
| G19 | **Zweite KI als Gegenspieler** | Ein zweites Modell (z. B. ein anderes Claude-Modell oder auf Wunsch ein anderer Anbieter) bekommt dieselben Fakten und muss Claude widersprechen; du siehst beide Sichtweisen. | B | S | ca. 0,05 $/Bericht |
| G20 | **Zukunfts-Ich im Gespräch** | Claude spricht als „du in 10 Jahren“, gestützt auf deine echten Trends (zwei Pfade aus P14), und erzählt, wie sich die Gewohnheiten angefühlt haben. | C (emotionales Werkzeug, keine Vorhersage) | S | Cent |
| G21 | **Schlafphasen-Wecker** | Wecker in leichter Schlafphase. Mit dem Ring nur, wenn Live-Daten nachts gehen (fraglich); mit iPhone-Bewegung/Ton grob möglich. | D mit Ring, C mit iPhone | M | 0 € |
| G22 | **Herzfrequenz-Kunst** | Jede Nacht wird als generatives Bild gespeichert; nach einem Jahr ein Poster deines Jahres. | A | S | 0 € |

---

## 4. Die „Mind-Blow“-Kombinationen

1. **Wetter × Schlaf × Alkohol × Reiten:** Die App weiß, dass du nach Reittagen besser schläfst, nach Wein schlechter, bei Schwüle unruhig. Sie sagt abends: „Morgen schwül, heute Reiten: Wein eher weglassen, dann ist deine Nacht wahrscheinlich normal.“ (P2 + I4 + I6)
2. **Kalender × Puls × Essen:** „Am Donnerstag drei Termine hintereinander, deine Puls-Signatur für solche Tage ist hoch. Mittags etwas Leichtes, um 15 Uhr 2 Minuten Atmung, abends Fisch statt Pasta.“ (I7 + L11 + E7)
3. **Prognose mit Gegenwette:** Lokales Modell, Claude und du tippen; die App zeigt nach 3 Monaten, wer deinen Körper am besten vorhersagt. Das trainiert dein Körpergefühl. (P17)
4. **Nachtschicht-Forscher findet Unerwartetes:** z. B. „Deine besten Nächte folgten Tagen mit über 2 h draußen, unabhängig vom Training.“ und baut sofort ein Experiment daraus. (I1 + L6)
5. **Pferd als Spiegel:** Herzkopplung + Gangart + dein Stresswert vom Tag: „Nach Bürotagen mit hohem Puls reagierte dein Pferd im Trab früher.“ (H1 + H2 + I7)
6. **Infekt-Frühwarnung × Tageskoch × Training:** Muster wie vor einer Erkältung → Training wird automatisch leichter vorgeschlagen, Gerichte wärmend, früher ins Bett. (P3 + E1 + L1)

---

## 5. Bewertung und Top 10

Punkte: Wirkung (1–5) + Machbarkeit (1–5, 5 = einfach) + „Wow“ (1–5). Stufe A–D wie oben.

| Rang | Idee | Wirkung | Machbarkeit | Wow | Stufe | Release |
|---|---|---|---|---|---|---|
| 1 | I1 Nachtschicht-Forscher | 5 | 4 | 5 | B | R3 |
| 2 | P1 Morgen-Vorhersage (+ P17 Turnier) | 5 | 4 | 5 | B | R2/R3 |
| 3 | I6 + P2 Körper-Wetterbericht | 5 | 4 | 4 | B | R2 (Open-Meteo-Adapter) |
| 4 | E1–E3 Tageskoch mit Fotos | 5 | 4 | 4 | B | R5 |
| 5 | P3 Infekt-Frühwarnung | 5 | 4 | 4 | B | R2, stärker mit R09 |
| 6 | I4 + I5 Alkohol- und Koffein-Fingerabdruck | 4 | 5 | 4 | A/B | R2 |
| 7 | I11 Ärzte-Konferenz | 4 | 4 | 5 | B | R3/R6 |
| 8 | X1 Morgen-Podcast | 4 | 5 | 4 | A | R6 |
| 9 | P7 Körper-Tempo | 3 | 4 | 5 | C | R3 (Prognose-Labor) |
| 10 | H1 Herzkopplung Reiter–Pferd | 5 | 2 | 5 | B | nach H10-Kauf |

**Schnelle Gewinne (klein, sofort sinnvoll):** I4/I5 Alkohol & Koffein, P11 Jahreszeiten, L9 Zeitkapsel, I8 Gangbild-Wächter, E10 Saisonkalender.

**Gehören zusammen:** P1, P17, I1 und L6 bilden zusammen eine Schleife: vorhersagen → abgleichen → Zusammenhänge finden → Experiment → bessere Vorhersage.

---

## 6. Was das für die bestehenden Regeln heißt (Entscheidung bei Johannes)

Diese Runde testet Grenzen aus. Drei Punkte berühren bisherige Festlegungen. Sie sind hier nur **benannt**, die Entscheidung liegt bei dir:

| Punkt | Bisher | Vorschlag für die Umsetzung |
|---|---|---|
| Wackelige Prognosen (Stufe C) | „Trends beschreiben, keine Befunde“ | eigener Bereich **„Prognose-Labor“**, standardmäßig an oder aus nach deiner Wahl, jede Aussage mit Stufe und Trefferquote |
| Krankheitsnahe Hinweise (Infekt, SpO₂-Nacht, Rhythmus) | „keine Diagnosen“ | als Muster formulieren („so sah es vor deiner Erkältung aus“), bei Rhythmus/SpO₂ immer „ärztlich abklären“ |
| Daten an Claude für Code-Ausführung (I1) | minimierte Fakten | anonymisierte Tagestabelle ohne Namen, Orte, Gerätenummern; vor jedem Lauf Vorschau und Freigabe |

Kosten bei voller Nutzung (Schätzung): Tageskoch, Tagesdrehbuch, Podcast täglich ca. 2–3 $/Monat, plus Nachtschicht-Forscher und Konferenz ca. 2–4 $/Monat, plus bisherige Berichte (ca. 5–6 $/Monat laut Intelligence-Spec). Zusammen grob **10–13 $/Monat**, mit Apple-KI für Alltagstexte deutlich weniger. Monatsbudget in der App begrenzt das hart.

---

## 7. Vergleichsprojekte (was es schon gibt)

| Projekt | Was es macht | Was PULSE ONE anders/zusätzlich kann |
|---|---|---|
| Google Personal Health Agent (Forschung) | 3 Unteragenten: Daten, Fachexperte, Coach | gleiche Idee, aber lokal gerechnet, eigener Schlüssel, Ring + Pferd |
| Google PHIA (Nature Comms 2026) | Agent schreibt Code für Analysen | entspricht I1, bei uns mit Freigabe und Anonymisierung |
| Apple Wearable Behavior Model (Forschung 2025) | Grundmodell aus 27 Verhaltenswerten sagt Gesundheitszustände voraus | zeigt, dass Tageswerte (nicht Rohsignale) viel tragen, unser Datenmodell passt dazu |
| WHOOP My Memory + Proactive Check-Ins (Beta 2026) | Gedächtnis, Hinweise im richtigen Moment | bei uns lokal, mit Verfallsdatum, Pferd, Experimente |
| Oura Advisor | KI-Begleiter mit Gedächtnis | Belegpflicht, Prognose-Turnier, offene Daten |
| Claude ↔ Apple Health (Beta, USA) | Claude-App liest Health | PULSE ONE kennt zusätzlich Ring-, Pferde-, Kontextdaten |
| Open Wearables (Open Source, MIT) | selbst gehostete Datenplattform mit offenen Bewertungsformeln und MCP-Server | Inspiration für offene, nachvollziehbare Formeln |
| StudyMe / Self-E (Forschungs-Apps) | geführte Selbstversuche | entspricht L6, bei uns mit Sensordaten automatisch ausgewertet |
| Google „Coachable Health Age“, Apple „Health Age“, Eight Sleep „Speed of Aging“ | Körper-Alter aus Wearables | P7, bei uns mit offener Formel und Stufe C |

---

## 8. Vorschlag zur Einordnung in die Roadmap

| Release | Neu aus Lab 2 |
|---|---|
| R2 Health Analytics | Open-Meteo-Kontext (Wetter/Luft/Pollen), Alkohol-/Koffein-Notizen, P1 Morgen-Vorhersage lokal, P3, P11, I4, I5, I8 |
| R3 Claude Intelligence | I1 Nachtschicht-Forscher (Code Execution), I11 Konferenz, P7 im Prognose-Labor, I23 Frag & Zeig, P17 Turnier |
| R4 Coach | L1 Tagesdrehbuch, L11 Mikro-Pausen, I20/I21 sobald H10 |
| R5 Ernährung | E1–E12 Tageskoch |
| R6 Unified Coach | X1 Morgen-Podcast, L7, I12 Jahresblick |
| R8 Premium | X2–X4, X8 |
| Sportwelt Reiten | H1–H6 |

---

## 9. Quellen (abgerufen 2026-11-20)

**KI und Vergleichsprojekte**
- Google Personal Health Agent: https://research.google/blog/the-anatomy-of-a-personal-health-agent/ · https://arxiv.org/pdf/2508.20148
- PHIA: https://arxiv.org/html/2406.06464v4
- Apple Wearable Behavior Model: https://arxiv.org/html/2507.00191v1
- WHOOP My Memory: https://www.whoop.com/us/en/thelocker/my-memory-whoop/
- Oura Advisor: https://www.businesswire.com/news/home/20250331565896/en/
- Claude ↔ Apple Health: https://www.macrumors.com/2026/01/22/claude-ai-adds-apple-health-connectivity/
- Claude Code Execution Tool: https://platform.claude.com/docs/en/agents-and-tools/tool-use/code-execution-tool · Memory Tool: https://platform.claude.com/en/docs/agents-and-tools/tool-use/memory-tool
- Open Wearables: https://alternativeto.net/software/open-wearables/about/
- Google Coachable Health Age: https://research.google/blog/using-wearables-to-enable-cardiovascular-kidney-metabolic-ckm-risk-profiling-for-personalized-coaching/

**Prognosen und Deutung**
- Infekt-Signale: https://www.nature.com/articles/s41591-021-01593-2 · https://www.nature.com/articles/s41551-020-00640-6 · https://pmc.ncbi.nlm.nih.gov/articles/PMC10975930
- Stimmung aus Wearables: https://doaj.org/article/7023de042e1941fcac23b61a7f9f72c8 · https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12440259/ · https://mental.jmir.org/2026/1/e85319/PDF
- Alkohol und Nachtpuls: https://pmc.ncbi.nlm.nih.gov/articles/PMC12970902/ · https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12073130/
- Ruhepuls und Sterblichkeit: https://www.cmaj.ca/content/188/3/E53 · https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7259773/
- Ruhepuls saisonal (92 457 Personen): https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7001906/
- Herzfrequenz-Erholung: https://pubmed.ncbi.nlm.nih.gov/10536127/
- VO₂max aus Wearables (Meta-Analyse): https://link.springer.com/10.1007/s40279-021-01639-y
- Körper-Alter (DunedinPACE): https://mdpi-res.com/d_attachment/dhi/dhi-01-00005/article_deploy/dhi-01-00005.pdf · Kritik: https://www.frontiersin.org/journals/digital-health/articles/10.3389/fdgth.2026.1842633/full
- Gefäßalter aus Ring-PPG: https://www.eurekalert.org/news-releases/1123213
- Schlafapnoe mit Ring-Oximetrie: https://www.frontiersin.org/articles/10.3389/frsle.2025.1549272/full
- Vorhofflimmern mit Ring: https://esc365.escardio.org/journal/2238
- Übertraining und HRV: https://pubmed.ncbi.nlm.nih.gov/24136138/ · https://www.frontiersin.org/articles/10.3389/fphys.2020.614765/pdf
- HRV und Denkleistung (kein Effekt): https://mhsrs.health.mil/MHSRS/download/downloadabstractfile/5807
- Wetter, Luft und Herz: https://tryterra.co/research/does-air-pollution-raise-your-heart-rate · https://formative.jmir.org/2026/1/e86615
- Open-Meteo Luft/Pollen: https://open-meteo.com/en/docs/air-quality-api
- DFA-α1 / aerobe Schwelle: https://www.mdpi.com/2075-4663/10/2/25 · https://pmc.ncbi.nlm.nih.gov/articles/PMC8167649
- Persönliche Herzmodelle: https://arxiv.org/abs/2508.16655v1 · https://arxiv.org/pdf/1812.01696

**Ernährung**
- PREDICT (Schlaf und Mahlzeiten-Reaktion): https://link.springer.com/10.1007/s00125-021-05608-y · https://pmc.ncbi.nlm.nih.gov/articles/PMC8741723
- LLM-Mahlzeitenpläne: https://arxiv.org/html/2502.20601 · https://www.mdpi.com/2072-6643/17/9/1492 · https://www.mdpi.com/2072-6643/17/7/1176
- Kiwi / Sauerkirsche und Schlaf: https://pubmed.ncbi.nlm.nih.gov/20438325/ · https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12438961/

**Pferd und Geräte**
- Pferd-Reiter-Synchronisierung: https://madbarn.com/research/child-horse-harmony-in-motion-a-preliminary-study-to-explore-heart-rate-synchronization-in-equine-assisted-therapy-for-neurotypical-and-adhd-children · https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11414536/
- H10 am Pferd: https://www.frontiersin.org/journals/veterinary-science/articles/10.3389/fvets.2022.939534/pdf
- Gadgetbridge Colmi/Yawell (R09 Temperatur): https://gadgetbridge.org/gadgets/wearables/yawell/ · https://gadgetbridge.org/gadgets/wearables/colmi
