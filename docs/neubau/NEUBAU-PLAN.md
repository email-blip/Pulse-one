# PULSE ONE – Neubau: Integrationsplan (Leitstand 00)

Stand: 2026-11-23, Version 2 (ChatGPT-Vorgaben „Motion Dashboard & Personal AI Coach“ und „Medienbibliothek und Gesundheitscoach“ eingearbeitet).
Verbindlich bei Widerspruch: dieser Plan vor älteren Konzepten (Begleiter-Konzept, Kern-wie-Oura, Master-Directive-Teile zu UI).
Verträge im Detail: `VERTRAEGE.md`. Auftragstexte je Team: `auftraege/01…06`.

---

## 1. Bestand und Sicherung

| Punkt | Stand |
|---|---|
| Repository | `email-blip/Pulse-one` (öffentlich), native SwiftUI, Swift 6, iOS 18+ |
| Integrationsstand | `main` = `2c5dae4` (#55) = **TestFlight Build 17** |
| Sicherungspunkt | Commit `2c5dae4` + Build 17 in TestFlight (Rückfall-Installation). Ein Git-Tag `vor-neubau-build17` wurde vom Server abgelehnt (keine Tag-Rechte); `main` ist unveränderlich in der Historie, damit reicht der Commit. |
| Offene PRs | nur #57 (dieser Plan). Keine ungesicherten Änderungen anderer Threads auf `main`. |
| Datenbank | SwiftData, **nicht versioniert** (kein `VersionedSchema`), 21 Modelle laut `docs/schema-snapshot.json` (u. a. `StoredSample`, `StoredMeasurement`, `StoredInsight`, `StoredCheckIn`, Coach-, Aktivierungs-, Ernährungs- und Konferenz-Datensätze). Öffnet die Datenbank nicht, läuft die App mit Hinweis auf einem temporären Speicher (kein stilles Löschen). |
| Codeumfang | ~33.000 Zeilen Swift (App + PulseCore) |
| Bestätigt am R03 | alle Verlaufsarten (Puls 5 min, Stress 30 min, HRV, SpO₂, Schritte, Schlaf `BC 27` mit Phasen), Nacht über 9 h verbunden mit Auto-Reconnect (`docs/colmi-protokoll.md`) |

**Regel:** Keine Messdaten werden beim Umbau gelöscht. Modelle verlassen das Schema erst mit einer versionierten Migration (`VersionedSchema` V1 → V2) und einem Migrationstest mit echter Datenbank-Kopie (Aufgabe 00, Meilenstein M2).

## 2. Threadbaum

| Nr. | Thread | Zuordnung |
|---|---|---|
| **00** | Leitstand / Architektur / Integration | **dieser Thread** („App komplett neu wie Oura gestalten“) |
| **01** | Daten / R03 / HealthKit / Schlaf | bestehender Thread **„Ring dauerhaft verbunden halten“** (hat schon Ring-Protokoll, Hintergrund, AccessorySetupKit-Prüfung); Auftrag wird erweitert |
| **02** | Design-System / Motion / Assets | neu |
| **03** | Dashboard / Zeitspuren / Diagramme | neu |
| **04** | Coach Intelligence / Interpretation / Gedächtnis | neu |
| **05** | Sprache / Training / Timer / Mitteilungen | neu |
| **06** | QA / Performance / Release-Prüfung | neu |

Alle älteren Threads (Begleiter, Oura-Kern, Coach, Sprechstunde, Verzahnung, KI-Rundgang …) sind abgeschlossen und bauen **keine** UI mehr. Threads können nicht direkt miteinander schreiben; Übergaben laufen über PRs auf `main`, diese Dateien und Nachrichten über den Leitstand.

Nur 00 lädt zu TestFlight hoch.

## 3. Marktvergleich (kurz) und Lückenliste

| | Oura | QRing | Whoop | Garmin | Apple | **PULSE ONE Ziel** |
|---|---|---|---|---|---|---|
| Start | 3 Scores + 1 Tageserkenntnis | Kacheln je Wert | 3 Zahlenräder + Wochenplan | „Mein Tag“-Karten frei anordenbar | Favoriten | **ROOK-Deutung + Handlung, dann frei anordenbare Kacheln** |
| Tagesverlauf | Kurve mit Messpunkten | jeder 5-min-Wert antippbar | Belastungskurve | Puls-/Body-Battery-Kurve | Swift-Charts-Scrubbing | **mehrere synchrone Spuren, Pinch-Zoom, gemeinsamer Cursor, Originalwert + Originalzeit** |
| Schlaf | Hypnogramm + Nachtkurven | Phasenbalken | Phasen, Schlafschuld | Phasen-Zeitachse | Phasen-Diagramm | **Hypnogramm auf derselben Zeitachse wie Puls/HRV/SpO₂, unbekannte Phasen sichtbar** |
| KI | Advisor-Chat | – | Coach mit Gedächtnis, Spracheingabe | Kurzsätze | Highlights | **ein Charakter: deutet, handelt, fasst nach, spricht, Zeitcursor folgt der Stimme** |
| Training | – | – | KI-Workouts | Workouts | Fitness+ (Video) | **animierte Übung, Ansagen, Timer aus Zeitstempeln, Live Activity** |

Quellen: Oura-Redesign Okt./Nov. 2025 (TechCrunch, Droid Life), Whoop Home + 2026-Neuerungen (whoop.com), Ultrahuman Emerald 2026 (Wareable), QRing/Garmin/Apple aus den App-Ständen.

**Lücken in Build 17:** Schlafphasen nur als Text gespeichert (kein Hypnogramm möglich) · Verlauf als Liste · Kacheln ohne Mini-Verlauf, nicht verschiebbar · KI-Prompt verlangt „sag ehrlich, was fehlt“ · „lernt noch“-Texte · drei getrennte KI-Persönlichkeiten (Begleiter, Sprechstunde, Expertenrunde) · Training ohne Sprache und ohne Animation · ~10 Animationsstellen in der ganzen App.

## 4. Produkt: drei Bereiche

**Dashboard · Verlauf · Coach** (native Tableiste unten, Profil/Ring/Status oben rechts, diskret).

Referenz-Ansicht (Mockup von ChatGPT, verbindlich in Aufbau und Hierarchie):
1. Kopf: **ROOK**-Zeichen (Ring-Orb) + Name, rechts „Vorlesen“.
2. Große Schlagzeile (2–3 Zeilen), darunter 1–2 Sätze Deutung.
3. Primärhandlung („Meine Einheit starten ↗“), daneben „Warum?“.
4. „Dein Cockpit“ + „Kacheln anordnen“: 2-spaltige Kacheln (Name, Symbol, große Zahl + Einheit, Bezug „NACHT · 07:00“, Mini-Verlauf).
5. Schlafvorschau und Tagesereignisse.

Palette (fest): Obsidian `#070D19`, Bio Cyan `#15D9F3`, Neural Violet `#9B70FF`, Pulse Coral `#FF644F`, Ice White `#E6F4FA`.

Coach-Name: **ROOK** (Arbeitsname, austauschbar, blockiert nichts).

## 5. Was bleibt, was neu wird, was später rausfliegt

| Bleibt (nach Bestandsprüfung durch das zuständige Team) | Neu | Wird entfernt, sobald ersetzt |
|---|---|---|
| Ring-Protokoll, Verlauf-Abruf, Reconnect, Messprofile (01) | Schlafsegmente als eigene Daten (01) | Ernährung komplett (UI sofort, Modell mit Migration) |
| `StoredSample`/`HealthSample` als einzige Datenwelt (01) | `MeasurementPoint`-Abfragen für Spuren (01) | Herz-3D (`HeartChamber`, `HeartGeometry`) |
| HealthKit-Import (01) | Design-Kit, Motion, Medienregister (02) | Labor, Detektiv, Experimente, Biografie, Zwei Gehirne |
| Score-Logik 0–100 (01, ohne „lernt noch“) | Dashboard, Kacheleditor, Zeitspuren, Hypnogramm (03) | Sprechstunde, Expertenrunde, Nachtforscher, Kleidungsberater |
| Check-in-Motor `CheckInGate`, `NightAssembler`, Claude-Client, Schlüsselbund, Kostenzähler (04) | ROOK-Deutung, Nachfassen, Rückfragen, „Warum?“ (04) | Alte Heute-/Verlauf-/Score-/Begleiter-Oberflächen |
| Coach- und Aktivierungslogik, Übungskatalog (05) | Audio-Koordinator, Trainingssession, Live Activity (05) | Alte Prompts mit „ehrlich sagen, was fehlt“ |
| Wecker/AlarmKit, Benachrichtigungs-Delegate (05) | Szenarien, Video-Abnahme, Performance-Messung (06) | Alte UI-Tests und Screenshot-Szenarien der entfernten Bildschirme |

Wer eine alte Oberfläche ersetzt, entfernt sie im selben PR aus dem produktiven Pfad. 00 macht am Ende jedes Meilensteins den Aufräum-Durchgang. Historie bleibt in Git.

## 6. Gemeinsame Verträge (Kurzfassung)

Code: `apps/PulseOne/Packages/PulseCore/Sources/PulseCore/Contracts/` (Besitzer 00), Tests: `ContractsTests.swift`.

| Vertrag | Typ | Kern |
|---|---|---|
| Measurement | `MeasurementPoint` | Sicht auf `HealthSample`: Subjekt, Gerät, Quelle, Art, Einheit, Methode, Messzeit, Empfangszeit, Importzeit, Qualität, Originalreferenz |
| SleepSegment | `SleepSegment`, `SleepPhase`, `SleepNight` | Rohcode, normalisierte Phase (inkl. `unknown`), Beginn/Ende, Quelle, Firmware; Zeit im Bett ≠ Schlaf; Lücken bleiben Lücken |
| TimelineState | `TimelineState`, `TimelineTrack`, `TimelineRange`, `NarrationCue` | sichtbares Fenster, Zoom, gemeinsamer Cursor, Spuren, gewählter Originalpunkt; Cursor in einer Lücke wählt nichts |
| CoachInsight | `CoachInsight`, `EvidenceRef`, `CoachAction`, `UserCorrection`, `CoachRevision`, `RookPresence` | Beobachtung, Deutung, Richtung, Belege, Handlung, Priorität, Gültigkeit, Nachprüfung, Korrekturen, Revisionen, Sprech-Abschnitte |
| WorkoutSession | `WorkoutSession`, `WorkoutStep`, `AnnouncementState` | Zeit nur aus Zeitstempeln und Pausen, `catchUp` nach Sperren, Pause verwirft Ansagen |
| DashboardLayout | `DashboardLayout`, `DashboardTile`, `DashboardTileSize` | stabile IDs, Reihenfolge, Größe, Sichtbarkeit, pro Profil |

Ein Zustand speist alles: Bildschirm, Stimme, Mitteilung, Diagramm-Markierung und Trainingssteuerung lesen dieselbe `WorkoutSession` bzw. denselben `CoachInsight`. Änderungen an Verträgen nur über 00.

## 7. Dateibesitz

| Team | Schreibt (allein) |
|---|---|
| 00 | `Sources/App/PulseOneApp.swift`, `LaunchOptions.swift`, `apps/PulseOne/project.yml`, `Sources/Persistence/PulseSchema.swift` + Migrationen, `PulseCore/Contracts/*`, `.github/workflows/*`, `DECISIONS.md`, `CLAUDE.md`, `docs/neubau/*` |
| 01 | `Sources/Bluetooth/*`, `Sources/Connect/*`, `Sources/Persistence/*` (außer `PulseSchema.swift`), PulseCore: `Colmi*`, `RingHistorySync`, `RingSettings`, `RingSnapshot`, `Connect/*`, `Scores/*`, `Insights/PersonalBaseline*`, `Day/*`, neu `PulseCore/Timeline/*` (Abfragen) |
| 02 | neu `Sources/DesignKit/*` (Tokens, Komponenten, Motion, Haptik-Muster), `Sources/Assets.xcassets`, neu `Resources/Media/*`, `docs/media/MEDIA-REGISTER.md`, `scripts/assets/*`; alt `Sources/DesignSystem/*` (wird von 02 abgelöst) |
| 03 | `Sources/App/MainTabView.swift`, neu `Sources/Features/Dashboard/*`, `Sources/Features/Timeline/*` (Verlauf, Spuren, Hypnogramm), `PulseCore/Insights/TodayLayout.swift` (ablösen); alt `Features/Today`, `Features/Health`, `Features/Scores` |
| 04 | `PulseCore/Companion/*`, `PulseCore/Intelligence/*`, `PulseCore/Insights/*` (außer TodayLayout, PersonalBaseline), `Sources/Features/Intelligence/*`, neu `Sources/Features/Coach/Conversation/*`; alt `Features/Companion` (ohne Services), `Features/Nutrition`, `Features/HeartChamber` |
| 05 | neu `Sources/Audio/*`, neu `Sources/Features/Training/*`, `Sources/Features/Coach/*` (außer `Conversation/`), `Sources/Features/Companion/Services/*` (Wecker, Mitteilungen, Sprecher), `App/NotificationDelegate.swift`, `PulseCore/Activation/*`, `PulseCore/Coach/*`, neu Live-Activity-Ziel (Projektänderung über 00) |
| 06 | `apps/PulseOne/UITests/*`, `apps/PulseOne/IntegrationTests/*`, neu `scripts/qa/*`, `docs/neubau/TESTBERICHT-*.md`, Testanleitungen |

Fremde Datei nötig? Kleinen Patch im eigenen PR mit Begründung, Besitzer-Team im PR-Text nennen, 00 entscheidet beim Merge.

## 8. Arbeitspakete, Reihenfolge, Abnahme

**Paket 0 (00, jetzt):** Verträge als Code + Tests, dieser Plan, Auftragstexte. Danach starten 01–06 gleichzeitig von `main`.

| Team | M1-Lieferung | Abnahme (je PR) |
|---|---|---|
| 01 | `SleepSegment` speichern (neues Modell, alte Nächte aus `stageSummary` nicht raten), `MeasurementPoint`-Abfragen je Spur/Zeitraum inkl. Aggregation, `receivedAt`, Erholung ab Tag 1, Szenario-Daten (volle Nacht, Lücke, unbekannter Code, Doppel-Sync, Sommerzeit) | PulseCore-Tests für alle Szenarien, kein Datenverlust, Migration lokal geprüft |
| 02 | Design-Kit (Palette, Schrift, Karte, Kachel, Knöpfe, Orb), Motion-Verträge (Dauer/Kurven je Ereignis), Haptik-Muster, Reduce-Motion-Regeln; Medienregister angelegt; Quellen-Erreichbarkeit geprüft | Referenzansicht in Screenshots (3 Größen, XXXL, hell nicht nötig), Kontrast AA |
| 03 | Dashboard nach Referenz, Kacheleditor (ziehen, Größe, ausblenden, barrierefreie Alternative, pro Profil gespeichert), Verlauf mit synchronen Spuren (Pinch, Pan, Cursor, Originalpunkt), Hypnogramm | UI-Test: Kachel verschieben → Neustart → Reihenfolge bleibt; Cursor zeigt Originalzeit |
| 04 | Prompt v-neu (Deutung → Richtung → Handlung, ≤3 Sätze, keine Lückensätze), `CoachInsight` aus Check-ins, „Warum?“-Belege, Nutzerkorrektur mit Revision, Textwächter gegen verbotene Sätze | Tests: positive und auffällige Deutung, Korrektur, Wächter |
| 05 | Audio-Koordinator (eine Warteschlange, AVSpeechSynthesizer, Unterbrechungen, Kopfhörer), Trainingssession-Bildschirm (Timer aus Zeitstempeln, Pause/Weiter/Überspringen/Ende, Ansagen), Phasenend-Mitteilung | Tests: Pause → keine Ansage; Sperren/Öffnen → richtige Restzeit |
| 06 | Szenario-Starter `-scenario neubauM1`, UI-Test über den ganzen Ablauf, Bildschirmvideo im CI, Prüfliste §15 | Video liegt als CI-Artefakt vor |

Merge-Reihenfolge M1: Verträge (00) → 02 und 01 → 03 und 04 → 05 → 06 → Integration 00.

**Erster integrierter Meilenstein M1 „Durchstich“** (Schritt C der Vorgabe), ein TestFlight-Build:
App öffnen → ROOK begrüßt und spricht die Deutung → Kachel verschieben (bleibt nach Neustart) → Kachel öffnet Verlauf → Cursor durch Puls/HRV/Schlaf-Spuren, Originalwert + Uhrzeit → Hypnogramm-Abschnitt antippen → „Warum?“ zeigt Belege → Korrektur „Ich bin krank“ ändert die Empfehlung → Einheit starten (Ansage) → Pause → Fortsetzen → Abschluss mit Anstrengung 1–10 → erscheint im Tagesverlauf.
Nachweis: Simulator-Video aus CI + Screenshots + Testbericht; danach TestFlight. Am iPhone mit echten R03-Daten ist M1 „gebaut“, „abgenommen“ erst nach Johannes' Test.

**M2:** echte Daten und Migration (Schritt D: Schlaf Ende-zu-Ende vom Ring, Dubletten, Zeitzonen, Profile, `VersionedSchema`), Medien-Erstlieferung (Körpermodell-Kandidat, zwei geprüfte Übungsanimationen, ROOK-Zustand, drei Sounds, Stimme, gesprochener Rückblick mit synchronem Cursor), Live Activity, alte Modelle entfernen.
**M3:** Belastungs-Echo, gezielte Rückfrage, nachfassender Coach, Wirkungskarte, Gesundheitschronik.

Nachweisstufen werden getrennt gemeldet: Konzept / implementiert / gebaut / Simulator / iPhone / abgenommen.

## 9. ROOK: Regeln für Sprache und Deutung

- Standard: **Deutung → Richtung → nächste Handlung**, höchstens drei kurze Sätze, locker, direkt, gelegentlich trockener Humor, „Bro/Junge/mein Freund“ nur selten und nur wenn Johannes das mag.
- Nie im Normalbetrieb: „Ich bin kein Arzt“, „kann ich nicht lesen“, „Basislinie fehlt“, „lernt noch“, Sync-Berichte, Zahlenlisten.
- Ohne persönliche Grundlage: normal begrüßen und eine passende Interaktion anbieten; keine erfundene Tagesdiagnose.
- „Warum?“ öffnet Messwerte, Vergleichszeitraum, Ereignisse, Berechnung, Alternativen, Unsicherheit.
- Keine erfundene Sicherheit, keine Diagnose-Prozente, keine Medikamentenänderung; Warnzeichen klar und kurz zur Abklärung.
- Fragt nach („Fühlst du dich auch so?“), nimmt Korrekturen ernst, fasst später nach.
- Meldet sich nur mit Anlass; „Heute Ruhe“, „Weniger antreiben“, „Sei direkter“, „Erinnere mich später“ wirken sofort.

## 10. Medien und Laufzeit

- Laufzeit M1: SwiftUI + Swift Charts; ROOK-Orb nativ (SwiftUI/Canvas) hinter `RookPresence`, damit eine spätere Rive-Datei ihn ohne Umbau ersetzen kann. **Keine** neue Bibliothek in M1.
- Rive, Lottie, Inferno, AudioKit, sherpa-onnx: nur mit `DECISIONS.md`-Eintrag (Zweck, Lizenz, Version) und belegtem Nutzen. Rive-Dateien entstehen im Rive-Editor; 02 klärt, ob das kostenlos geht.
- Quellen (Poly Haven, ambientCG, MakeHuman/MPFB, Quaternius, Kenney, NIH 3D, Freesound CC0, Sonniss GDC): Auswahl durch 02, jede Datei ins Medienregister (ID, Quelle, Autor, Lizenz, Nachweis, Version, Prüfsumme, Format, Größe, Verwendung, Attribution). Mixamo braucht Johannes' Adobe-ID und läuft nur über ihn.
- Erreichbarkeit: Die Cloud-Umgebung blockiert diese Seiten derzeit (Proxy 403). Freigabe der Hosts ist beantragt; sonst lädt 02 über Johannes' PC.
- Keine Gesundheitsdaten an Asset-Plattformen.

## 11. CI und Builds

- Jeder Push mit App-Änderungen startet die volle CI; ein Lauf belegt alle 5 Gratis-Mac-Jobs (15–20 Min.). Teams pushen gebündelt (etwa alle 2 Stunden), reine Doku-Pushes starten nichts. Bei sechs Teams entstehen Wartezeiten; 00 priorisiert die Läufe in Merge-Reihenfolge.
- Grüne Team-PRs merged 00 in der Reihenfolge aus §8 (squash). Teams mergen nicht selbst, damit `main` stabil bleibt.
- TestFlight nur aus `main` durch 00, wenn der Meilenstein-Ablauf im Video funktioniert.
