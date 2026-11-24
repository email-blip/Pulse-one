# Prüfliste M1 „Durchstich“ (Team 06 QA)

Stand: 2026-11-23, Branch `claude/project-thread-uv4fq0`. Grundlage: Plan §8 (12 Punkte des Ablaufs), Vorgaben M (Zusatzprüfungen, Performance).

**Nachweisstufen:** Konzept · implementiert · gebaut · Simulator · iPhone · abgenommen. Ein Mockup oder Szenario beweist keine Ring-Integration.
Spalte „Nachweis“ nennt den automatischen Test (CI) oder den Handtest am iPhone.

## A. Der Ablauf (Video im CI)

Test: `UITests/DurchstichTests.testWalkthrough`, Video `durchstich.mp4` (Artefakt `durchstich-video-<Lauf>`, 14 Tage) und Bilder je Schritt auf `ci-screenshots/<branch>/m1-<Gerät>/`.

| # | Punkt | Team | Nachweis | Stufe |
|---|---|---|---|---|
| 1 | App öffnen, ROOK-Beitrag sofort sichtbar, Testansicht-Banner | 03/04 | Schritt 1 (+ verbotene Sätze geprüft) | Konzept (Test fertig, Bildschirm fehlt) |
| 2 | ROOK begrüßt und spricht die Deutung (Vorlesen/Stoppen) | 05 | Schritt 2 (Ton selbst nur am iPhone hörbar) | Konzept |
| 3 | Kachel verschieben | 03 | Schritt 3 (barrierefreie Alternative „nach unten“) | Konzept |
| 4 | Reihenfolge bleibt nach Neustart | 03 | Schritt 4 | Konzept |
| 5 | Kachel öffnet Verlauf | 03 | Schritt 5 | Konzept |
| 6 | Cursor durch Puls/HRV/Schlaf, Wert + Uhrzeit | 03/01 | Schritt 6 | Konzept |
| 7 | Originalpunkt mit echter Messzeit | 03/01 | Schritt 7 | Konzept |
| 8 | Hypnogramm-Abschnitt antippen | 03/01 | Schritt 8 (braucht Schlafsegmente von 01 im Szenario) | Konzept |
| 9 | „Warum?“ zeigt Belege | 04 | Schritt 9 (mind. ein `why.evidence.*`) | Konzept |
| 10 | Korrektur „Ich bin krank“ ändert die Empfehlung | 04 | Schritt 10 (Text ändert sich in ≤ 20 s, ohne Netz) | Konzept |
| 11 | Einheit starten mit Ansage | 05 | Schritt 11 | Konzept |
| 12 | Pause (Timer steht, keine Ansage) → Fortsetzen (Timer läuft) | 05 | Schritte 12–13 | Konzept |
| 13 | Abschluss mit Anstrengung 1–10 | 05 | Schritt 14 | Konzept |
| 14 | Einheit erscheint im Tagesverlauf | 03/05 | Schritt 15 | Konzept |
| 15 | Sprachgespräch mit ROOK: Zuhören → Denken → Sprechen, Transkript, Antwort, Unterbrechung (Barge-in), Ende | 05/04 | Schritt 16 (`-uiTestVoice`, kein Mikrofon im Simulator; echte Spracherkennung nur iPhone) | implementiert |

## B. Zusatzprüfungen (Vorgaben M)

| Prüfung | Wie | Team | Stufe |
|---|---|---|---|
| Volle Nacht | Szenario-Daten 01 + Hypnogramm-Screenshot | 01/03 | Konzept |
| Nacht mit Lücke | Lücke 13:00–14:10 im Szenario `neubauM1` (Puls); Nachtlücke kommt mit 01 | 01/03 | implementiert (Daten), Anzeige offen |
| Unbekannter Schlafcode | 01-Fixture, Hypnogramm zeigt „unbekannt“ | 01/03 | Konzept |
| Doppel-Sync | PulseCore-Test 01 (keine Doppelpunkte) | 01 | Konzept |
| Falsches Profil | PulseCore-Test 01 | 01 | Konzept |
| Veralteter Wert | Kachel zeigt Bezugszeit statt „jetzt“ | 03 | Konzept |
| Unregelmäßige Abstände | Spur ohne Verbindungslinie über Lücken | 03 | Konzept |
| Sommerzeit / Zeitzone | PulseCore-Test 01 + Achse 03 | 01/03 | Konzept |
| Offline | Ablauf läuft ohne Netz (Testszenario hat keins) | 04/05 | Konzept |
| KI-Fehler / Budgetende | 04-Test: Beitrag fällt auf lokale Deutung zurück, kein Fehlertext | 04 | Konzept |
| Anruf / Kopfhörer weg | 05-Test Audio-Koordinator + Handtest iPhone | 05 | Konzept |
| Abgelehnte Berechtigungen | Handtest iPhone (Bluetooth, Health, Mitteilungen) | 01/05 | Konzept |
| XXXL | Screenshot-Matrix `m1-*__xxxl` (3 Geräte) + Audit | alle | implementiert (Test), wartet auf Bildschirme |
| Reduce Motion | Screenshots `m1-dashboard/timeline/workout__reduced` | 02/03/05 | implementiert (Test), wartet auf Bildschirme |
| VoiceOver / Audit | `AccessibilityTests.testM1*Audit` auf 7 neuen Bildschirmen | alle | implementiert (Test), wartet auf Bildschirme |

## C. Performance

| Prüfung | Test | Ziel | Stufe |
|---|---|---|---|
| Scrubbing mit Jahresdaten (~105 000 Pulspunkte) | `TimelinePerformanceTests.testScrubbingYearOfData` (Zeit, CPU, Speicher) | flüssig, 60 fps | implementiert |
| Pannen: Bildrate, Hitch-Anteil | `testPanningHitches` (System-Scroll-Signposts) | < 5 ms/s Hitches | implementiert |
| Keine Daueranimation unsichtbarer Ansichten | `testIdleCPUWithDashboardHidden` (CPU im Leerlauf) | nahe 0 % | implementiert |

Werte stehen im Lauf-Bericht („Performance, Simulator, nur berichtend“). Simulator ≠ iPhone: 60 fps gilt erst nach Messung am Gerät (Instruments über Johannes' Rechner geht nicht, also Sichtprüfung + spätere On-Device-Messung).

## D. Aufräumen alter Tests

Wer einen alten Bildschirm entfernt (03: Heute/Gesundheit/Scores, 04: Analyse/Begleiter/Ernährung/Herz), streicht im selben PR dessen Einträge in `ScreenshotTests.scenarios`, `AccessibilityTests`, `InteractionTests`, `IntelligenceTests`, `CompanionTests`, `ActivationTests` und den Bereich in `ExplorerTests` (Patch an 06-Dateien, im PR-Text nennen). 06 prüft beim Integrationslauf, dass nichts Totes übrig ist.

## Kennungen für Teams 02–05 (Vertrag der Tests)

Bildschirm-Wurzeln tragen die Kennung immer (nicht nur im Testszenario). Quelle der Wahrheit: `apps/PulseOne/UITests/NeubauM1.swift`.

| Kennung | Team | Bedeutung |
|---|---|---|
| `screen.dashboard`, `screen.timeline`, `screen.why`, `screen.workout`, `screen.workoutSummary` | 03/04/05 | Bildschirm-Wurzeln |
| `rook.insight` | 03/04 | Schlagzeile + Deutung als ein Element, Label = sichtbarer Text |
| `rook.speak` | 05 | Vorlesen/Stoppen (Umschalter) |
| `rook.why` | 04 | „Warum?“ |
| `rook.action` | 04/05 | Primärhandlung; nach „Ich bin krank“ eine leichtere, startbare Einheit |
| `rook.correct`, `correction.sick` | 04 | Korrektur öffnen, „Ich bin krank“; Ergebnis lokal und ohne Netz im Testszenario |
| `orb` | 02 | ROOK-Orb (vom Kontrast-Audit ausgenommen) |
| `dashboard.edit`, `dashboard.editDone` | 03 | „Kacheln anordnen“ / „Fertig“ |
| `tile.<Kachel-ID>` (z. B. `tile.metric.heart_rate`, `tile.sleep`) | 03 | Kachel, ID aus `DashboardTile.id` |
| `tile.<Kachel-ID>.moveDown` / `.moveUp` | 03 | barrierefreie Verschiebe-Knöpfe im Bearbeiten-Modus |
| `timeline.chart` | 03 | ziehbare Spurenfläche (ein Element über alle Spuren) |
| `timeline.selection` | 03 | Cursor-Anzeige: Wert, Einheit, Original-Messzeit „HH:mm“ |
| `timeline.track.sleep` | 03 | Hypnogramm-Spur |
| `hypnogram.segment.<n>` | 03 | jeder Schlafabschnitt als eigenes Element (Phase + Uhrzeit); der Test tippt den ersten |
| `hypnogram.selection` | 03 | gewählter Schlafabschnitt: Phase + „HH:mm–HH:mm“ |
| `timeline.event.workout` | 03/05 | abgeschlossene Einheit im Verlauf |
| `why.evidence.<n>`, `why.close` | 04 | Belege, Schließen |
| `workout.start/.pause/.resume/.finish/.save` | 05 | Steuerung |
| `workout.state` | 05 | `accessibilityValue` = `WorkoutRunState.rawValue` |
| `workout.remaining` | 05 | Restzeit der Phase als Text |
| `workout.exertion.1` … `.10` | 05 | Anstrengung |
| Tableiste „Dashboard“, „Verlauf“, „Coach“ | 03 | Tab-Beschriftungen |
| Signpost `de.sommerlabs.pulseone` / `timeline` / `scrub` (optional) | 03 | eigene Messung des Cursor-Updates, wenn gewünscht |

Szenario starten: `-uiTesting YES -scenario neubauM1` (kurz für `-uiTestScenario`), Jahresdaten `neubauM1Year`, Video mit laufenden Animationen `-liveMotion YES`.
