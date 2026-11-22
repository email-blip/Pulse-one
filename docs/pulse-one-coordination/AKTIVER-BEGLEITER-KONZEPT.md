# PULSE ONE als aktiver KI-Begleiter – Gesamtkonzept

Stand: 2026-11-22 · Status: **Konzept, nichts davon ist gebaut** · Auftraggeber: Johannes
Anlass: Johannes (22.11.): „Wenn ich die App aufmache, stehen da einfach nur Werte … Ich wollte eigentlich etwas, wo die KI die Werte stetig prüft, ohne dass ich etwas absenden muss.“ Leitbild (22.11.): ein persönlicher KI-Begleiter wie der Assistent aus *QualityLand* (Marc-Uwe Kling), der einen stets begleitet.

---

## 1. Wie die App heute funktioniert (in einfachen Worten)

1. **Daten kommen rein.** Der Ring (Colmi R03) misst Puls, HRV, SpO₂, Schritte, Schlaf und speichert sie auf sich selbst. Die App holt sie ab, **aber nur, solange PULSE ONE geöffnet ist**. Apple Health liefert zusätzlich Schlaf, Schritte, Puls.
2. **Die App rechnet lokal.** Für jeden Wert gibt es „deinen üblichen Bereich“ (die mittlere Hälfte deiner letzten 28 Tage). Daraus entstehen Kacheln, Diagramme und einfache Regeln (Begleiter, Coach, Aktivierung, Infekt-Hinweis, Körper-Tempo).
3. **Fünf Bereiche (Tabs):** Heute · Gesundheit · Analyse · Coach · Ernährung. Dazu Profil, Geräte, Ring.
4. **Begleiter:** Wecker (AlarmKit), Morgenbericht (lokal berechnet, auf Wunsch vorgelesen), Tagesimpulse (max. 3), Aktivierungs-Einheiten mit Countdown, Expertenrunde.
5. **Claude (KI):** nur im Tab „Analyse“. Du tippst auf einen Bericht oder eine Frage, siehst eine Vorschau der Daten, tippst „Senden“. Ohne diesen Tipp passiert nichts.

## 2. Ehrliche Befunde: warum es sich wie ein Werte-Friedhof anfühlt

| # | Befund | Folge für dich |
|---|---|---|
| B1 | **Die KI wird nie von selbst aktiv.** Claude läuft nur nach „Senden“. Es gibt keine geplanten Prüfungen. | Du musst die KI „bedienen“, statt dass sie dich begleitet. |
| B2 | **Die App schläft, wenn sie zu ist.** Es sind keine Hintergrund-Rechte eingerichtet (kein Bluetooth-Hintergrund, keine Hintergrundaufgaben, keine Apple-Health-Hintergrundlieferung). | Ring-Daten kommen erst, wenn du die App öffnest. Morgens weiß die App nichts von deiner Nacht, bis du sie öffnest. |
| B3 | **Startseite = Kachelwand.** „Jetzt dran“, Ring, Apple Health, Ruhepuls, HRV … untereinander. Kein Satz, der dir sagt, was das alles bedeutet. | Zahlen ohne Geschichte. |
| B4 | **Diagramme ohne Stimme.** Der Verlauf (Tag/Woche/Monat/3 Monate) zeigt Linie + üblichen Bereich, aber keine Kommentare, keine Markierungen „hier war was“. | Du musst selbst deuten. |
| B5 | **Zu viele Inseln.** Begleiter, Coach, Aktivierung, Expertenrunde, Sprechstunde, Detektiv, Experimente, Körperbiografie, Ernährung: jedes Modul für sich gut gemeint, zusammen unübersichtlich. | „Mit den ganzen Funktionen kann ich nichts anfangen.“ |
| B6 | **Morgen ist kein Erlebnis.** Der Morgenbericht existiert, liegt aber in einem Unterbildschirm. Das „Ich bin wach“ am Wecker merkt sich nur die Uhrzeit. | Kein „Hey, du bist wach!“-Moment. |
| B7 | **Training ohne Nachweis.** Aktivierung zählt Wiederholungen und Countdowns, prüft aber nicht am Puls, ob du wirklich trainiert hast, und gibt keine Rückmeldung aus den Werten. | Kein „cool, das hat gewirkt“. |
| B8 | **Kein Gedächtnis über den Tag.** Was morgens gesagt wurde, weiß der Abend nicht. Es gibt keine durchgehende Erzählung. | Es fühlt sich nicht wie *ein* Begleiter an. |

Gut und wiederverwendbar ist die Technik darunter: Datenbank, üblicher Bereich, Aufwach-Erkennung (`WakeDetector`), Nachtanalyse, Morgenbericht-Bausteine, Vorlesen (`BriefingSpeaker`), Wecker mit „Ich bin wach“-Knopf, Aktivierungs-Übungen, Coach-Regeln, Claude-Anbindung mit Sicherheitsregeln (`SafetyRules`, ärztlicher Modus), Kostenrechner, lokales Apple-Sprachmodell (`OnDeviceBrain`). **Das Problem ist das Erlebnis, nicht das Fundament.**

## 3. Was der Markt gut macht

Siehe Abschnitt 11 (Marktrecherche mit Quellen). Kurzfassung der Muster, die wir übernehmen:

- **Ein Satz zuerst, Zahlen danach** (Oura, WHOOP, Garmin Morning Report).
- **Ein Tageswert als Anker** (Readiness, Recovery, Body Battery): eine große Zahl/Form, die den Tag erklärt.
- **Proaktiver Coach mit Gedächtnis**, der Kontext (Training, Notizen, Ereignisse) kennt (WHOOP Coach, Oura Advisor, Fitbit/Gemini Coach).
- **Morgen-Ritual mit festem Ablauf** (Garmin Morning Report: Schlaf → Erholung → Plan des Tages).
- **Annotationen im Verlauf**: Ereignisse und Notizen als Symbole auf der Zeitachse.
- **Kurze, angeleitete Einheiten** mit Live-Puls und Ergebnis danach.

## 4. Leitbild: der persönliche Begleiter (abgeleitet aus *QualityLand*)

Wir übernehmen das **Prinzip**, keine Figuren und keine Namen aus dem Buch. Im Buch kennt der Assistent seinen Menschen besser als dieser sich selbst, spricht ihn proaktiv an und hat eine eigene Persönlichkeit. Die satirische Schattenseite: Er entscheidet über den Kopf hinweg, verkauft, manipuliert, und man kann ihm nicht widersprechen. Daraus folgen sieben Regeln:

| Übernehmen | Bewusst vermeiden |
|---|---|
| **P1 Er meldet sich von selbst** zu festen Momenten (Aufwachen, Mittag, Abend, nach dem Training, bei Auffälligkeiten). | Dauerbeschallung. Höchstens 3 eigene Meldungen pro Tag plus Weck- und Trainingsmoment, Ruhezeiten werden eingehalten. |
| **P2 Er kennt dich** (Verlauf, üblicher Bereich, Notizen, Gespräche, Ziele) und bezieht sich darauf („wie letzten Dienstag“). | Er tut nie so, als wüsste er mehr, als die Daten hergeben. Unsicherheit wird genannt („ziemlich sicher“, „nur ein Verdacht“). |
| **P3 Er hat eine Persönlichkeit**: locker, direkt, mit Humor, duzt dich, kurze Sätze. | Kein Schleimen, kein Belehren, kein Schuldgefühl, keine Streak-Erpressung („Du verlierst deine Serie!“). |
| **P4 Er schlägt vor und handelt mit**, z. B. startet er die Stoppuhr, wenn du „Los“ sagst. | **Du entscheidest immer.** Jeder Vorschlag hat „Nicht heute“ und „Anders“. Er bucht, kauft und sendet nichts ohne deine Freigabe. |
| **P5 Er ist ehrlich** und erklärt auf Nachfrage, warum er etwas sagt („Warum?“-Knopf an jeder Aussage zeigt die Werte dahinter). | Keine Blackbox, kein Nudging aus fremden Interessen (keine Werbung, keine Partner, kein Verkauf). |
| **P6 Er merkt sich Widerspruch.** „Das stimmt nicht, ich war krank“ korrigiert seine Deutung für die Zukunft. | Er bleibt nicht stur bei seiner Deutung. |
| **P7 Er bleibt bei dir**: Daten auf dem iPhone, an Claude nur das Nötige und nur nach deiner Daueranweisung (siehe §8.2), alles einsehbar im „Gesendet“-Protokoll. | Keine heimliche Datenweitergabe. |

**Arbeitsname des Begleiters:** frei wählbar beim Einrichten (Vorschlag: „Puls“). Stimme: beste installierte deutsche Stimme, später optional eine eigene.

## 5. Das Kreativteam

Für das Konzept wurden diese Rollen als Perspektiven eingesetzt (wie in früheren Runden: Perspektiven eines Teams, keine echten Personen):

1. **Produktleitung** – ein Gedanke pro Bildschirm, alles andere weg.
2. **Erlebnis-Designer (Motion/Sound/Haptik)** – „lässig, dynamisch“: Bewegung erzählt, nicht dekoriert.
3. **Schreiber/Stimme des Begleiters** – Ton, Sätze, Humor, Länge.
4. **Sportwissenschaftler** – 10-Minuten-Einheiten, Pulszonen, Nachweis.
5. **Internist/Schlafmediziner** – was zählt morgens wirklich, Warnzeichen.
6. **Datenvisualisierer** – Symbole im Diagramm, Tag/Woche/Monat.
7. **iOS-Architekt** – was iOS im Hintergrund wirklich erlaubt.
8. **Datenschutz/Ethik** – Leitbild ohne QualityLand-Schattenseite.
9. **Advocatus Diaboli** – was nervt nach zwei Wochen?

## 6. Das neue Erlebnis

### 6.1 Drei Bereiche statt fünf

| Neu | Inhalt | Was dort aufgeht |
|---|---|---|
| **Jetzt** | Der Begleiter spricht: ein Satz, eine Aktion, der Tagesbogen | Heute, Jetzt dran, Begleiter, Morgenbericht, Coach-Tagesplan, Aktivierung |
| **Verlauf** | Diagramme Tag/Woche/Monat/3 Monate/Jahr mit KI-Symbolen | Gesundheit, Analyse-Berichte, Detektiv, Körperbiografie |
| **Gespräch** | Mit dem Begleiter reden (Text/Sprache), Sprechstunde, Expertenrunde, Ernährung erfassen | Analyse/Sprechstunde, Ernährung, Experimente |

Profil, Geräte, Ring, Einstellungen bleiben oben rechts. Nichts wird gelöscht; die bestehenden Module wandern unter diese drei Dächer. Ernährung bleibt erreichbar (Gespräch: „Ich hab gerade Müsli gegessen“ oder Barcode-Knopf).

### 6.2 Bildschirm „Jetzt“

```
┌──────────────────────────────┐
│  ◐ 07:42        Puls ✦        │  Begleiter-Avatar: pulsierende Form,
│                              │  Farbe = Tageslage, atmet im Ruhepuls-Takt
│  „Guter Start. 7 h 10 Schlaf, │  EIN Satz, groß, KI-formuliert
│   Ruhepuls 4 unter normal.    │
│   Heute verträgt dein Körper  │
│   mehr."                      │
│                              │
│  [ ▶ 10 Min. Aktivierung ]   │  EINE Hauptaktion
│   Nicht heute · Warum?       │
│                              │
│  ── Tagesbogen ──────────────│  0–24 Uhr als Bogen/Band:
│  ☾━━━━━☀●━━━━━━━━━━━━━━━━━━  │  Schlaf, Aufwachen, Check-ins,
│      ✦  ⚡     ◆             │  Training, Symbole
│                              │
│  Zuletzt: 07:15 Morgen-Check │  Karten-Stapel der heutigen Meldungen
│  ▸ Nacht ▸ Erholung ▸ Plan   │  (wischbar wie Stories)
└──────────────────────────────┘
```

- Oben **ein Satz**, nicht zehn Werte. Zahlen erst beim Antippen („Warum?“).
- Der **Tagesbogen** zeigt den Tag als Zeitachse mit Symbolen (§6.5). Er wächst über den Tag.
- **Karten-Stapel** = die heutigen Meldungen des Begleiters (Morgen, Mittag, Abend, Training), wischbar wie Instagram-Stories, jede mit „Vorlesen“.

### 6.3 Morgen-Ritual (das Herzstück)

1. **Aufwachen erkennen** (beste verfügbare Quelle zuerst, siehe §8.1):
   Weckerknopf „Ich bin wach“ → Ende des Schlaf-Fokus → erste Entsperrung/erstes Öffnen nach 04:00 → Puls+Schritte-Anstieg aus dem Ring.
2. **„Hey, du bist wach!“** – Mitteilung bzw. direkt in der App: Avatar „wacht mit auf“ (Animation + sanfter Ton + Haptik).
3. **Erzählter Morgenbericht, 45–60 Sekunden**, als Stories mit Stimme:
   - *Nacht:* „7 Stunden 10, zweimal kurz wach gegen 3.“
   - *Erholung:* „Ruhepuls 54, 4 unter deinem Normal. HRV im oberen Bereich.“
   - *Vergleich:* „Beste Nacht seit Dienstag.“
   - *Deutung:* „Du bist gut erholt. Das passt zu deinem freien Abend gestern.“
   - *Plan:* „Heute: 10 Minuten Aktivierung jetzt, mittags ein Spaziergang, Training ab 17 Uhr ist eine gute Idee.“
   - *Wetter/Kleidung* (vorhanden), *Warnzeichen* falls nötig (immer zuerst und deutlich).
4. **„Auf geht's: 10 Minuten.“** – ein Knopf, Stoppuhr startet (§6.4).
5. Bei schlechter Nacht wird der Plan sanfter („heute 10 Minuten Mobilität statt Liegestütz“).

### 6.4 Angeleitetes 10-Minuten-Training mit Nachweis

- **Ablauf:** Begleiter sagt die Übung an (Stimme + großes Bild), Stoppuhr/Intervall läuft groß, **Live-Puls vom Ring** läuft als Linie darunter. Sperrbildschirm zeigt eine Live-Aktivität (Stoppuhr + Puls), damit das iPhone weggelegt werden kann.
- **Nachweis „hat gewirkt“** (lokal, ohne KI berechnet):
  - Puls steigt während der Einheit auf ≥ 60 % der geschätzten Pulsreserve (Ruhepuls aus der Nacht, Maximalpuls aus Alter oder gemessen) für insgesamt ≥ 4 Minuten → „Ziel erreicht“.
  - Erholung: Pulsabfall 60 Sekunden nach Ende (HRR60). Ein größerer Abfall als dein üblicher = gute Form; deutlich kleiner = Hinweis auf Müdigkeit.
  - Schritte/Bewegung im Zeitfenster als Zusatzbeleg.
  - Ist der Ring nicht verbunden: ehrlich „Ohne Ring kann ich es nicht prüfen, ich glaube dir.“
- **Feedback** direkt danach (1–2 Sätze, vorgelesen): „Cool, 6 Minuten im Zielbereich, Puls nach einer Minute um 28 gefallen. Das ist besser als letzte Woche.“ Oder: „Dein Puls kam kaum hoch. Entweder war's zu leicht, dann nächstes Mal eine Stufe mehr, oder du bist müde. Wie fühlst du dich?“ (Antwort fließt ins Gedächtnis.)
- Das Ergebnis erscheint als Symbol ⚡ im Tagesbogen und im Verlauf.

### 6.5 Symbolsprache (überall gleich: Tagesbogen, Verlauf, Mitteilungen)

| Symbol | Bedeutung | Beispiel |
|---|---|---|
| ✦ | Begleiter-Hinweis (KI-Deutung) | „Ab hier stieg dein Ruhepuls 3 Tage.“ |
| ▲ / ▼ | Wert deutlich über / unter deinem üblichen Bereich | HRV ▼ an zwei Tagen |
| ⚡ | Training / Aktivierung, mit Ergebnis | „Ziel erreicht“ |
| ☾ | Schlaf-Ereignis | kurze Nacht, sehr gute Nacht |
| ◆ | Muster erkannt (wiederkehrend) | „Montags immer schlechterer Schlaf“ |
| ✚ | Deine Notiz / Ereignis (Alkohol, Krankheit, Reise, Stress) | aus Gespräch oder Tagesabschluss |
| ⚠ | Warnzeichen, bitte abklären | in Rot-Orange, immer oben, nie versteckt |
| ★ | Bestwert / Rekord | „beste Nacht seit 30 Tagen“ |

Technisch: SF Symbols statt Unicode, damit alles skaliert und barrierefrei vorlesbar ist. Jedes Symbol ist antippbar und öffnet die Aussage mit „Warum?“ (Werte dahinter) und „Stimmt nicht“ (Widerspruch, §4 P6).

### 6.6 Verlauf mit KI-Symbolen

- Zeiträume: **Tag · Woche · Monat · 3 Monate · Jahr**, mit Wischen zwischen Tagen/Wochen.
- Linie + üblicher Bereich wie heute, **zusätzlich Symbole auf der Zeitachse** (Swift Charts `PointMark` mit Symbol + `annotation`).
- Über dem Diagramm ein **Satz des Begleiters zum gewählten Zeitraum** („Diese Woche: Ruhepuls stabil, HRV nach dem Mittwoch-Training zwei Tage unten, dann zurück.“). Er wird beim Check-in vorberechnet, nicht beim Öffnen.
- **Mehrere Werte übereinander** (z. B. Schlaf + HRV + Training) mit gemeinsamer Zeitachse, damit Zusammenhänge sichtbar werden.
- Einzeltag antippen → Tagesbogen dieses Tages mit allen Meldungen von damals („Was hat der Begleiter an dem Tag gesagt?“).

### 6.7 Mittags- und Abend-Check

- **Mittag (ca. 12–13 Uhr):** Bewegung bisher, Puls/Stress am Vormittag, Vorschlag für den Nachmittag (Spaziergang, Training ja/nein, Koffein-Grenze). 2–3 Sätze.
- **Abend (ca. 20–21 Uhr):** Tagesbilanz in 3 Sätzen, ein Lob oder eine Beobachtung, Einladung zum Tagesabschluss (vorhanden) mit Notiz („Alkohol? Stress? Krank?“), Ausblick auf die Nacht.
- **Du steuerst:** Uhrzeiten der drei Checks, welche Meldungsarten, Ruhezeiten (wie Oura, als Antwort auf WHOOP-Kritik).
- **Ehrliche Lernphase:** In den ersten Tagen sagt der Begleiter „noch 4 Nächte, bis ich dein Normal kenne“ statt Fantasiewerte.
- **Zusätzlich ereignisgesteuert:** Warnhinweis erst, wenn **mindestens zwei** Werte gleichzeitig deutlich vom Üblichen abweichen (wie Apple Vitals), mit möglichen Ursachen; z. B. auffälliger Wert (z. B. nächtlicher Ruhepuls deutlich hoch + HRV tief → Infekt-Hinweis), 2 ruhige Stunden (vorhanden), Training erkannt.

### 6.8 Ton und Beispiele

- Kurz. Max. 3 Sätze pro Meldung, max. 60 Sekunden Vorlesen.
- Konkrete Zahl + Vergleich + Bedeutung + ein Vorschlag.
- Lässig, aber nicht albern: „Solide Nacht.“ statt „Super!!! 🎉“.
- Ärztlicher Modus (bestehende Entscheidung 21.11.) gilt: mögliche Ursachen mit Wahrscheinlichkeit, Warnzeichen deutlich, Medikamente nie eigenmächtig umstellen.

### 6.9 „Dynamisch, cool, lässig“ – Gestaltung

- **Lebendiger Avatar** statt Logo: eine weiche, leuchtende Form (MeshGradient/Shader), die im Takt deines Ruhepulses atmet; Farbe nach Tageslage (ruhiges Cyan = erholt, warmes Bernstein = müde). Keine Ampel-Bewertung, sondern Stimmung.
- **Übergänge erzählen**: Morgen-Stories gleiten ein, Zahlen zählen hoch, Symbole „ploppen“ auf der Zeitachse auf, Haptik bei jedem neuen Symbol.
- **Sound**: kurzer eigener Klang je Moment (Aufwachen, Ziel erreicht, Abend).
- Bestehende Studio-Standards (Motion, Haptik, Sound, Reduce Motion) gelten.

## 7. Was mit den bestehenden Modulen passiert

| Heute | Künftig |
|---|---|
| Begleiter (Wecker, Morgenbericht, Impulse) | wird **der** Begleiter, Kern von „Jetzt“ |
| Aktivierung | wird das 10-Minuten-Training mit Nachweis |
| Coach | liefert im Hintergrund den Plan (WAS), der Begleiter sagt ihn an (WANN/WIE) |
| Jetzt-dran-Karte, Tagesabschluss | gehen in „Jetzt“ auf |
| Analyse-Berichte, Detektiv, Körperbiografie | werden zu Begleiter-Sätzen und Symbolen im Verlauf; Detailseiten bleiben erreichbar |
| Sprechstunde, Expertenrunde | im Bereich „Gespräch“ |
| Ernährung | im Bereich „Gespräch“ + Knopf |
| Gesundheit (Diagramme) | wird „Verlauf“ mit Symbolen |

## 8. Technik: wie „automatisch“ auf dem iPhone wirklich geht

### 8.1 Ehrliche iOS-Grenzen und unser Weg

iOS lässt Apps nicht frei im Hintergrund laufen. „Genau um 12:00 rechnet die KI“ ist **nicht garantiert**. Deshalb mehrere Auslöser, und wer zuerst kommt, macht den Check:

| Auslöser | Was er kann | Zuverlässigkeit |
|---|---|---|
| **App-Öffnen** | Sofort Ring abholen, Check machen, falls fällig | sicher |
| **Bluetooth-Hintergrund** (`bluetooth-central` + Zustandswiederherstellung) | Ring bleibt verbunden, App wird bei Ring-Ereignissen kurz geweckt und kann Verlauf abholen | gut, sobald eingerichtet; am R03 zu testen |
| **Hintergrundaufgaben** (`BGAppRefreshTask`/`BGProcessingTask`) | iOS weckt die App „ungefähr“ zur Wunschzeit für ca. 30 Sekunden | ungefähr, iOS entscheidet |
| **Apple-Health-Hintergrundlieferung** | App wird geweckt, wenn neuer Schlaf/neue Schritte in Health landen | gut für Schlaf/Schritte |
| **Wecker „Ich bin wach“** (vorhanden) und **Schlaf-Fokus-Ende** (Fokus-Filter, `SetFocusFilterIntent`) | sicheres Aufwach-Signal | gut; Fokus-Ende am Gerät zu prüfen |
| **Geplante Mitteilung** zur Check-in-Zeit | erinnert zuverlässig; Text kommt aus dem letzten Hintergrund-Check, Tippen startet einen frischen Check | sicher |

Ergebnis für dich: Morgens, mittags, abends liegt eine Meldung bereit, **ohne dass du etwas absendest**. Wenn iOS die App nicht rechtzeitig weckt, ist sie in der Mitteilung etwas älter und wird beim Öffnen sofort aufgefrischt.

### 8.2 Wer rechnet was

1. **Lokal, immer, kostenlos:** alle Zahlen, üblicher Bereich, Aufwach-Erkennung, Trainingsnachweis, Symbole ▲▼⚡☾★⚠. Auch ohne Internet und ohne Claude funktioniert alles; die Sätze kommen dann aus Textbausteinen bzw. dem Apple-Sprachmodell auf dem Gerät (kostenlos, ab iPhone 15 Pro/16 Pro).
2. **Claude, 3× täglich automatisch + nach Training:** formuliert die Deutung (✦), erkennt Muster (◆), schreibt den Satz zum Zeitraum. Bekommt eine **kompakte Zusammenfassung** (Tageswerte, Abweichungen, Notizen), keine Rohdaten-Minuten.
3. **Sicherheitsnetz:** `SafetyRules` (ärztlicher Modus) prüft jede Claude-Antwort; Warnzeichen kommen immer aus lokalen Regeln, nie nur aus der KI.

**Wichtig – Regeländerung nötig:** In `CLAUDE.md` steht heute „an Claude nur nach sichtbarer Vorschau“. Automatische Checks brauchen stattdessen eine **Daueranweisung**: einmal einschalten, festlegen *was* gesendet wird (Liste), jede Sendung landet im Protokoll „Gesendet“ mit Inhalt und Kosten, jederzeit abschaltbar. Diese Entscheidung trifft Johannes (§10, E1).

### 8.3 Neue Bausteine (Code)

- `PulseCore/Companion/CheckInPlanner` – welcher Check ist fällig (Morgen/Mittag/Abend/Ereignis), Ruhezeiten, Tageslimit.
- `PulseCore/Companion/CheckInComposer` – baut die kompakte Zusammenfassung (wiederverwendet `ContextBuilder`, `NightAnalyzer`, `PersonalBaseline`).
- `PulseCore/Companion/CompanionMemory` – Tagesgedächtnis (was wurde gesagt, Widersprüche, Notizen); baut auf dem Sprechstunden-Gedächtnis auf.
- `PulseCore/Activation/WorkoutVerifier` – Pulsreserve-Zeit, HRR60, Schritte → Ergebnis + Begründung.
- `PulseCore/Insights/ChartMarker` – ein Modell für alle Symbole (Typ, Zeit, Wert, Text, Quelle, Sicherheit).
- App: `BackgroundCoordinator` (BGTask, BLE-Wiederherstellung, HealthKit-Lieferung), `JetztScreen`, `TagesbogenView`, `StoryBriefingView`, `GuidedSessionView` + Live-Aktivität, Verlauf mit Markern.
- `project.yml`: `UIBackgroundModes` (bluetooth-central, fetch, processing), `BGTaskSchedulerPermittedIdentifiers`, HealthKit-Hintergrundlieferung, Live-Aktivitäten. Datenbank: neue Modelle `CheckInRecord`, `ChartMarkerRecord` (Schema-Wächter ausführen).

## 9. Kosten der automatischen Claude-Prüfungen

Preise aus `CostEstimator.swift` (Anthropic-Preisliste, Stand 20.11.2026), USD pro 1 Mio. Tokens.
Annahme je Check: ca. 6.000 Tokens hinein (Zusammenfassung + feste Anweisung), ca. 600 Tokens heraus. 3 Checks + ca. 1 Trainings-Feedback pro Tag ≈ 120 Aufrufe/Monat.

| Modell | je Check | pro Tag (≈4) | pro Monat |
|---|---|---|---|
| Claude Opus 5.5 (4 $ / 20 $) | ca. 0,036 $ | ca. 0,14 $ | **ca. 4,30 $** |
| Claude Sonnet 5.5 (2 $ / 10 $) | ca. 0,018 $ | ca. 0,07 $ | **ca. 2,20 $** |
| Claude Haiku 5.5 (0,10 $ / 0,50 $) | ca. 0,001 $ | ca. 0,004 $ | **ca. 0,11 $** |
| Apple-Modell auf dem iPhone | 0 | 0 | **0 $** |

Mit Prompt-Caching der festen Anweisung sinkt das um geschätzt 20–40 %. **Empfehlung:** Sonnet für die täglichen Checks, Opus einmal pro Woche für den Wochenrückblick (+ ca. 0,30 $/Monat) → **ca. 2,50 $ im Monat**. Obergrenze in den Einstellungen (z. B. 5 $/Monat), danach nur noch lokal. Kein Abo, keine Zusatzhardware.

## 10. Entscheidungen für Johannes

- **E1 Automatisch senden:** Darf der Begleiter 3× täglich automatisch eine Zusammenfassung an Claude schicken (Daueranweisung + Protokoll + Monatsgrenze), statt jedes Mal „Senden“? *Empfehlung: ja.*
- **E2 Modell:** Sonnet täglich + Opus wöchentlich (ca. 2,50 $/Monat)? *Empfehlung: ja.*
- **E3 Drei Bereiche** (Jetzt · Verlauf · Gespräch) statt fünf Tabs? *Empfehlung: ja.*
- **E4 Name und Stimme** des Begleiters (Vorschlag „Puls“).
- **E5 Ring im Hintergrund verbunden halten** (braucht etwas mehr Akku am Ring und iPhone).

## 11. Marktrecherche (Stand November 2026)

Hinweis: whoop.com, ouraring.com waren aus der Recherche-Umgebung nicht direkt abrufbar; Angaben dazu stammen aus Suchergebnissen und Fachpresse. „unbestätigt“ = nicht gegengeprüft.

| Anbieter | Stark beim Begleiten | Schwäche | Quelle |
|---|---|---|---|
| **WHOOP** | „Daily Outlook“ morgens mit klarer Empfehlung (Gas geben/erholen), „Day in Review“, Fragen zu jedem Bildschirm, Journal (Koffein, Stress) als Kontext; seit 05/2026 „My Memory“ + proaktive Check-ins (vor Terminen, nach Reisen, nach Krankheit) | KI noch Beta, Nutzer wollen steuern, wann der Coach schreibt | whoop.com/us/en/thelocker/new-ai-guidance-from-whoop · wareable.com (My Memory) · gearpatrol.com (Reddit-Feedback) |
| **Oura** | Morgendliche Readiness-Nachricht lädt direkt ins Gespräch mit Advisor ein; Symptom Radar erst nach 7 Nächten (ehrliche Lernphase); Pläne mit vom Nutzer gesteuerten Check-ins; App auf 3 Tabs reduziert; „Cumulative Stress“ als Monatssignal | Proaktive Pushes von Advisor unbestätigt | support.ouraring.com/hc/en-us/articles/39512345699219 · ouraring.com/blog/personalized-plans-with-oura-advisor · techcrunch.com/2025/10/20/oura-launches-redesigned-app-and-cumulative-stress-feature |
| **Ultrahuman** | Erholungswert aktualisiert sich live (Nickerchen, Sauna); „Movement Index“ startet morgens bei 100 und fällt bei Sitzen; zuschaltbare Module (Tagesrhythmus, Koffein-Fenster) | Wenig Details nach dem Training | ultrahuman.com/re/powerplugs · gsmarena.com (Ring-AIR-Test) |
| **Garmin** | Morning Report automatisch zur gewohnten Aufwachzeit (Wetter, Schlaf, HRV, Readiness, Tagesnachricht); Readiness rechnet den Tag über weiter; ehrliche 3-Wochen-Lernphase; Active Intelligence meldet sich beim Aufwachen, nach Training, abends | Active Intelligence gilt als generisch, wiederholt nur, was ohnehin dasteht | garmin.com Handbuch (Morning Report) · androidcentral.com (Connect+) · techradar.com (Kritik) |
| **Apple** | Workout Buddy: gesprochene Ansage zum Start, Meilensteine, Fazit (auf dem Gerät); Vitals meldet sich erst, wenn ≥ 2 Nachtwerte außerhalb des Üblichen liegen, nennt mögliche Ursachen; Training Load 7 vs. 28 Tage in Wortstufen | Workout Buddy zunächst nur Englisch, nicht mit Vitals verknüpft | apple.com/newsroom/2025/06/watchos-26… · dcrainmaker.com/2025/07/apple-watchos-26-workout-beta-real-world.html |
| **Samsung** | Energy Score morgens; Schlafenszeit-Empfehlung; Running Coach startet mit 12-Minuten-Einstufungstest, dann Level 1–10 und Plan | Verstreut über viele Kacheln (Einschätzung) | news.samsung.com (One UI 8 Watch) |
| **Fitbit/Gemini Coach** | Einstiegsgespräch 5–10 Min. über Ziele; ein Coach für alles; „Ask Coach“ überall; klare Bereiche | Nur Vorschau, USA, Premium | blog.google/products/fitbit/personal-health-coach-public-preview · research.google/blog/how-we-are-building-the-personal-health-coach |
| **Bevel** | Strain/Recovery/Schlaf nur aus Apple Health (unser Fall ohne Watch ähnlich); „Bevel Intelligence“ erklärt das Warum | Zielwerte abstrakt, keine konkrete Einheit | apps.apple.com/us/app/bevel…/id6456176249 · lifestack.ai/blog/bevel-app-review |
| **Athlytic** | Zielkorridor direkt im Verlaufsdiagramm; viele Widgets | Schwer verständlich, Werte teils veraltet | techradar.com (Athlytic) |
| **Gentler Streak** | Figur spiegelt Tagesform über Gesicht, Farbe, einen Satz (emotional, nicht kindisch); Ruhetage werden belohnt | Ohne Apple Watch kaum nutzbar | apps.apple.com/us/app/gentler-streak…/id1576857102 |
| **Polar** | FitSpark: täglich 2–4 fertige Einheiten passend zur Nacht, beste oben; neu berechnet nach Training, Mitternacht, Aufwachen; Pulszonen mit festen Zeiten | Phasen nicht änderbar | support.polar.com/en/fitspark-daily-training-guide |

**Übernommen in dieses Konzept:** feste KI-Momente (Aufwachen, nach Training, Abend) · erst ein Satz, dann Zahlen, dann Rückfrage · eine klare Tagesempfehlung · Warnung erst bei ≥ 2 gleichzeitigen Abweichungen + mögliche Ursachen · ehrliche Lernphase („noch 4 Nächte“) · Zielkorridor im Diagramm · Journal-Tags als Kontext · Gedächtnis + Nachfass-Check-in, Häufigkeit vom Nutzer gesteuert · 2–3 Einheiten-Vorschläge, eine empfohlen · gesprochene Begleitung Start/Mitte/Ende · Einstufungstest für das 10-Minuten-Training · Figur/Farbe als Stimmung.

**Vermeiden:** KI, die nur vorliest, was dasteht · Pushes ohne Steuerung · abstrakte Ziele ohne nächste Handlung · widersprüchliche Zahlen zwischen Ansichten · Kachelfriedhof.

**Lücke im Markt (Chance):** KI-Symbole direkt im Verlaufsdiagramm, Trainingsnachweis über Pulsverlauf und ein erzählter Audio-Morgenbericht nach erkannter Aufwachzeit sind bei keinem Anbieter so belegt (unbestätigt). Genau das wäre PULSE ONEs Eigenes.

## 12. Umbau in Etappen (jede Etappe = ein TestFlight-Build)

| Etappe | Inhalt | Ergebnis für dich |
|---|---|---|
| **E-1 Wach werden** | Hintergrund-Rechte, BLE-Wiederherstellung, BGTask, HealthKit-Lieferung, `CheckInPlanner`, geplante Mitteilungen; Checks zunächst lokal formuliert | Die App holt Daten von selbst und meldet sich morgens/mittags/abends |
| **E-2 Jetzt-Bildschirm** | Neuer Start mit einem Satz, Avatar, Tagesbogen, Karten-Stapel; 3 Bereiche | Kein Werte-Friedhof mehr |
| **E-3 Morgen-Ritual** | Aufwach-Signale, erzählte Stories, „Auf geht's“ | „Hey, du bist wach“-Moment |
| **E-4 Training mit Nachweis** | Geführte Einheit, Live-Puls, Live-Aktivität, `WorkoutVerifier`, Feedback | „Cool, hat gewirkt“ |
| **E-5 Claude automatisch** | Daueranweisung, Protokoll, Kostengrenze, Gedächtnis, ✦/◆-Deutungen | Echte KI-Deutung ohne Senden |
| **E-6 Verlauf mit Symbolen** | Marker in allen Diagrammen, Satz je Zeitraum, Überlagerung | Diagramme, die erzählen |

E-1 und E-2 können parallel laufen. Reihenfolge E-3/E-4 nach Wunsch tauschbar.

## 13. Risiken

- **iOS weckt die App nicht pünktlich** → mehrere Auslöser + Auffrischen beim Öffnen (§8.1).
- **Ring liefert im Hintergrund nicht** (R03 ungetestet) → Apple Health und App-Öffnen als Rückfall; Realtest in E-1.
- **Nerv-Faktor nach 2 Wochen** → Tageslimit, „Weniger davon“-Knopf je Meldungsart, Begleiter lernt aus Ignorieren.
- **Falsche Deutung** → „Warum?“ + „Stimmt nicht“, Unsicherheit wird genannt, Warnzeichen nur aus lokalen Regeln.
- **Live-Puls des R03 ist träge/lückenhaft** → Nachweis braucht nur Minuten im Zielbereich, nicht Sekundengenauigkeit; am Ring zu prüfen.
