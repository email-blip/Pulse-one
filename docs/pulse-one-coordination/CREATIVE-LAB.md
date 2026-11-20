# CREATIVE LAB – Neue Wege, wie Claude Gesundheitsdaten deutet und den Alltag begleitet

> **Hinweis:** Erweitert und abgelöst durch `CREATIVE-LAB-2.md` (ohne Vorauswahl, 102 Ideen).

Stand: 2026-11-20 · Status aller Ideen: **Geplant / Vorschlag** (§14) · Verfasser: Claude Code
Auftrag: Johannes (Projekt-Chat, 2026-11-20 22:27): „ganz kreativ … Think out of the box … herausragende neue Interpretation und Lebensanleitung“.
Reine Doku. Kein App-Code wird angefasst.

> **Ehrlichkeitshinweis:** Das „Kreativteam“ sind acht klar getrennte Perspektiven, die ein einzelner Agent
> nacheinander eingenommen hat (wie im `EXPERT-COUNCIL-REVIEW.md`). Es gab keine echten Fachleute.
> Ideen sind Vorschläge, nichts davon ist implementiert. Preise und Studien sind mit Quelle belegt oder als Schätzung markiert.

---

## 0. Kurzfassung für Johannes

Die bestehenden Konzepte (Claude Intelligence R3, Coach R4/R6, Ernährung R5, Klinik R7) machen Claude zu einem
**sorgfältigen Analysten**: Zahlen lokal rechnen, Claude formuliert, jede Aussage mit Beleg.
Das Kreativlabor geht einen Schritt weiter: Claude wird zum **Ermittler, Versuchsleiter, Gedächtnis und Erzähler** deines Körpers,
ohne dass die Grundregeln wackeln (Daten lokal, Senden nur mit Freigabe, keine Diagnosen, keine erfundenen Zahlen).

**Top 5 (Empfehlung, Begründung in §5):**

| # | Idee | Was du im Alltag davon hast |
|---|---|---|
| 1 | **Zwei Gehirne** (Apple-KI auf dem iPhone + Claude) | Kurze Alltagstexte kommen kostenlos und offline vom iPhone, Claude wird nur für die großen Fragen gerufen, und du siehst vorher genau, was das iPhone verlässt. |
| 2 | **Körper-Detektiv mit Analogtagen** | Wenn ein Wert ungewohnt ist, legt dir die App drei mögliche Begleitumstände mit Belegen hin und zeigt frühere Tage, die genauso aussahen, und was danach kam. |
| 3 | **Experiment-Labor** | Du fragst „Schlafe ich besser ohne Kaffee nach 14 Uhr?“, und Claude baut daraus einen kleinen Selbstversuch mit Plan, Erinnerungen und ehrlicher Auswertung. |
| 4 | **Abend-Sprachnotiz** | Du sprichst abends 30 Sekunden ins iPhone („Reitstunde, viel Stress, zwei Bier“), und die App macht daraus Stichworte, die später erklären helfen, warum eine Nacht anders war. |
| 5 | **Körperbiografie mit Verfallsdatum** | Die App sammelt, was sie über deinen Körper gelernt hat, zeigt dir das als lesbares Heft und prüft jede Erkenntnis regelmäßig neu, statt alte Annahmen ewig zu wiederholen. |

**Joker für später:** Reiter-Pferd-Kopplung (zwei Polar-H10-Gurte, einer am Pferd), sobald H10 und Equine-Gurt da sind.

---

## 1. Ausgangslage: Was schon geplant ist (und hier nicht wiederholt wird)

| Bereich | Schon im Konzept | Datei |
|---|---|---|
| Lokale Fakten mit IDs, Claude belegt jede Aussage, Validator prüft Zahlen | ja | `CLAUDE-INTELLIGENCE-SPEC.md` §3 |
| Chat mit lokalen Abfragewerkzeugen (Tool Use) | ja | ebd. §5 |
| Tages-/Wochen-/Monats-/Jahresberichte, Kostenbudget | ja | ebd. §2, §4 |
| Coach Memory (Ziele, Vorlieben, Hindernisse), nur nach Bestätigung | ja | `COACH-ENGINE-SPEC.md` §7.3 |
| Persönliche Experimente (einfache Form) | ja | `konzept/RING-AUSWERTUNGEN.md` §8 |
| Kein Gesamtscore, keine Ampelfarben | entschieden | `RING-AUSWERTUNGEN.md` §8 |
| Klinischer Kontext, Arztgespräch-Vorbereitung | ja | `CLINICAL-CONTEXT-SPEC.md` |
| Foto-Analyse von Mahlzeiten | ja | `NUTRITION-SPEC.md` §5 |

Die Ideen unten setzen **auf diesen Bausteinen auf** (gleiche Fakt-IDs, gleicher `ResponseValidator`, gleiche `SafetyRules`, gleiche Datenfreigaben je Kategorie).

---

## 2. Stand der Technik (Recherche 2026-11-20)

| Was | Kernaussage | Bedeutung für PULSE ONE |
|---|---|---|
| Google **Personal Health Agent** (Forschungsprototyp, arXiv 2508.20148) | Drei Unteragenten: Datenwissenschaft, Fachexperte, Coach. Nutzer und Fachleute bewerteten das Gesamtsystem besser als Einzelagenten. | Rollenteilung übernehmen, aber lokal: Rechnen macht die App, Claude deutet und coacht. |
| Google **PHIA** (Nature Communications, Jan. 2026) | Agent schreibt Code und rechnet mehrstufig auf Wearable-Daten, statt Zahlen „aus dem Kopf“ zu nennen. | Bestätigt unseren Ansatz „Claude ruft lokale Werkzeuge, erfindet keine Zahlen“. |
| **WHOOP My Memory + Proactive Check-Ins** (Beta, Mai 2026) | Nutzer gibt Kontext per Text oder Sprache; Gedächtnis ist einsehbar, änderbar, löschbar; Hinweise zum passenden Zeitpunkt. | Sprachnotiz (Idee 4) und Körperbiografie (Idee 5), aber **lokal** und mit Verfallsdatum. |
| **Oura Advisor** (seit März 2025) | KI-Begleiter mit Gedächtnis, abschaltbar. | Marktstandard; PULSE ONE unterscheidet sich durch Belegpflicht, Selbstversuche und Datenhoheit. |
| **Claude ↔ Apple Health** (Beta, Jan. 2026, nur USA, Pro/Max) | Claude-App liest Health-Daten; Gesundheitsgespräche nicht im Chat-Gedächtnis und nicht fürs Training. | Zeigt, dass Anthropic Gesundheit ernst nimmt; PULSE ONE nutzt aber die API mit eigenem Schlüssel und lokaler Vorverarbeitung (Ring-Daten kennt die Claude-App nicht). |
| **Apple Foundation Models** (iOS 26, iPhone 15 Pro und neuer) | Sprachmodell auf dem Gerät, mit `@Generable` (garantiert strukturierte Ausgabe) und Tool Calling. Entwicklerforen melden Zuverlässigkeitsprobleme ab iOS 26.4 (nicht von Apple bestätigt). | Basis für „Zwei Gehirne“ (Idee 1). Johannes' iPhone 16 Pro ist geeignet. Nur hinter `if #available(iOS 26, *)`. |
| **Frühe Krankheitszeichen in Wearable-Daten** (Nat. Med. 2021, Nat. Biomed. Eng. 2020, TemPredict) | Ruhepuls stieg bei vielen Infektionen Tage vor Symptomen; Fingertemperatur zeigt Fieber. Eine kleine Studie (BMJ Open 2025) fand keinen Unterschied. Studien meist klein, COVID-lastig. | Nur als **persönliches Muster** nutzen („ähnlich wie vor deiner Erkältung im März“), nie als Erkennung von Krankheiten. |
| **N-of-1-Selbstversuche** (StudyMe, Self-E, Frontiers-Themenreihe) | Apps können Laien durch Selbstversuche führen; Fallstricke: Autokorrelation, Trends, Übertragungseffekte. | Experiment-Labor (Idee 3) mit Auswaschtagen und lokaler Statistik. |
| **Pferd-Reiter-Herzkopplung** (Sci. Rep. 2025 mit Polar Equine; iScience 2024) | Messbare Synchronisierung der Herzfrequenzen; Polar H10 am Pferd im Stand und bei Bodenarbeit gegen EKG gut, in Bewegung vorsichtig (Southampton 2010, ältere Polar-Modelle). | Joker-Idee 14. |

Quellen am Ende (§8).

---

## 3. Das Kreativteam (acht Perspektiven)

| Kürzel | Perspektive | Leitfrage |
|---|---|---|
| **KI** | KI-Forscherin (Agenten, Tool Use, Gedächtnis) | Was kann Claude 2026 wirklich, und wie bleibt es nachprüfbar? |
| **VP** | Verhaltenspsychologe | Was verändert tatsächlich Verhalten, ohne zu nerven oder Druck zu machen? |
| **GD** | Game Designer | Wie wird es fesselnd ohne Streak-Zwang und Schuldgefühle? |
| **CB** | Chronobiologin | Welche Rolle spielen innere Uhr, Rhythmus und Zeitpunkt? |
| **ST** | Storyteller | Wie werden Zahlen zu einer Geschichte, die man behält? |
| **SW** | Sportwissenschaftler (inkl. Reiten) | Was hilft beim Training und im Sattel? |
| **DE** | Datenschutz-Ethikerin (**Vetorecht**) | Bleibt Johannes Herr seiner Daten, und ist es kein Medizinprodukt? |
| **DS** | Designer (Interaktion, Klang, Haptik) | Wie fühlt es sich an, und passt es zu „ruhig & dunkel“? |

Arbeitsweise: Jede Perspektive brachte Ideen ein, **DE** prüfte jede gegen die Rahmenbedingungen (§4.0), dann gemeinsame Bewertung.

---

## 4. Die Ideen

### 4.0 Prüfraster (gilt für jede Idee)

| Regel | Quelle |
|---|---|
| L – Daten bleiben lokal, Senden an Claude nur mit Freigabe je Kategorie | CLAUDE.md, Intelligence-Spec §2 |
| D – keine Diagnosen, kein Medizinprodukt, Trends statt Befunde | CLAUDE.md |
| Z – keine erfundenen Zahlen: jede Zahl kommt aus einem lokalen Fakt | Intelligence-Spec §3.4 |
| K – Kosten vorher nennen, kostenlos bevorzugen | Projektregeln |
| M – baubar ohne Mac (GitHub-Actions-Build), Apple-Frameworks zuerst | CLAUDE.md |
| S – keine simulierten Werte als Messung | CLAUDE.md |

**Bewertung:** Wirkung und Machbarkeit je 1–5 (5 = sehr hoch / sehr einfach). Kosten: einmalig und laufend.
Claude-Preise wie in `CLAUDE-INTELLIGENCE-SPEC.md` §4 (Opus 5.5: 4 $ / 20 $ je 1 Mio. Ein-/Ausgabetoken; Sonnet 5.5: 2 $ / 10 $; Haiku 5.5: 0,10 $ / 0,50 $). Laufende Kosten sind **Schätzungen**; die App zeigt echte Werte aus `usage`.

---

### Gruppe A – Deuten: Claude als Ermittler

#### 1. Zwei Gehirne: Apple-KI auf dem iPhone + Claude in der Tiefe (KI, DE)
**Alltag:** Kurze Alltagstexte kommen kostenlos und offline vom iPhone, Claude wird nur für die großen Fragen gerufen, und du siehst vorher genau, was das iPhone verlässt.

- **Gehirn 1 (lokal, Apple Foundation Models):** formuliert Morgen- und Abendsätze aus lokalen Fakten, ordnet Sprachnotizen (Idee 4), entscheidet, ob eine Frage lokal beantwortbar ist. `@Generable`-Strukturen erzwingen das Ausgabeformat; dieselbe Zahlenprüfung wie bei Claude.
- **Gehirn 2 (Claude über die API):** Wochen-/Monatsberichte, Detektiv (Idee 2), Experiment-Design (Idee 3), Gespräche.
- **„Gläserner Bote“:** Vor jedem Senden eine Seite „Das verlässt dein iPhone“: Kategorien, Zeitraum, Anzahl Fakten, Kosten, und markiert, was **nicht** gesendet wird. Zusätzlich ein monatliches **Datenbudget** (z. B. höchstens 30 Sendungen), analog zum Kostenbudget.
- **Rückfall:** Ist Apple-KI nicht verfügbar (älteres Gerät, abgeschaltet, Fehler), zeigt die App die lokalen Fakten als feste Textbausteine. Kein stiller Wechsel zu Claude.
- **Prüfung:** L ✓ (mehr bleibt lokal), D ✓ (gleiche SafetyRules), Z ✓, K ✓ (senkt Claude-Kosten), M ✓ (Swift-Framework, iOS 26 hinter `#available`; Deployment Target bleibt iOS 18).
- **Risiko:** Lokales Modell ist klein; Qualität vor Einsatz mit festen Testfällen prüfen. Forenberichte über Fehler ab iOS 26.4 ernst nehmen → Rückfall muss immer funktionieren.

| Wirkung | Machbarkeit | Kosten | Release |
|---|---|---|---|
| 5 | 4 | 0 € (lokal); spart Claude-Kosten | R3 (Grundgerüst), R6 (Tagesbegleitung) |

#### 2. Körper-Detektiv mit Analogtagen (KI, ST, CB)
**Alltag:** Wenn ein Wert ungewohnt ist, legt dir die App drei mögliche Begleitumstände mit Belegen hin und zeigt frühere Tage, die genauso aussahen, und was danach kam.

- **Auslöser:** Ein lokaler Fakt liegt außerhalb des persönlichen Bandes (z. B. Ruhepuls über p75 der Basislinie an zwei Tagen).
- **Analogtage (Methode aus der Wettervorhersage):** Die App sucht lokal die 5 ähnlichsten früheren Tage (Abstand über normierte Ruhepuls-, HRV-, Schlaf-, Aktivitäts- und später Temperaturabweichungen) und zeigt, was in den 3 Tagen danach in **deinen** Daten und Notizen stand („2-mal folgte eine Notiz ‚erkältet‘, 3-mal nichts Besonderes“).
- **Hypothesen-Tafel (Claude):** Claude bekommt Abweichung + Analogtage + Ereignisse + Sprachnotiz-Stichworte und liefert im festen Schema höchstens drei **Begleitumstände** mit Fakt-IDs, je einer Gegenprobe („Wenn es am Schlaf liegt, sollte die nächste lange Nacht den Wert senken“) und einer Einschätzung „passt gut / teilweise / kaum“.
- **Sprache:** „beobachtet zusammen mit“, nie „verursacht durch“. Bei anhaltender, deutlicher Abweichung greift der Arzthinweis der SafetyRules.
- **Prüfung:** L ✓ (Analogsuche lokal), D ✓ (keine Krankheitsnamen als Erklärung, nur eigene Notizen), Z ✓, K: ca. 0,05–0,10 $ je Fall (Schätzung, Opus effort medium), M ✓.

| Wirkung | Machbarkeit | Kosten | Release |
|---|---|---|---|
| 5 | 4 | ca. 0,5–1 $/Monat bei 10 Fällen (Schätzung) | R2 (Analogtage lokal), R3 (Hypothesen-Tafel) |

#### 3. Experiment-Labor: Claude als Versuchsleiter (KI, VP, SW)
**Alltag:** Du fragst „Schlafe ich besser ohne Kaffee nach 14 Uhr?“, und Claude baut daraus einen kleinen Selbstversuch mit Plan, Erinnerungen und ehrlicher Auswertung.

- **Frage → Plan:** Claude übersetzt eine Alltagsfrage in ein Versuchsschema (`Generable`/JSON): Zielmesswert, Bedingungen A/B, Reihenfolge (z. B. ABAB in 4 Blöcken à 5 Tage), Auswaschtage gegen Übertragungseffekte, nötige Notizen.
- **Wie lange?** Die App schätzt lokal aus der bisherigen Streuung, wie viele Tage es braucht, um einen Unterschied in der Größe X überhaupt zu sehen, und sagt es ehrlich („Unter 20 Tagen lässt sich das bei dir nicht unterscheiden“).
- **Auswertung lokal:** Permutationstest bzw. einfache Bayes-Schätzung auf Blockebene (berücksichtigt Autokorrelation besser als Tageswerte); Claude formuliert nur das Ergebnis mit Unsicherheit.
- **Grenzen:** Nur Alltagsverhalten (Koffein, Bildschirm, Abendessen, Training, Zubettgehzeit). **Keine Medikamente, keine Nahrungsergänzung in Dosierungsfragen** (DE-Veto: wäre Therapienähe).
- **Prüfung:** L ✓, D ✓ (Grenzliste), Z ✓, K ca. 0,10 $ je Versuch (Planung + Auswertung, Schätzung), M ✓.

| Wirkung | Machbarkeit | Kosten | Release |
|---|---|---|---|
| 5 | 4 | ca. 0,10 $ je Versuch | R2 (Statistik), R3 (Claude-Plan), R4 (Erinnerungen) |

#### 4. Abend-Sprachnotiz als fehlende Datenschicht (VP, KI, DS)
**Alltag:** Du sprichst abends 30 Sekunden ins iPhone („Reitstunde, viel Stress, zwei Bier“), und die App macht daraus Stichworte, die später erklären helfen, warum eine Nacht anders war.

- **Ablauf:** Spracherkennung **auf dem Gerät** (Apple Speech-Framework mit On-Device-Erkennung; API vor Umsetzung gegen die Doku des gepinnten SDK prüfen), dann Apple-KI (Idee 1) oder feste Regeln → Stichworte: Stimmung 1–5, Stress, Koffein, Alkohol, Training/Reiten, spätes Essen, Bildschirm, Krankheitsgefühl, Freitext.
- **Bestätigung:** Stichworte erscheinen als Chips, ein Tipp bestätigt oder korrigiert. Audio wird nach der Umwandlung **gelöscht** (Standard).
- **Nutzen:** Sensoren wissen nichts über Stress, Alkohol oder Ärger. Genau diese Stichworte machen Korrelationen, Detektiv und Experimente erst aussagekräftig.
- **DE-Veto:** keine Stimmungs- oder Krankheitsdeutung aus dem **Klang** der Stimme. Nur der Inhalt zählt, den Johannes selbst sagt.
- **Prüfung:** L ✓ (alles lokal), D ✓, Z ✓, K 0 €, M ✓.

| Wirkung | Machbarkeit | Kosten | Release |
|---|---|---|---|
| 4 | 4 | 0 € | R2 (Notizen als Ereignisse), R3 (Stichworte via Apple-KI) |

#### 5. Körperbiografie mit Verfallsdatum (KI, ST, DE)
**Alltag:** Die App sammelt, was sie über deinen Körper gelernt hat, zeigt dir das als lesbares Heft und prüft jede Erkenntnis regelmäßig neu, statt alte Annahmen ewig zu wiederholen.

- **Erkenntnis-Karte:** Satz („Nach Reittagen ist dein Ruhepuls am Folgetag eher niedriger“), Belege (Fakt-IDs, n, Zeitraum), Stärke (schwach / mittel / deutlich), Herkunft (Experiment, Korrelation, Analogtage), **Prüfdatum**.
- **Verfallsdatum:** Jede Erkenntnis wird nach z. B. 90 Tagen automatisch lokal neu gerechnet; hält sie nicht mehr, wird sie als „verblasst“ markiert. So bleibt das Wissen lebendig, wenn sich Körper, Saison oder Gerät ändern.
- **Kontext statt Rohdaten:** Für Claude-Gespräche wird die Biografie (nur freigegebene Kategorien) mitgeschickt statt langer Historien. Das spart Token und sendet weniger.
- **Abgrenzung:** Coach Memory (R6) speichert Vorlieben und Ziele; die Körperbiografie speichert **messbare Muster**. Beide getrennt einsehbar, löschbar, nur nach Bestätigung.
- **Prüfung:** L ✓, D ✓ (keine Diagnosen in Karten), Z ✓ (jede Zahl neu gerechnet), K spart Kosten, M ✓ (SwiftData).

| Wirkung | Machbarkeit | Kosten | Release |
|---|---|---|---|
| 4 | 4 | 0 € (spart Token) | R3 (Karten), R6 (Gesprächskontext) |

#### 6. „Zweite Meinung“: Claude prüft Claude (KI, DE)
**Alltag:** Unter jedem großen Bericht steht, wie sicher die Aussagen sind, weil ein zweiter, günstiger KI-Durchgang nach Übertreibungen und schwachen Belegen sucht.

- Nach dem Bericht: ein kurzer Prüflauf mit Haiku 5.5 oder Sonnet 5.5, der nur Bericht + Fakten sieht und je Abschnitt „gut belegt / dünn belegt / überzogen“ zurückgibt. Überzogene Sätze werden markiert oder nicht angezeigt.
- Ergänzt den lokalen `ResponseValidator` (Zahlen) um eine **inhaltliche** Prüfung (Kausalsprache, fehlende Unsicherheit).
- **Prüfung:** L ~ (gleiche Daten, zweiter Aufruf, keine neuen Kategorien), D ✓, Z ✓, K ca. 0,01 $ je Bericht mit Haiku (Schätzung), M ✓.

| Wirkung | Machbarkeit | Kosten | Release |
|---|---|---|---|
| 3 | 5 | ca. 0,01–0,03 $ je Bericht | R3 |

#### 7. Foto als Datenquelle über Mahlzeiten hinaus (KI, SW)
**Alltag:** Du fotografierst einen Laborausdruck oder einen Trainingsplan vom Reitstall, und die App überträgt die Angaben nach deiner Bestätigung in die richtigen Felder.

- Claude Vision liest das Bild im festen Schema; nichts wird ohne Bestätigung gespeichert. Laborwerte landen nur im Klinischen Kontext (R7) und nur mit dessen separater Freigabe.
- Alternative zuerst lokal: Apple Vision-Texterkennung auf dem Gerät; Claude nur, wenn Struktur unklar.
- **Prüfung:** L ~ (Bild verlässt Gerät nur mit Freigabe; lokale Texterkennung bevorzugt), D ✓ (keine Bewertung der Laborwerte, nur Übernahme), Z ✓ (Zahlen stammen aus dem Bild, Bestätigung durch Johannes), K ca. 0,01–0,03 $ je Foto (Schätzung nach Formel in NUTRITION-SPEC §5.3).

| Wirkung | Machbarkeit | Kosten | Release |
|---|---|---|---|
| 3 | 4 | Cent-Beträge je Foto | R5 (gleiche Pipeline wie Mahlzeiten), R7 (Labor) |

---

### Gruppe B – Lebensanleitung: vom Wissen zum Tun

#### 8. Werte-Kompass: Lebensziele in Wochensignale übersetzen (VP, ST)
**Alltag:** Du sagst einmal, was dir wichtig ist („mit 70 noch reiten“, „abends ruhiger sein“), und die App zeigt dir jede Woche, welche deiner Messwerte dazu passen und ob du auf Kurs bist.

- Claude übersetzt Werte in 2–4 beobachtbare **Leitsignale** (z. B. Schlafregelmäßigkeit, Kraft-Einheiten pro Woche, Ruhepuls-Band) und formuliert sie als Richtung, nicht als Soll.
- Wöchentlich ein Satz je Wert, ohne Punkte oder Ampeln („Schlafzeiten diese Woche regelmäßiger als im Monatsschnitt“).
- Psychologischer Hintergrund: Ziele, die mit der eigenen Identität verknüpft sind, tragen länger als reine Zahlenziele (Schätzung aus Verhaltensforschung, kein PULSE-ONE-Beleg).
- **Prüfung:** alle ✓; K einmalig ca. 0,05 $, danach lokal.

| Wirkung | Machbarkeit | Kosten | Release |
|---|---|---|---|
| 4 | 4 | einmalig Cent-Betrag | R4 (Onboarding), R6 |

#### 9. Wenn-Dann-Pläne zum richtigen Moment (VP, CB)
**Alltag:** Statt allgemeiner Tipps bekommst du einen kleinen Plan, der genau dann auftaucht, wenn er hilft, zum Beispiel „Wenn du nach 22:30 noch am Handy bist, dann Licht dimmen und Ring-Atemübung“.

- Claude schlägt aus Coach Memory („mittwochs keine Zeit“) und Körperbiografie 1–3 **Wenn-Dann-Pläne** vor; nach Bestätigung laufen sie als **lokale Regeln** (kein Claude-Aufruf beim Auslösen).
- Auslöser: Uhrzeit, Sync-Ergebnis (kurze Nacht), Kalenderlücke (Idee 10), Ruhepuls-Abweichung. Höchstens 1 Hinweis pro Tag (wie RING-AUSWERTUNGEN §5.5).
- Wenn-Dann-Pläne gehören zu den am besten untersuchten Verhaltenstechniken; ihre Wirkung in PULSE ONE ist nicht belegt und wird über Annehmen/Ablehnen-Quote beobachtet.
- **Prüfung:** alle ✓; K Cent-Beträge beim Erstellen.

| Wirkung | Machbarkeit | Kosten | Release |
|---|---|---|---|
| 4 | 4 | Cent-Beträge | R4, R6 |

#### 10. Tag im Voraus mit dem Kalender (CB, SW)
**Alltag:** Morgens sieht die App, dass heute vier Termine und um 17 Uhr Reiten anstehen, und schlägt nach einer kurzen Nacht vor, wo eine Pause oder ein früheres Zubettgehen passt.

- Kalender über EventKit **nur lesen**, nur belegt/frei und selbst gewählte Schlüsselwörter („Reiten“, „Training“). Termintitel verlassen das iPhone nie; an Claude gehen höchstens „3 h Termine vormittags, Reiten 17–18 Uhr“.
- **Prüfung:** L ✓ (Titel bleiben lokal), D ✓, K 0 € (lokal) bzw. Teil des Morgentexts, M ✓.

| Wirkung | Machbarkeit | Kosten | Release |
|---|---|---|---|
| 3 | 4 | 0 € | R6 |

#### 11. Innere Uhr und „Wochenend-Jetlag“ (CB)
**Alltag:** Die App zeigt dir, wann dein Körper typischerweise am wachsten ist und wie stark sich deine Schlafzeiten zwischen Arbeitstagen und Wochenende verschieben.

- Lokal aus Schlafsitzungen: Schlafmitte an freien Tagen (Chronotyp-Schätzung nach Munich-Chronotype-Methode), Differenz Werktag/frei („sozialer Jetlag“), Schlafregelmäßigkeit. Später mit R09-Temperatur (nur nach Realtest) ein Tagesrhythmus.
- Claude formuliert Zeitfenster als **Beobachtung** („deine härtesten Einheiten mit gutem Gefühl lagen meist zwischen 16 und 19 Uhr“), nicht als Therapie.
- **Prüfung:** alle ✓, K 0 € lokal.

| Wirkung | Machbarkeit | Kosten | Release |
|---|---|---|---|
| 4 | 5 | 0 € | R2 (Kennzahlen), R3 (Deutung) |

#### 12. Monatsbrief und Jahreschronik (ST, DS)
**Alltag:** Einmal im Monat bekommst du einen kurzen, persönlichen Brief über deinen Körper, in dem jede Zahl antippbar belegt ist, und am Jahresende eine Chronik zum Durchblättern.

- Form: Brief statt Tabelle, max. 250 Wörter, drei Kapitel (Was war neu, was blieb stabil, eine Frage für nächsten Monat). Beleg-Chips wie im Bericht.
- Jahreschronik: 12 Briefe + Erkenntnis-Karten (Idee 5) + abgeschlossene Experimente, ehrlich inklusive Lücken („im Juli 9 Tage ohne Ring“).
- Kosten: Monatsanalyse bereits in Intelligence-Spec §4 (ca. 0,28 $); Brief ist eine andere Form desselben Laufs (Batch-API möglich, laut Anthropic 50 % günstiger).

| Wirkung | Machbarkeit | Kosten | Release |
|---|---|---|---|
| 3 | 5 | im bestehenden Monatsbudget | R3/R6 |

#### 13. Zwei Wege (Pfade statt Prognose) (ST, DE)
**Alltag:** Für ein Ziel zeigt die App zwei mögliche Wege anhand deiner eigenen bisherigen Wochen, etwa „so wie in deinen besten 4 Wochen“ und „so wie im Schnitt“, damit du siehst, was realistisch ist.

- Keine Vorhersage von Gesundheit oder Krankheit. Nur: „In Wochen mit ≥ 3 Bewegungseinheiten lag dein Ruhepuls im Median bei X“ (lokaler Fakt), daraus zwei Pfade mit sichtbarer Streuung.
- **DE-Auflage:** kein „biologisches Alter“, keine Lebenserwartung, keine Risikoprozente.

| Wirkung | Machbarkeit | Kosten | Release |
|---|---|---|---|
| 3 | 3 | gering | R6 |

---

### Gruppe C – Pferd und Sport

#### 14. Reiter-Pferd-Kopplung (Joker) (SW, DS)
**Alltag:** Nach dem Ausritt siehst du, in welchen Phasen dein Puls und der deines Pferdes eng zusammenlagen und wann einer von euch angespannter war.

- Zwei Polar H10 gleichzeitig (einer im **Polar Equine**-Gurt am Pferd), RR-Intervalle über das Standard-Herzfrequenzprofil bzw. Polar BLE SDK; Synchronisierung lokal (gleitende Korrelation der Herzfrequenz, Phasen aus GPS-Tempo).
- Claude beschreibt den Ritt („Im Trab lagen eure Werte eng beieinander, beim Galopp stieg dein Puls früher als der des Pferdes“), ohne Aussagen über Tiergesundheit.
- Forschung: Synchronisierung zwischen Pferd und Reiter messbar (Sci. Rep. 2025, Polar Equine; iScience 2024). H10 am Pferd im Stand gut validiert, in Bewegung mit Vorsicht.
- **Kosten (Schätzung, vor Kauf prüfen):** zweiter H10 und Equine-Gurt, zusammen grob 150–200 €; Software 0 €.
- **Voraussetzungen:** Pferdeprofil (Subjekt „Pferd“ wie im MyBody-Konzept), Zwei-Geräte-Verbindung, GPS-Aufzeichnung.

| Wirkung | Machbarkeit | Kosten | Release |
|---|---|---|---|
| 5 (für Johannes) | 2 | ca. 150–200 € Hardware (Schätzung) | nach R4, eigenes Sport-Welt-Modul |

#### 15. Atem-Schrittmacher mit Haptik (DS, SW)
**Alltag:** Eine sanfte Vibration führt dich durch ruhiges Atmen, und du siehst danach, wie sich dein Puls dabei verändert hat.

- Mit R03: geführte Atmung (ca. 6 Atemzüge/min) per Core Haptics, Puls vorher/nachher. **Echtes HRV-Biofeedback** erst mit H10 (RR-Intervalle in Echtzeit); der Ring kennt laut `docs/colmi-protokoll.md` zwar eine HRV-Live-Messung (Typ 10), aber keine fortlaufenden einzelnen RR-Intervalle (am R03 ungeprüft).
- Passt zur Heart Chamber (gleiche Haptik-Infrastruktur).

| Wirkung | Machbarkeit | Kosten | Release |
|---|---|---|---|
| 3 | 4 | 0 € | R4 (R03-Version), mit H10 erweitern |

#### 16. Schlafzimmer-Klima als eigener Sensor (CB, SW)
**Alltag:** Ein kleiner Raumsensor neben dem Bett misst Temperatur und Luftfeuchte, und die App zeigt, ob unruhige Nächte mit warmen Zimmern zusammenfallen.

- Xiaomi LYWSD03MMC mit offener pvvx-Firmware sendet per Bluetooth-Werbepaket, ohne Konto (bereits am 2026-11-19 vorgeschlagen). Neuer Adapter + Registry-Eintrag, kein Kernumbau.
- **Kosten:** wenige Euro je Sensor (Schätzung, Händlerpreis vor Kauf prüfen).

| Wirkung | Machbarkeit | Kosten | Release |
|---|---|---|---|
| 3 | 4 | wenige € einmalig | nach R2 |

---

### Gruppe D – Erlebnis: Spiel, Klang, Welten

#### 17. Saisons statt Streaks (GD, VP)
**Alltag:** Statt täglicher Serien, die bei einem verpassten Tag „reißen“, gibt es 6-wöchige Saisons mit einem Thema (z. B. „Schlafsaison“), die mit der Auswertung eines Experiments enden.

- Kein Bestrafen von Lücken; verpasste Tage sind normal und werden nicht rot markiert. Abschluss = Erkenntnis-Karte, nicht Punktestand.
- Verbindet Experiment-Labor (Idee 3) mit Motivation.

| Wirkung | Machbarkeit | Kosten | Release |
|---|---|---|---|
| 3 | 4 | 0 € | R4/R6 |

#### 18. Körperwelt als Wetterlandschaft (GD, DS, ST)
**Alltag:** Deine Woche erscheint als ruhige, sich verändernde Landschaft, bei der zum Beispiel Nebel für kurze Nächte steht, und ein Tipp darauf zeigt die echten Werte dahinter.

- Passt zu „ONE BODY. MANY WORLDS“ und R8 (Living Twin). Jedes Bildelement ist an genau einen lokalen Fakt gebunden (antippbar), keine Wertung durch Farben (keine Ampel).
- Technik: SwiftUI-Shader / MeshGradient / RealityKit laut `studio-graphics-3d`; Reduce Motion beachten.

| Wirkung | Machbarkeit | Kosten | Release |
|---|---|---|---|
| 3 | 3 | 0 € | R8 |

#### 19. Hör deine Woche (Sonifikation) (DS)
**Alltag:** Ein 20-Sekunden-Klang macht deine Woche hörbar: ruhige Nächte klingen tiefer, aktive Tage lebendiger, und das funktioniert auch mit geschlossenen Augen.

- AVAudioEngine-Synthese lokal; zugleich ein Barrierefreiheits-Gewinn (VoiceOver-Ergänzung zu Diagrammen; Apple bietet dafür Audio Graphs über `AXChartDescriptor`).

| Wirkung | Machbarkeit | Kosten | Release |
|---|---|---|---|
| 2 | 4 | 0 € | R8 |

#### 20. Siri, Widgets, Live-Aktivität (DS, KI)
**Alltag:** „Hey Siri, wie war meine Nacht?“ beantwortet die App mit einem Satz aus deinen Daten, und beim Reiten zeigt der Sperrbildschirm deinen Puls live.

- App Intents (lokale Antwort, optional Apple-KI), WidgetKit, ActivityKit. Keine Claude-Aufrufe über Siri (DE: kein Senden ohne sichtbare Freigabe).

| Wirkung | Machbarkeit | Kosten | Release |
|---|---|---|---|
| 3 | 4 | 0 € | R6/R8 |

---

### 4.9 Bewusst verworfen (DE-Veto oder fachlich unseriös)

| Idee | Warum nicht |
|---|---|
| „Biologisches Alter“ / Lebenserwartung | Keine belastbare Grundlage mit Ring-Daten; wirkt wie ein Befund. |
| Krankheits-Früherkennung („Infekt in 2 Tagen“) | Medizinproduktnähe, Studienlage gemischt; stattdessen nur persönliche Analogtage (Idee 2). |
| Stimmung oder Stress aus dem Stimmklang | Unzuverlässig, sehr persönlich; nur gesprochener Inhalt (Idee 4). |
| Blutdruck aus Ring-PPG | Ring liefert das nicht verlässlich; keine erfundenen Werte. |
| Ranglisten, Vergleich mit Fremden | Gegen „ruhig“ und „privat“; Vergleich nur mit dem eigenen Normalband. |
| Claude im Hintergrund ohne Freigabe (automatische Läufe ohne Budget) | Regel L und K; automatische Läufe nur mit Kostengrenze (wie Intelligence-Spec §2). |
| Eigener Server für „Rund-um-die-Uhr-KI“ | Neuer Empfänger von Gesundheitsdaten, Hosting-Kosten; erst bei Weitergabe an Dritte. |

---

## 5. Gesamtbewertung und Top 5

| # | Idee | Wirkung | Machbarkeit | Kosten | Release | Summe W+M |
|---|---|---|---|---|---|---|
| 1 | Zwei Gehirne + Gläserner Bote | 5 | 4 | 0 €, spart Kosten | R3/R6 | 9 |
| 2 | Körper-Detektiv mit Analogtagen | 5 | 4 | ca. 0,5–1 $/Monat | R2/R3 | 9 |
| 3 | Experiment-Labor | 5 | 4 | ca. 0,10 $/Versuch | R2–R4 | 9 |
| 11 | Innere Uhr & Wochenend-Jetlag | 4 | 5 | 0 € | R2/R3 | 9 |
| 4 | Abend-Sprachnotiz | 4 | 4 | 0 € | R2/R3 | 8 |
| 5 | Körperbiografie mit Verfallsdatum | 4 | 4 | 0 €, spart Token | R3/R6 | 8 |
| 6 | Zweite Meinung | 3 | 5 | ca. 0,01–0,03 $/Bericht | R3 | 8 |
| 8 | Werte-Kompass | 4 | 4 | Cent | R4/R6 | 8 |
| 9 | Wenn-Dann-Pläne | 4 | 4 | Cent | R4/R6 | 8 |
| 12 | Monatsbrief & Chronik | 3 | 5 | im Budget | R3/R6 | 8 |
| 7 | Foto als Datenquelle | 3 | 4 | Cent/Foto | R5/R7 | 7 |
| 10 | Tag im Voraus (Kalender) | 3 | 4 | 0 € | R6 | 7 |
| 15 | Atem-Schrittmacher | 3 | 4 | 0 € | R4 | 7 |
| 16 | Schlafzimmer-Klima | 3 | 4 | wenige € | nach R2 | 7 |
| 17 | Saisons statt Streaks | 3 | 4 | 0 € | R4/R6 | 7 |
| 14 | Reiter-Pferd-Kopplung | 5 | 2 | ca. 150–200 € (Schätzung) | nach R4 | 7 |
| 20 | Siri, Widgets, Live-Aktivität | 3 | 4 | 0 € | R6/R8 | 7 |
| 13 | Zwei Wege | 3 | 3 | gering | R6 | 6 |
| 18 | Körperwelt als Landschaft | 3 | 3 | 0 € | R8 | 6 |
| 19 | Hör deine Woche | 2 | 4 | 0 € | R8 | 6 |

**Top-5-Empfehlung** (nicht nur nach Summe, sondern danach, was die anderen Ideen trägt):

1. **Zwei Gehirne + Gläserner Bote** – Fundament: macht jede weitere KI-Funktion günstiger, privater und offline-fähig.
2. **Körper-Detektiv mit Analogtagen** – die eigentliche „neue Interpretation“: persönliche Muster statt Durchschnittsregeln.
3. **Experiment-Labor** – macht aus Vermutungen eigenes Wissen; stärkste Lebensanleitung ohne Bevormundung.
4. **Abend-Sprachnotiz** – liefert die Datenschicht, ohne die 2 und 3 nur halb so gut funktionieren.
5. **Körperbiografie mit Verfallsdatum** – sammelt die Ergebnisse von 2 und 3 dauerhaft und hält sie ehrlich aktuell.

Innere Uhr (11) ist gleich stark bewertet, aber kleiner im Umfang; sie passt als einfacher Baustein direkt in R2 und sollte dort mitlaufen.

---

## 6. Einbau in die Roadmap (Vorschlag, ohne laufende Arbeit zu stören)

| Release | Ergänzung aus dem Kreativlabor | Abhängigkeit |
|---|---|---|
| R2 Health Analytics | Notizen/Ereignisse als Datentyp (für Idee 4), Analogtag-Suche (2), Chronotyp & Wochenend-Jetlag (11), Blockstatistik für Experimente (3) | Basislinie R2-3, Schlafsitzungen R2-6 |
| R3 Claude Intelligence | `InsightProvider` mit zwei Implementierungen (Apple-KI, Claude) und Gläserner Bote (1), Hypothesen-Tafel (2), Experiment-Plan (3), Erkenntnis-Karten (5), Zweite Meinung (6) | Fakten + Validator R3 |
| R4 Coach | Werte-Kompass im Onboarding (8), Wenn-Dann-Pläne als lokale Regeln (9), Erinnerungen für Experimente, Atem-Schrittmacher (15), Saisons (17) | Onboarding R4 |
| R5/R7 | Foto-Pipeline für Labor/Plan (7) | Nutrition-Pipeline, Klinik-Freigabe |
| R6 Unified Coach | Kalender (10), Körperbiografie als Gesprächskontext (5), Monatsbrief (12), Zwei Wege (13), Siri (20) | Coach Memory |
| R8 Premium | Körperwelt (18), Sonifikation (19), Widgets/Live-Aktivität (20) | Designsystem 5.0 |
| Sportwelt Reiten | Reiter-Pferd-Kopplung (14) | H10 + Equine-Gurt gekauft, Zwei-Geräte-BLE |

Architektur-Hinweis für den Bau-Thread: Die Ideen brauchen nur **drei neue Kernbausteine** in `PulseCore`:
`ContextEvent` (Notiz/Stichwort mit Zeit und Herkunft „selbst gesagt“), `Insight` (Erkenntnis-Karte mit Belegen und Prüfdatum),
`Experiment` (Plan, Phasen, Auswertung). Alles andere setzt auf vorhandenen Fakten, Validator und SafetyRules auf.

---

## 7. Offene Fragen an Johannes (keine blockiert die laufende Arbeit)

1. Sollen die Top 5 so in die Roadmap (§6)?
2. Kalender lesen (Idee 10) und Sprachnotiz (Idee 4): grundsätzlich gewünscht?
3. Reiter-Pferd-Kopplung: Ist ein zweiter H10 mit Equine-Gurt später denkbar (Schätzung 150–200 €, Preis vor Kauf prüfen)?

---

## 8. Quellen (abgerufen 2026-11-20)

- Google Research, „The anatomy of a personal health agent“: https://research.google/blog/the-anatomy-of-a-personal-health-agent/ · arXiv 2508.20148: https://arxiv.org/pdf/2508.20148
- PHIA / Personal Health Insights Agent, arXiv 2406.06464 (Nature Communications 2026): https://arxiv.org/html/2406.06464v4
- WHOOP My Memory: https://www.whoop.com/us/en/thelocker/my-memory-whoop/ · Bericht: https://gadgetsandwearables.com/2026/05/08/whoop-memory/
- Oura Advisor: https://www.businesswire.com/news/home/20250331565896/en/
- Claude und Apple Health (Beta, USA): https://www.macrumors.com/2026/01/22/claude-ai-adds-apple-health-connectivity/ · https://thehackernews.com/2026/01/anthropic-launches-claude-ai-for.html
- Apple Foundation Models: https://developer.apple.com/documentation/foundationmodels · WWDC25 Session 286: https://developer.apple.com/videos/play/wwdc2025/286/ · Entwicklerforum: https://developer.apple.com/forums/topics/machine-learning-and-ai/machine-learning-and-ai-foundation-models
- Frühe Signale in Wearables: Nat. Med. 2021 https://www.nature.com/articles/s41591-021-01593-2 · Nat. Biomed. Eng. 2020 https://www.nature.com/articles/s41551-020-00640-6 · TemPredict/Fieber https://pmc.ncbi.nlm.nih.gov/articles/PMC10975930 · BMJ Open 2025 (CEDiD) https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11973797/
- N-of-1 mit Wearables: https://www.frontiersin.org/research-topics/76212/personalized-intervention-n-of-1-trials-using-wearable-devices · Methodik https://arxiv.org/pdf/2208.00739
- Pferd und Reiter: Sci. Rep. 2025 (doi 10.1038/s41598-025-29330-6) Zusammenfassung https://madbarn.com/research/child-horse-harmony-in-motion-a-preliminary-study-to-explore-heart-rate-synchronization-in-equine-assisted-therapy-for-neurotypical-and-adhd-children · iScience 2024 https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11414536/ · H10 am Pferd (Frontiers 2022) https://www.frontiersin.org/journals/veterinary-science/articles/10.3389/fvets.2022.939534/pdf · Polar am Pferd in Bewegung (Southampton 2010) https://eprints.soton.ac.uk/73248
