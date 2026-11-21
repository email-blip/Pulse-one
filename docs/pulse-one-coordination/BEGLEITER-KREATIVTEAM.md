# BEGLEITER – Kreativteam-Konzept: Smarter Wecker und Tagesbegleiter

Stand: 2026-11-21 · Status: **Ideensammlung / Konzept** (§14: Geplant) · Verfasser: Claude Code (Kreativteam = Perspektiven eines einzelnen Agenten, keine echten Fachleute)
Grundlage: Wunsch von Johannes (Wecker mit Klang, Wach-Messung, Begrüßung, Tagestipps, Wetter, Begleitung über Tag und Nacht) plus
`CREATIVE-LAB-2.md` (I1, P1, P17, I6, P2, P3, P7, I11, X1, X8). Kontext: `COACH-ENGINE-SPEC.md`, `CLAUDE-INTELLIGENCE-SPEC.md`,
`SPORT-UND-ALLTAG.md`, `DESIGN-SYSTEM-5.0.md`, `INTEGRATION.md`. Reine Doku, kein App-Code.

> **Spielregeln:** Nichts wird vorab gestrichen. Jede Idee trägt ein Etikett:
> **A** belastbar · **B** ansatzweise (bei dir prüfbar) · **C** wackelig (Prognose-Labor) · **D** braucht anderes Gerät/andere Technik.
> Ideen, die gegen eine harte Regel verstoßen, stehen mit **⚠ Regelkonflikt** da und mit einer erlaubten Umformulierung.

---

## 0. Kurzfassung (für das Handy)

**Was der Begleiter ist:** Ein Wecker, der dich mit einem eigenen, ruhig ansteigenden Klang weckt. Du tippst „Ich bin wach“,
der Ring misst 30–60 Sekunden, die Nacht wird nachgeladen, und eine Stimme begrüßt dich in höchstens 45 Sekunden:
Nacht, Tagesausblick, Wetter + Kleidung, drei kleine „Jetzt tun“-Schritte. Am Frühstückstisch misst der Ring ein zweites Mal.
Über den Tag kommen wenige, vorab geplante Hinweise (Essen, Koffein-Grenze, Bewegung, Sportfenster, Nickerchen, Schlafenszeit).

**Ehrliche Grenzen (iOS + Ring):**
- Die App läuft nicht dauerhaft im Hintergrund. Der Wecker klingelt über **AlarmKit** (ab iOS 26) wie der System-Wecker; ein Knopf öffnet die App.
- **Weck-Fenster „im Leichtschlaf“ geht mit dem R03 nicht zuverlässig** (Ring liefert Schlafphasen nur nachträglich) → Etikett D.
- „Sprechen über den Tag“ = **lokale Mitteilungen, morgens geplant**, bei jedem App-Öffnen neu geplant. Stimme = iOS-Sprachausgabe (kostenlos, lokal).
- Gesundheitsdaten bleiben auf dem iPhone. Claude nur optional, mit Vorschau. Wetter nur mit grobem Ort.

**Die 5 wichtigsten Entscheidungen:**
1. Release 1 läuft **komplett lokal und regelbasiert** (keine Claude-Kosten, keine Prognosen); Claude formuliert später optional.
2. Wecker = AlarmKit + eigener Klang „**Morgenquelle**“ (28 s WAV, prozedural erzeugt).
3. Begrüßung folgt **4 Tagestypen** (erholt / normal / kurze Nacht / auffälliges Muster) mit festen, geprüften Satzbausteinen.
4. Höchstens **3 Begleiter-Hinweise pro Tag**, gemeinsames Tageslimit 4 mit dem Coach, Ruhezeit ab Schlafenszeit-Fenster.
5. Prognosen (P1/P17), Körper-Tempo (P7) und Ärzte-Konferenz (I11) erst im **Prognose-Labor** nach Freigabe durch Johannes.

**Offene Entscheidungen bei Johannes:** §11.

---

## 1. Das Kreativteam (13 Perspektiven)

| # | Rolle | Konkrete Beiträge |
|---|---|---|
| 1 | **Schlafforscherin** | (a) Ringschlafphasen sind Schätzungen; Begrüßung nennt Dauer und Regelmäßigkeit zuerst, Phasen nur nebenbei. (b) „Kurze Nacht“ = mind. 1 h unter persönlichem Median, nicht unter einer Pauschale. (c) Schlafträgheit dauert 15–30 min → keine schweren Entscheidungen oder harten Zahlen in Minute 1. (d) Nickerchen 10–20 min, sonst Trägheit danach. |
| 2 | **Chronobiologe** | (a) Tageslicht in der ersten Stunde nach dem Aufwachen ist der stärkste Taktgeber (A). (b) Regelmäßige Weckzeit wichtiger als lange Wochenend-Nächte → Hinweis auf „sozialen Jetlag“ montags. (c) Schlafenszeit-Fenster rückwärts aus Weckzeit + persönlichem Schlafbedarf. (d) Koffein-Grenze an die geplante Schlafenszeit koppeln, nicht an eine feste Uhrzeit. |
| 3 | **Sportwissenschaftler** | (a) Sportfenster aus Erholung + Wetter + Zeitbudget, sportneutral (Lauf, Rad, Kraft, Rudern, Fußball, draußen, auch „kein Sport“). (b) Erholungssignale nach `COACH-ENGINE-SPEC` §6.2 übernehmen, nicht neu erfinden. (c) Morgen-Aktivierung ist kein Training: max. 2 Minuten, RPE ≤ 4. (d) Bei auffälligem Muster: Hauptaktivität „locker“ anbieten, Nutzer entscheidet. |
| 4 | **Ernährungswissenschaftlerin** | (a) Frühstücksfenster 30–120 min nach dem Aufwachen als Vorschlag, kein Muss (Fasten-Präferenz respektieren). (b) Letzte größere Mahlzeit 2–3 h vor dem Schlafenszeit-Fenster (B). (c) Wasser direkt nach dem Aufstehen als einfachster Schritt. (d) Brücke zum Tageskoch (`NUTRITION`), nicht doppelt bauen. |
| 5 | **Allgemeinmediziner (Sicherheit)** | (a) Jede Aussage zu Infekt-Mustern endet mit „Das ist keine Diagnose.“ (b) Nie „Du bist (nicht) krank“. (c) Warnzeichen (Brustschmerz, Atemnot, Ohnmacht, hohes Fieber) → immer „ärztliche Hilfe, Notruf 112“, nie Begleiter-Tipps. (d) Kalte Dusche/Klimmzüge nur, wenn kein Muster und keine Einschränkung im Profil. |
| 6 | **Sound-Designer** | (a) Eigener Weckklang „Morgenquelle“ (§2.2), prozedural, ≤ 30 s. (b) Kein Piepen, kein Sprung von leise auf laut. (c) Kurzer Bestätigungston bei „Ich bin wach“ und bei Messende (nach `studio-sound`, abschaltbar). (d) Sprachausgabe nach dem Klang, nie darüber. |
| 7 | **Voice-/UX-Writer** | (a) Begrüßung ≤ 110 Wörter (≈ 45 s). (b) Reihenfolge: Gruß → Nacht → Tag → Wetter → Jetzt tun → Ausblick. (c) Beschreibend, relativ zum eigenen Band, Aussagetyp sichtbar (gemessen/berechnet/Vorschlag). (d) Keine Wertungen („schlecht“, „katastrophal“), kein Ausrufezeichen-Dauerfeuer. |
| 8 | **Verhaltenspsychologin** | (a) Drei Schritte, nicht zehn; jeder abhakbar, Abhaken ist freiwillig. (b) Kein Nörgeln: ignorierte Hinweise werden seltener, nicht lauter. (c) „Wenn-dann“-Formulierung („Wenn du in der Küche bist: ein Glas Wasser“). (d) Wöchentlich fragen, welche Hinweise nerven → abschalten mit einem Tippen. |
| 9 | **Meteorologe** | (a) Open-Meteo (kostenlos, nicht kommerziell, Quellenangabe CC BY 4.0). (b) Kleidung aus „gefühlter Temperatur“ + Wind + Regenwahrscheinlichkeit + UV, nicht nur Lufttemperatur. (c) Schwüle/Hitze-Nacht-Warnung für den Abend (I6/P2). (d) Pollen nur, wenn Johannes Allergie im Profil markiert. |
| 10 | **Datenwissenschaftler** | (a) Normalband = `PersonalBaseline` (p25–p75, 28 Tage, mind. 7 Tage). (b) Mehrfachtest-Korrektur (Benjamini-Hochberg) im Nachtschicht-Forscher. (c) Prognose nur mit sichtbarer Trefferquote. (d) Datenlücken ehrlich: „unbekannt“ ist nie „gut“. |
| 11 | **Datenschutz-Berater** | (a) Standard: nichts verlässt das iPhone außer grober Wetter-Ort (2 Nachkommastellen ≈ 1 km oder gewählte Stadt). (b) Claude-Läufe nur mit Vorschau „Das wird gesendet“ + Analyseprotokoll. (c) Sprachausgabe lokal (`AVSpeechSynthesizer`), keine Cloud-Stimme. (d) Begrüßung auf dem Sperrbildschirm ohne Gesundheitswerte. |
| 12 | **iOS-Ingenieur (Realitätscheck)** | (a) AlarmKit ab iOS 26 hinter `if #available`; iOS 18–25: lokale Mitteilung mit Ton (≤ 30 s, respektiert Stummschalter/Fokus nicht wie ein Wecker). (b) Kein Dauerlauf im Hintergrund; `BGAppRefreshTask` nur „vielleicht“. (c) Ring-Live-Puls nur bei geöffneter App zuverlässig. (d) Info.plist-Texte (AlarmKit, Ort) trägt nur der Lead ein (`INTEGRATION.md`). |
| 13 | **Game-/Erlebnis-Designer** | (a) Morgen-Ritual statt Dashboard: ein Bildschirm, ein großer Knopf. (b) Prognose-Turnier als leises Spiel (Trefferquote), keine Ranglisten-Hetze. (c) Living Twin (X8) atmet morgens ruhig ein, „gedämpfter“ bei Muster, ohne Ampelfarbe. (d) Wochen-Fund des Nachtschicht-Forschers als „Fundstück“ am Montag. |

---

## 2. Das Weck-Erlebnis Minute für Minute

### 2.1 Ablauf

| Zeit | Was passiert | Technik / Grenze | Etikett |
|---|---|---|---|
| **Abend davor** | Begleiter fragt (oder übernimmt) Weckzeit, plant den AlarmKit-Wecker, zeigt Schlafenszeit-Fenster. Optional Prognose-Tipp (P1/P17). | AlarmKit-Alarm wird vorab geplant | A (Wecker), C (Prognose) |
| **T−30 min** | Nichts Aktives möglich. Idee „Lichtwecker“: smarte Lampe dimmt hoch. | App schläft; nur mit HomeKit-Szene/Automation des Nutzers | D (braucht Lampe) |
| **T−30 bis T** | Idee „Weck-Fenster im Leichtschlaf“. | Ring streamt keine Schlafphasen live, App läuft nicht → **nicht seriös baubar** mit R03 | D |
| **T** | „Morgenquelle“ klingt (28 s, wiederholt sich wie System-Wecker). Knöpfe: **„Ich bin wach“** (öffnet App) und „Schlummern 9 min“. | AlarmKit, Sekundär-Knopf öffnet App per App Intent (genaue API gegen Doku iOS 26 prüfen) | A |
| **T+0:10** | App öffnet: dunkler Bildschirm, ruhiger Atemkreis, Text „Guten Morgen, Johannes. Ich verbinde mich mit deinem Ring …“ Leiser Bestätigungston. | Bluetooth-Verbindung startet erst jetzt | A |
| **T+0:15–1:15** | **Wach-Messung 30–60 s**: Live-Puls (Ring-Echtzeitmessung), parallel Nacht-Sync (Schlaf, Nachtpuls, HRV, SpO₂, Schritte). Hinweis: „Bleib kurz sitzen, Hand ruhig.“ | R03 Live-Puls; QRing-App darf nicht verbunden sein | A (Puls), B (Ring-HRV unbelegt) |
| **T+1:15** | **Begrüßung** gesprochen (≤ 45 s) + als Karte lesbar. | `AVSpeechSynthesizer`, deutsche Stimme; Text vollständig lokal aus Bausteinen (§3) | A |
| **T+2** | **3 „Jetzt tun“-Karten** (§2.4), je abhakbar. | Regelwerk lokal | A/B |
| **T+2 bis +10** | Optional: Atemübung 2 min mit Haptik (Ring misst weiter, wenn App offen). | App vorne | B |
| **T+30–90** | **Frühstücks-Check**: Mitteilung „Am Tisch? 30 Sekunden Ring-Messung.“ Zweite Messung, Vergleich mit Wach-Messung. | geplante lokale Mitteilung; Messung nur, wenn Nutzer öffnet | B |
| **Frühstück + 1 h** | Tagesplan der Hinweise steht (§4), Koffein-Grenze und Schlafenszeit-Fenster sichtbar. Optionaler Kaffee-Hinweis bei verzögerter Variante (§2.4, C). | lokale Mitteilungen | A/B |

**Wach-Erkennung ohne Tippen** („App merkt selbst, dass ich wach bin“): Ring müsste Bewegung/Puls live an eine laufende App senden. Mit
Bluetooth-Hintergrundmodus theoretisch denkbar, aber unzuverlässig und akkuintensiv → **C/D**. Release 1: Tippen auf „Ich bin wach“ gilt als Aufwachzeit;
die nachträgliche Ring-Schlafkurve ergänzt die echte Aufwachzeit („Laut Ring warst du ab 6:41 wach“).

### 2.2 Weckklang „Morgenquelle“ (prozedural, 28 s WAV)

Ziel: wach machen ohne Schreck. Erzeugbar per Skript (z. B. Python/numpy oder Swift offline), 44,1 kHz, 16 bit, mono, ≤ 30 s
(Grenze für Mitteilungstöne; für AlarmKit-Ton gleiche Datei im App-Bundle, Format gegen Doku prüfen).

| Sekunde | Schicht | Beschreibung |
|---|---|---|
| 0–6 | **Grundton** | Weicher Sinus-Drone 110 Hz (A2) + Oktave 220 Hz leise, Einblendung −36 → −28 dBFS, langsames Tremolo 0,2 Hz („Atmen“). |
| 4–14 | **Tropfen** | Glockenartige FM-Töne (Träger:Modulator 1:3,5, Abklingzeit 1,5 s) auf A-Dur-Pentatonik (A3, C♯4, E4, F♯4, A4), zufällige Abstände 0,8–1,6 s, Seed fest → immer gleicher Klang. |
| 10–22 | **Aufstieg** | Tropfen wandern eine Oktave höher, dichter (0,4–0,8 s), gefiltertes Rauschen wie Luftzug (Tiefpass öffnet 400 Hz → 4 kHz). Lautheit steigt auf −14 dBFS. |
| 22–28 | **Ankommen** | Dreiklang A–C♯–E als weiche Fläche, Spitze −8 dBFS, letzte 1,5 s Ausblendung auf −20 dBFS, damit die Wiederholung nahtlos wirkt. |

Varianten (später, Personalisierung): „Morgenquelle“ (Standard), „Holz“ (Marimba-artig, trockener), „Weite“ (nur Fläche + Rauschen, sehr sanft).
Kein Vogelgezwitscher-Klischee, keine Sprache im Weckton. Etikett **A** (Klangdesign), Wirkung auf Aufwachqualität **C**.

### 2.3 Aufbau der Begrüßung (max. ~45 s, ≤ 110 Wörter)

1. **Gruß** (1 Satz): Name aus Profil, Tageszeit.
2. **Nacht** (1–2 Sätze, gemessen): Dauer relativ zum Median, Regelmäßigkeit; Phasen nur, wenn auffällig.
3. **Tag** (1 Satz, berechnet): Tagestyp in Worten, nie als Note.
4. **Muster-Zeile** (nur wenn nötig, §8): mit „Das ist keine Diagnose.“
5. **Wetter + Kleidung** (1–2 Sätze).
6. **Jetzt tun** (1 Satz mit 3 Schritten, Details auf Karten).
7. **Ausblick** (1 Satz): „Am Frühstückstisch messen wir noch einmal.“
Optional, nur als Karte (nicht gesprochen): Prognose-Abgleich, Körper-Tempo, Fund der Woche.

### 2.4 Katalog „Jetzt tun“ (Regeln wählen genau 3)

Regeln: Jeder Schritt ≤ 3 min. Mindestens einer ohne Anstrengung. Ausschlüsse haben Vorrang. Keine Wiederholung derselben drei an 3 Tagen in Folge.
Bei „auffälligem Muster“ nur Schritte mit Anstrengung „keine“.

| # | Schritt | Vorschlagen, wenn … | Nicht vorschlagen, wenn … | Etikett |
|---|---|---|---|---|
| 1 | **Glas Wasser** (300–500 ml) | immer möglich, Standard-Anker | – | A |
| 2 | **Tageslicht 5–10 min** (Fenster auf, Balkon, kurz raus) | Sonnenaufgang vor/um Weckzeit, Wetter trocken | Dunkelheit (dann: helles Licht drinnen) | A |
| 3 | **Kaltes Wasser ins Gesicht** (30 s) | erholt/normal, müde Wach-Messung | Muster, Kälteempfindlichkeit im Profil | B |
| 4 | **Kalter Dusch-Abschluss** (30–60 s) | erholt, Nutzer hat es aktiviert | Muster, Herz-Einschränkung im Profil, kurze Nacht | B |
| 5 | **5–15 Liegestütze** (auch an der Wand/Knien) | erholt/normal | Muster, Schulter-Einschränkung | A |
| 6 | **1–5 Klimmzüge oder Hängen 20 s** | Stange vorhanden (Profil), erholt | Muster, Schulter-Einschränkung | A |
| 7 | **10 Kniebeugen / Ausfallschritte** | normal/kurze Nacht (sanfte Aktivierung) | Knie-Einschränkung | A |
| 8 | **Mobilität 2 min** (Hüfte, Brustwirbelsäule, Nacken) | nach Sport-Vortag, langes Sitzen geplant | – | A |
| 9 | **Atmung 2 min** (z. B. 4 s ein, 6 s aus) | kurze Nacht, Muster, unruhige Wach-Messung | – | B |
| 10 | **Aktivierende Atmung 30 s** (schneller, durch die Nase) | erholt, müde | Muster, Schwindel bekannt | C |
| 11 | **Kaffee jetzt** | Gewohnheit, normal/kurze Nacht | später als Koffein-Grenze − 8 h | A |
| 12 | **Kaffee 60–90 min verzögern** („Adenosin-Idee“) | Nutzer hat Experiment gewählt | Standard: aus | **C** (Belege schwach, als N-of-1-Experiment anbieten) |
| 13 | **Extra starker Kaffee** | kurze Nacht, Nutzer-Wunsch | Muster mit erhöhtem Ruhepuls, Koffein-Grenze nah | B (Wirkung A, Schlaf-Nacheffekt bei dir prüfbar) |
| 14 | **Grüner Tee statt Kaffee** | Muster, erhöhter Ruhepuls, nachmittags | – | B |
| 15 | **Bett machen / Fenster lüften** | immer, „leichter Sieg“ | – | B |
| 16 | **Bewegter Weg** (Treppe statt Aufzug, 10 min gehen) | Arbeitsweg im Profil | Glätte/Unwetter | A |
| 17 | **Frühstück mit Eiweiß** | normal/erholt, Sport geplant | Fasten-Präferenz | B |

⚠ **Regelkonflikt vermeiden:** Keine Schritte als Therapie („gegen Infekt“). Formulierung immer „kann helfen, wacher zu werden“, nie „stärkt dein Immunsystem“.

### 2.5 Frühstücks-Check (zweite Messung)

- 30 s Live-Puls im Sitzen, 30–90 min nach dem Aufwachen. Vergleich mit Wach-Messung und eigenem Morgenband.
- Satzbeispiele: „Dein Puls ist seit dem Aufwachen von 64 auf 58 gesunken, so wie an deinen üblichen Morgen.“ /
  „Dein Puls liegt jetzt noch etwas über deinem üblichen Morgenwert. Plane den Vormittag ruhig.“
- Nutzen: zweiter Datenpunkt für Prognose und Infekt-Muster, unabhängig von Wach-Aufregung. Etikett **B** (persönlich prüfbar).
- Optional: 1 Frage „Wie fühlst du dich? 1–5“ → subjektives Signal für Coach §6.2.

---

## 3. Begrüßungs-Bausteine (4 Tagestypen)

**Klassifikation (lokal, berechnet):** Basis `PersonalBaseline` (28 Tage). Weniger als 7 Tage → Typ „Band bildet sich“ (nur beschreiben, keine Wertung).

| Tagestyp | Regel (Beispiel, in `BegleiterRules` mit Tests) |
|---|---|
| **erholt** | Schlafdauer ≥ Median, Nachtruhepuls ≤ Median, HRV ≥ Median (falls vorhanden), kein Signal §6.2 |
| **normal** | alle Werte im Band, höchstens 1 knapp außerhalb |
| **kurze Nacht** | Schlafdauer < Median − 1 h, Ruhepuls/HRV im Band |
| **auffälliges Muster** | Nachtruhepuls 2 Nächte über Band (p75 + 0,5 × IQR) **und** HRV 2 Nächte unter Band (oder R09: Temperatur über Band, §8) |

### 3.1 Typ „erholt“

> „Guten Morgen, Johannes. Du hast 7 Stunden 50 geschlafen, eine halbe Stunde mehr als üblich, und ruhig: dein Nachtpuls lag am unteren Rand deines Bereichs.
> Dein Körper wirkt heute gut erholt. Draußen sind es 8 Grad, gefühlt 5, ab Mittag sonnig: Jacke für den Morgen, später reicht ein Pullover.
> Für einen wachen Start: ein Glas Wasser, kaltes Wasser ins Gesicht und zehn Liegestütze. Wenn du heute Sport machen willst: der späte Nachmittag ist trocken und mild.
> Am Frühstückstisch messen wir noch einmal.“

### 3.2 Typ „normal“

> „Guten Morgen, Johannes. 7 Stunden 10 Schlaf, das ist dein üblicher Bereich. Puls und Erholung liegen ebenfalls im Normalband.
> Ein ganz gewöhnlicher Tag, gut für dein normales Programm. Heute 14 Grad mit Schauern ab 15 Uhr: Regenjacke einpacken.
> Jetzt: Fenster auf und fünf Minuten Tageslicht, ein Glas Wasser, zwei Minuten Mobilität. Dein Kaffee passt gut bis 14 Uhr.“

### 3.3 Typ „kurze Nacht“

> „Guten Morgen, Johannes. Die Nacht war kurz: 5 Stunden 40, gut anderthalb Stunden unter deinem Üblichen. Dein Ruhepuls liegt trotzdem in deinem Bereich.
> Heute ist ein Tag für einen ruhigeren Takt: wichtige Dinge eher an den Vormittag. Draußen 3 Grad und Wind, gefühlt minus 1: Mütze und warme Jacke.
> Jetzt: Wasser, Tageslicht und ein starker Kaffee, wenn du magst. Gegen 13:30 schlage ich dir ein Nickerchen von 15 Minuten vor, und heute Abend ein früheres Schlafenszeit-Fenster ab 22:15.“

### 3.4 Typ „auffälliges Muster“ (Ruhepuls 2 Nächte über Band + HRV darunter)

> „Guten Morgen, Johannes. Du hast 7 Stunden geschlafen. Dein Ruhepuls liegt seit zwei Nächten über deinem üblichen Bereich, deine Herzratenvariabilität darunter.
> So ein Muster sehe ich bei dir manchmal nach intensiven Tagen, nach Alkohol oder vor einem Infekt. Das ist keine Diagnose.
> Geh es heute langsamer an: Training eher locker oder Pause, viel trinken, früh ins Bett. Draußen 6 Grad und nass: zieh dich warm an.
> Jetzt: ein Glas Wasser, zwei Minuten ruhig atmen, und gern grüner Tee statt extra starkem Kaffee. Wenn du dich krank fühlst oder Fieber hast, lass es ärztlich abklären.“

**Kurzform für Tage ohne Muster** (Johannes’ Wunschsatz, regelkonform umformuliert):
> „Deine Nachtwerte liegen in deinem üblichen Bereich, ein Infekt-Muster sehe ich heute nicht. Das ist keine Diagnose.“
⚠ Nicht erlaubt: „Du bist nicht krank.“ / „Deine Werte sehen gesund aus.“ / „Dein Immunsystem kämpft.“

### 3.5 Wetter- und Kleidungszeilen (Bausteine)

| Bedingung (gefühlte Temp., Wind, Regen-%, UV) | Satz |
|---|---|
| < 0 °C | „Gefühlt minus {x} Grad: Mütze, Handschuhe, warme Jacke.“ |
| 0–8 °C | „Gefühlt {x} Grad: warme Jacke, Schal hilft.“ |
| 9–15 °C | „{x} Grad: Übergangsjacke oder Pullover.“ |
| 16–22 °C | „Angenehme {x} Grad: leichte Kleidung, für den Abend eine Schicht mehr.“ |
| > 22 °C | „Warm, bis {x} Grad: luftige Kleidung, Wasser mitnehmen.“ |
| Regen ≥ 50 % | „Ab {Uhrzeit} wahrscheinlich Regen: Regenjacke oder Schirm.“ |
| Wind ≥ 40 km/h | „Böig: winddichte Jacke statt Schirm.“ |
| UV ≥ 6 | „Starke Sonne mittags: Sonnenschutz.“ |
| Schwüle Nacht erwartet (I6/P2) | „Heute Nacht wird es schwül. Bei dir waren solche Nächte bisher meist unruhiger: Schlafzimmer früh lüften.“ (B, erst nach ≥ 5 vergleichbaren Nächten) |

Ort: grob (Stadt oder 2 Nachkommastellen). Quelle sichtbar: „Wetterdaten: Open-Meteo.com“.

### 3.6 Prognose-Abgleich (P1 + P17, nur mit Prognose-Labor, C)

> „Gestern Abend tippte ich auf einen Ruhepuls von 56 bis 60. Gemessen: 58. Eingetroffen. Meine Trefferquote der letzten 30 Tage: 21 von 30.“
> „Du hattest auf ‚höher als üblich‘ getippt, ich auf ‚üblich‘. Diesmal lagst du richtig. Stand im Turnier: du 12, Rechenmodell 15, Claude 13.“
> „Nicht eingetroffen: erwartet 56 bis 60, gemessen 64. Ich lerne daraus, ein späteres Abendessen gestern war bei dir bisher öfter mit höherem Nachtpuls verbunden.“

### 3.7 Körper-Tempo-Zeile (P7, C, nur Karte, nicht gesprochen)

> „Körper-Tempo (experimentell): Dein 4-Wochen-Trend entspricht etwa 41 bis 45 Jahren, leicht jünger als im Vormonat. Nur eine Annäherung.“

### 3.8 Fund der Woche (Nachtschicht-Forscher, montags)

> „Fund der Woche: An Tagen mit mehr als 8.000 Schritten war dein Nachtpuls im Schnitt 3 Schläge niedriger (42 Tage, Zusammenhang, keine Ursache). Willst du es zwei Wochen gezielt testen?“

---

## 4. Tagesbegleiter (Tag und Nacht)

### 4.1 Technik

- Morgens nach der Begrüßung: Regelwerk erzeugt einen **Tagesplan der Hinweise** → `UNUserNotificationCenter`, lokale Zeit-Auslöser.
- **Neu planen bei jedem App-Öffnen** (neue Ringdaten, Wetter, abgehakte Schritte) und optional per `BGAppRefreshTask` (iOS entscheidet, wann; kein Versprechen).
- Hinweise sind **vorgeplant**, nicht reaktiv. „Du sitzt seit 90 Minuten“ geht nicht live → stattdessen feste Bewegungs-Snacks, die beim Öffnen gestrichen werden, wenn die Schritte schon da sind.
- Mitteilungstexte auf dem Sperrbildschirm **ohne Gesundheitswerte** („Zeit für eine kurze Bewegungspause“), Details erst in der App.

### 4.2 Tageslinie möglicher Hinweise (Beispiel: Weckzeit 6:30, Schlafbedarf 7 h 45, Schlafenszeit-Fenster 22:15–22:45)

| Uhrzeit (Beispiel) | Hinweis | Regel | Etikett |
|---|---|---|---|
| 6:30 | Wecker + Begrüßung | AlarmKit | A |
| 7:15 | Frühstücks-Check | 30–90 min nach Wach | B |
| 8:00–9:00 | (verzögerter Kaffee, nur im Experiment) | Weckzeit + 60–90 min | C |
| 10:30 | Bewegungs-Snack 2 min | wenn Sitztag (Profil) und < 1.500 Schritte bis Öffnen | A |
| 12:00–13:00 | Mittagsfenster | 4–6 h nach Frühstück | B |
| 13:30 | **Nickerchen 10–20 min** | nur Tagestyp „kurze Nacht“, spätestens 15:00 und ≥ 7 h vor Schlafenszeit | B |
| 14:15 | **Koffein-Grenze** | Schlafenszeit − 8 h (persönlich anpassbar, später via Koffein-Fingerabdruck) | B |
| 16:30–18:30 | **Sportfenster** | Wetter trocken/mild + Erholung (Coach §6.2) + Zeitbudget; sportneutral: „Gut für deine Einheit draußen“ oder „drinnen besser“ | B |
| 19:30 | Letzte größere Mahlzeit | Schlafenszeit − 2,5 h | B |
| 21:30 | **Runterfahren** (Licht dimmen, Bildschirm weg, Zimmer lüften) | Schlafenszeit − 45 min; zählt als letzter Hinweis | B |
| 22:15 | Schlafenszeit-Fenster (nur auf Wunsch als Hinweis) | Weckzeit − Schlafbedarf − 15 min Einschlafzeit | A (Rechnung), B (persönlicher Bedarf) |
| Nacht | **Stille.** Ring zeichnet auf; Nachtschicht-Forscher rechnet nur, wenn die App offen/aktiv ist oder per Hintergrundaufgabe | – | A |

**Schlafbedarf:** Median der Schlafdauer in Nächten vor „erholt“-Tagen (mind. 10 solche Nächte), sonst Vorgabe 7 h 30, vom Nutzer änderbar.

### 4.3 Grenzen und Ruheregeln

- **Höchstens 3 Begleiter-Hinweise pro Tag** (Wecker und Frühstücks-Check zählen nicht). Gemeinsames Tageslimit mit Coach: **4** (`COACH-ENGINE-SPEC` §6.5). Bei Konflikt gewinnt: Sicherheit > Schlafenszeit > Koffein-Grenze > Sport > Essen > Bewegung.
- **Ruhezeit:** ab Schlafenszeit-Fenster − 45 min bis Weckzeit (ersetzt die starre 21–7-Vorgabe, wenn der Begleiter aktiv ist). Fokus-Modi respektieren, keine „zeitkritischen“ Mitteilungen.
- **Kein Nörgeln:** Hinweisart 3× hintereinander ignoriert → eine Woche Pause für diese Art, dann einmal fragen „Weiter erinnern?“.
- Jede Hinweisart einzeln abschaltbar; Wochenende eigener Plan (andere Weckzeit, weniger Hinweise).
- Tagestyp „auffälliges Muster“: keine Sport-Hinweise, nur Trinken, Ruhe, früher Schlaf.

---

## 5. Ärzte-Konferenz (I11) – Vorschlag: Name „Expertenrunde“

⚠ **Regelkonflikt Name:** „Ärzte-Konferenz“ suggeriert ärztlichen Rat. Vorschlag UI-Name **„Expertenrunde“** oder **„Vier Blickwinkel“**, Untertitel „KI-Rollen, keine Ärzte“.

| Rolle | Schaut auf | Ton |
|---|---|---|
| **Herz-Stimme** | Ruhepuls, Nacht- und Wachpuls, HRV (Methode beachten, Ring-HRV unbelegt), Frühstücks-Check-Verlauf | ruhig, präzise, vorsichtig |
| **Schlaf-Stimme** | Dauer, Regelmäßigkeit, Einschlafzeit, Phasen (Schätzung), SpO₂-Nacht (R03 nur grob) | erklärend, geduldig |
| **Sport-Stimme** | Belastung (sRPE), Schritte, Erholungssignale, Sportfenster; sportneutral nach Profil | anpackend, nie drängend |
| **Ernährungs-Stimme** | Mahlzeitenzeiten, Koffein, Alkohol-Notizen, Trinken, Tageskoch-Daten | alltagsnah |
| **Synthese (Moderation)** | führt zusammen, löst Widersprüche oder benennt sie | knapp |

**Ablauf:** (1) Lokal: Kontext bauen (Tageswerte, Bänder, Notizen; keine Namen/Orte/Gerätenummern) → **Vorschau „Das wird gesendet“** → Freigabe.
(2) Claude: je Rolle ein kurzer Beitrag (strukturiertes JSON, Aussagetyp je Satz). (3) Synthese. (4) Lokale `SafetyRules` prüfen jeden Satz (Diagnosebegriffe, Ursachenbehauptungen, Therapie → verwerfen).

**Uneinigkeit sichtbar:** Eigener Block „Hier sind wir uns nicht einig“, z. B.
> Sport-Stimme: „Erholung reicht für eine lockere Einheit.“ · Herz-Stimme: „Ruhepuls noch über Band, eher Pause.“ · **Synthese:** „Beides vertretbar. Wenn du trainierst: kurz und locker, Abbruch bei ungewohnt hohem Puls.“

**Synthese-Format:** 3 Beobachtungen (mit Beleg-Chips) · 1 Uneinigkeit (falls vorhanden) · 2–3 Vorschläge (Typ „Vorschlag“) · 1 offene Frage an Johannes · ggf. Karte „Ärztliche Abklärung“.
**Wann:** auf Knopfdruck („Expertenrunde fragen“) + optional sonntags als Wochenrunde (einmal einschalten, jede Woche Vorschau bestätigen oder dauerhaft freigeben).
**Kosten:** Schätzung 0,30–0,80 $ je Runde (CREATIVE-LAB-2). Etikett **B**. Nie Teil der morgendlichen Begrüßung (Tempo + Kosten).

---

## 6. Nachtschicht-Forscher (I1)

**Grundsatz:** Release-Version rechnet **lokal in Swift** (kostenlos, nichts verlässt das iPhone). Die ursprüngliche Idee mit Claude Code Execution
(anonymisierte Tagestabelle, Vorschau, Freigabe, Schätzung 0,50–3 $/Lauf) bleibt als Ausbaustufe.

**Gescannte Paare (zeitversetzt):**

| Tag X (Einfluss) | Nacht/Tag X+1 (Ergebnis) | Versatz |
|---|---|---|
| Schritte, Aktivminuten, Sport-Uhrzeit, sRPE | Nachtruhepuls, HRV, Schlafdauer, Einschlafzeit | 0 und +1 Nacht |
| Koffein-Letztzeit, Alkohol-Notiz, späte Mahlzeit | dieselben | +1 Nacht |
| Wetter: Nachttemperatur, Schwüle, Luftdruck-Sprung | Schlafdauer, Wachphasen | gleiche Nacht |
| Zeit draußen (Notiz/Health), Tageslicht-Schritt erledigt | Schlaf, Morgenpuls | +1 Nacht |
| Weckzeit-Abweichung (sozialer Jetlag) | Montagswerte | Wochenende → Montag |
| „Jetzt tun“-Schritte erledigt | Frühstücks-Check-Puls, Selbstauskunft | gleicher Tag |
| Nickerchen ja/nein | Einschlafzeit, Nachtpuls | gleiche Nacht |

**Mindestdaten:** ≥ 42 Tage mit Daten; jede Bedingung mit ≥ 8 Tagen „ja“ und ≥ 8 „nein“ (bzw. ≥ 30 Wertepaare bei stetigen Größen).
**Statistik:** Spearman-Korrelation bzw. Mittelwertunterschied mit Bootstrap-Intervall; **Benjamini-Hochberg, FDR 10 %** über alle Tests eines Laufs;
Mindesteffekt (z. B. ≥ 2 Schläge/min oder ≥ 20 min Schlaf); Gegenprobe: Effekt muss in erster **und** zweiter Datenhälfte gleiche Richtung haben.
Wochentag als Störgröße prüfen (Funde, die nur „Wochenende“ sind, verwerfen oder so benennen).

**Formulierung:**
- „In deinen Daten fiel auf: …“ + Zahl + Stichprobengröße + „Zusammenhang, keine Ursache.“
- Immer ein Angebot: „Willst du es als Experiment testen?“ (N-of-1 aus `SPORT-UND-ALLTAG` §2).
- Nie: „X verursacht Y“, „Du solltest nie wieder …“.
- Ohne Fund: „Diese Woche nichts Belastbares gefunden. Das ist auch ein Ergebnis.“
Etikett **B** (Methode A, Funde bei kleinen Stichproben oft instabil).

---

## 7. Körper-Tempo (P7) – offene Formel, Etikett C

⚠ **Regelkonflikt:** `SPORT-UND-ALLTAG` §1.5 sagt „kein universeller Score“. Daher nur im **Prognose-Labor**, standardmäßig aus, nie in der Begrüßung gesprochen, nie täglich (nur 28-Tage-Trend).

**Formel-Vorschlag (alles 28-Tage-Mediane, Ergebnis als Spanne ±2 Jahre):**

```
Körper-Tempo = Kalenderalter + Σ Beitrag_i   (Summe begrenzt auf ±10 Jahre)

Beitrag Ruhepuls   = 0,35 × (Ruhepuls − 60) / 5 × 3 Jahre     (5 Schläge über 60 → +2,1 J.)
Beitrag Schritte   = 0,25 × (7.500 − Schritte) / 2.500 × 3 J.   (begrenzt ±3 J.)
Beitrag Schlaf     = 0,25 × (|Schlafdauer − 7,5 h| / 1 h + Regelmäßigkeits-Abweichung / 60 min) × 2 J.
Beitrag Aktivität  = 0,15 × (150 − Aktivminuten/Woche) / 75 × 2 J.   (begrenzt ±2 J.)
HRV                = nicht enthalten (Ring-HRV unbelegt, altersabhängig, Methode unklar)
```

Gewichte grob angelehnt an öffentliche Ansätze (Google „Coachable Health Age“: Ruhepuls, Schritte, Schlaf, Aktivminuten); Zahlen sind **Schätzungen des Teams**, nicht validiert.
Formel in der App aufklappbar („So rechne ich“), jeder Beitrag einzeln sichtbar.

**Wortlaut:** „Körper-Tempo (experimentell): Dein Trend der letzten vier Wochen entspricht etwa {a} bis {b} Jahren. Größter Beitrag: Schritte.
Das ist eine grobe Annäherung, keine medizinische Aussage.“ · Nie: „Du bist biologisch 50.“ / „Du alterst schneller.“

---

## 8. Infekt-Frühwarnung (P3)

**Signale (je relativ zum persönlichen 28-Tage-Band):**

| Signal | Schwelle | R03 | R09 |
|---|---|---|---|
| Nachtruhepuls | > p75 + 0,5 × IQR | ✓ | ✓ |
| HRV | < p25 − 0,5 × IQR (gleiche Methode) | ✓ (B, unbelegt) | ✓ |
| Hauttemperatur-Abweichung nachts | > Band + 0,5 °C (Wert gegen Realtest prüfen) | – | ✓ (erst nach Realtest behaupten) |
| Schlafdauer/Unruhe | Wachphasen deutlich über Band | ✓ (C) | ✓ (C) |
| Frühstücks-Check | Morgenpuls bleibt über Band | ✓ | ✓ |
| Selbstauskunft | „fühle mich krank“, Halskratzen | Notiz | Notiz |

**Regeln:**
- **Ohne Temperatur (R03):** Stufe 2 erst bei Ruhepuls über Band **in 2 Nächten** + mindestens 1 weiteres Signal (HRV, Frühstücks-Check oder Selbstauskunft). Etikett **B−** (mehr Fehlalarme: Alkohol, Training, Stress sehen gleich aus).
- **Mit R09:** Stufe 2 bei 2 von 3 (Ruhepuls, HRV, Temperatur) in 2 Nächten. Etikett **B**.
- Bekannte Ursache in Notizen (Alkohol, harter Wettkampf, Reise) → Wortlaut nennt sie als mögliche Erklärung.
- Analogtag-Vergleich („so sah es vor deiner Erkältung im März aus“) nur, wenn eine frühere Episode vom Nutzer **selbst markiert** wurde.

**Wortlaut-Leiter:**

| Stufe | Auslöser | Satz |
|---|---|---|
| 0 | nichts | „Deine Nachtwerte liegen in deinem üblichen Bereich, ein Infekt-Muster sehe ich heute nicht. Das ist keine Diagnose.“ (nur auf Nachfrage oder 1×/Woche, nicht täglich) |
| 1 | 1 Signal, 1 Nacht | „Dein Ruhepuls lag heute Nacht etwas über deinem Bereich. Einzelne Nächte schwanken; ich schaue morgen wieder.“ |
| 2 | Regel oben erfüllt | „Ruhepuls und Erholung weichen seit zwei Nächten von deinem Üblichen ab. So ein Muster kann nach Belastung, Alkohol oder vor einem Infekt auftreten. Das ist keine Diagnose. Geh es heute langsamer an.“ |
| 3 | Stufe 2 ≥ 4 Nächte **oder** + Fieber/Symptome **oder** SpO₂-Nacht wiederholt deutlich unter Band | „Diese Abweichung hält seit mehreren Tagen an. Wenn du dich krank fühlst oder unsicher bist, lass es ärztlich abklären.“ + Karte „Ärztliche Abklärung“ (Stethoskop-Symbol, kein Rot) |
| Notfall | Selbstauskunft Brustschmerz, Atemnot, Ohnmacht | „Bei diesen Beschwerden ruf bitte ärztliche Hilfe, im Notfall 112.“ – keine weiteren Begleiter-Tipps |

⚠ Nicht erlaubt: „Du wirst krank“, „Du hast einen Infekt“, „Nimm Vitamin C/Zink“, Farbwechsel nach Rot. Living Twin (X8) darf „gedämpfter“ atmen, ohne Farbe als Alarm.

---

## 9. Personalisierung und Namen

**Modulname (UI), Vorschläge:**

| Name | Wirkung | Bemerkung |
|---|---|---|
| **Begleiter** | warm, klar | Arbeitstitel, Favorit des Teams |
| **Morgenquelle** | poetisch, an den Weckklang gekoppelt | gut für den Wecker-Teil allein |
| **Tageslotse** | aktiv, führend | betont den Tag |
| **PULSE Morgen** | Markenbezug | knapp, sachlich |
| **Wachwerk** | verspielt | evtl. zu technisch |

Vorschlag: Modul „**Begleiter**“, Wecker darin heißt „**Morgenquelle**“.

**Stimme:** iOS-Systemstimmen Deutsch (Standard/erweitert/Premium, falls vom Nutzer geladen), weiblich/männlich nach Verfügbarkeit; Tempo 0,9–1,1;
„Stimme testen“-Knopf. Personal Voice (eigene Stimme) nur, wenn API und Freigabe es erlauben (Doku prüfen, C). Ohne Ton: Begrüßung als Text + Haptik.

**Tonfall (Einstellung):**

| Stil | Beispiel „kurze Nacht“ |
|---|---|
| **sachlich** | „5 h 40 Schlaf, 1 h 30 unter deinem Median. Ruhepuls im Band. Vorschlag: Nickerchen 13:30, Schlafenszeit ab 22:15.“ |
| **motivierend** | „Kurze Nacht, aber dein Herz ist ruhig. Mit Licht, Wasser und einem guten Kaffee holen wir das Beste aus dem Tag.“ |
| **knapp** | „Kurze Nacht. Puls okay. Licht, Wasser, Kaffee. Nickerchen 13:30.“ |

Weitere Schalter: Name in der Anrede (ja/nein), Wetter an/aus, Prognose-Labor an/aus, Körper-Tempo an/aus, Sport-Hinweise an/aus,
Wochenend-Modus, Klimmzugstange/Dusche/Garten vorhanden (für „Jetzt tun“), Einschränkungen aus Profil.

---

## 10. Rangliste: Was zuerst gebaut wird

**Release 1 des Moduls („Begleiter 1“, lokal, 0 €):**

| Rang | Baustein | Etikett | Hinweis |
|---|---|---|---|
| 1 | Tagestyp-Regeln + Satzbausteine (`BegleiterRules`, Swift Testing) | A | Kern, testbar ohne Ring |
| 2 | Wecker via AlarmKit + Fallback-Mitteilung (iOS 18–25) + „Ich bin wach“ | A | Info.plist-Text über Lead |
| 3 | Weckklang „Morgenquelle“ (Skript erzeugt WAV, im Bundle) | A | |
| 4 | Wach-Bildschirm: Ring verbinden, Nacht-Sync, 30–60 s Live-Puls | A | braucht echten R03-Test |
| 5 | Begrüßung gesprochen (`AVSpeechSynthesizer`) + Karte mit Aussagetypen | A | |
| 6 | „Jetzt tun“-Katalog mit Regeln (ohne Schritt 12) | A/B | |
| 7 | Tagesplan der Hinweise (≤ 3/Tag), Koffein-Grenze, Schlafenszeit-Fenster, Nickerchen-Regel | B | gemeinsames Limit mit Coach |
| 8 | Frühstücks-Check | B | |
| 9 | Infekt-Leiter Stufe 0–3 nur mit R03-Signalen | B− | Wortlaut von SafetyRules geprüft |
| 10 | Wetter + Kleidung (Open-Meteo, grober Ort) | A | **neuer Netzwerk-Endpunkt → Freigabe nötig** |

**Release 2 (lokal, Prognose-Labor):**

| Baustein | Etikett |
|---|---|
| Nachtschicht-Forscher lokal (Wochen-Fund) | B |
| P1 Morgen-Vorhersage lokal + Abgleich | C |
| P17 Prognose-Turnier (du vs. Rechenmodell; Claude später) | C |
| I6/P2 Schwüle-/Hitze-Nacht-Hinweis aus eigener Historie | B |
| P7 Körper-Tempo | C |
| Kaffee-Verzögerung als N-of-1-Experiment | C |
| R09-Temperatur in der Infekt-Leiter (nach Realtest) | B / D bis Gerät da |

**Release 3 (Claude, mit Vorschau und Kosten-Budget):**

| Baustein | Etikett |
|---|---|
| X1 Begrüßung von Claude formuliert (aus lokalen Fakten, ca. 0,02 $/Tag) | A |
| I11 Expertenrunde (auf Knopfdruck + Wochenrunde) | B |
| I1 Nachtschicht-Forscher mit Code Execution (monatlich, anonymisiert) | B |
| P17 mit Claude als drittem Tipper | C |
| X8 Living Twin reagiert auf Tagestyp | A (Darstellung) |

**Später / anderes Gerät:**

| Baustein | Etikett |
|---|---|
| Weck-Fenster im Leichtschlaf | D (bräuchte Live-Schlafphasen, z. B. Apple Watch) |
| Wach-Erkennung ohne Tippen | C/D |
| Lichtwecker über HomeKit-Lampe | D |
| Reaktive „Du sitzt zu lange“-Hinweise in Echtzeit | D (App läuft nicht dauerhaft) |
| SpO₂-Nacht-Muster belastbar | D (Fingerclip-Oximeter) |

---

## 11. Offene Entscheidungen bei Johannes

1. **Prognosen:** `INTEGRATION.md` sagt „keine Prognosen“. P1/P17/P7 nur im Prognose-Labor – einschalten ja/nein, Standard an oder aus?
2. **Wetter:** Open-Meteo wäre ein neuer Netzwerk-Endpunkt (bisher nur Claude und Open Food Facts/USDA). Freigabe mit grobem Ort?
3. **Name:** „Ärzte-Konferenz“ → „Expertenrunde“? Modulname „Begleiter“, Wecker „Morgenquelle“?
4. **Ruhezeit:** feste 21–7 Uhr (Coach) oder dynamisch ab Schlafenszeit-Fenster?
5. **Claude im Morgen:** täglich automatisch formulieren lassen (≈ 0,60 $/Monat, nach einmaliger Freigabe) oder nur lokale Bausteine?
6. **Begleiter vs. Coach:** eigener Tab-Bereich oder Teil von „Heute“/„Coach“? (Vorschlag: Karte auf „Heute“ + Einstellungen im Coach.)
