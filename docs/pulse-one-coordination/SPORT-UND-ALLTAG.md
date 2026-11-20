# PULSE ONE – Sportübergreifender Kern, Sportmodule und betreute Tiere (Aufträge P1-004, P1-004-N1)

Stand: 2026-11-20. Nur Dokumentation. Leitung: Codex, Entscheidung: Johannes.

**Anlass:** Johannes fragte, warum das Kreativlabor so stark auf Reiten zugeschnitten ist; er will verschiedenste Anwendungen und Sportarten.
Befund: `CREATIVE-LAB.md` und `CREATIVE-LAB-2.md` hatten eine eigene Pferde-Perspektive (§3.5 H1–H6). Außerdem nutzten sie Stall/Reiten als Standardbeispiel bei Ernährung, Podcast, Kontext und Vergleichen. Das war für die universelle Produktvision zu eng.

**Ergänzung P1-004-N1 (Johannes):** PULSE ONE unterstützt Menschen **und verschiedene Tiere** als eigenständige betreute Lebewesen: Hunde, Katzen, Pferde, Kleintiere, Geflügel und weitere Arten. Pferd und Reiter sind nur ein optionaler Anwendungsfall. Das ist **Produktscope und Architekturplanung**. Es wird nichts als implementiert oder tiermedizinisch validiert behauptet.

**Diese Datei gilt vor den Beispielen in den Kreativlaboren.** Alte Quellen-IDs, Ideen und Historie bleiben dort erhalten. Die Beispiele sind dort neutral nachgezogen, markiert mit „P1-004“.

---

## 1. Grundsatz

1. **Ein Kern für alle.** Messdaten, Belastung, Erholung, Kontexttagebuch, Ziele, Rückblicke und Experimente sind sportneutral. Sie funktionieren auch **ohne Sportziel**, zum Beispiel nur für Schlaf, Alltag und Erholung.
2. **Präferenzen kommen aus dem Profil.** Sportarten, Ziele und Trainingsorte wählt die Person im Onboarding oder später. Es gibt keine Reitannahme und keine andere Sportart als Voreinstellung. Ohne Auswahl zeigt die App nur den Kern.
3. **Drei unabhängige Achsen:** Sportart, Designprofil und Geräteadapter hängen nicht voneinander ab. Ein Läufer kann jedes Designprofil wählen. Ein Polar H10 dient Laufen, Rudern oder Reiten gleichermaßen.
4. **Keine neue Plugin-Infrastruktur auf Vorrat.** Bestehende Typen werden erweitert, wenn ein Modul gebaut wird (siehe §3).
5. **Fachlich passende Metriken je Sportart.** Kein universeller Score, der alles auf eine Zahl reduziert. Sportübergreifend vergleichbar sind nur Zeit, Herzfrequenz-Belastung und die selbst eingeschätzte Anstrengung (sRPE).

## 2. Sportneutraler Kern

| Baustein | Was er sportneutral leistet | Beispiele aus verschiedenen Bereichen |
|---|---|---|
| Messdaten | Puls, HRV, SpO₂, Schlaf, Schritte, Temperatur, je mit Quelle und Qualität (`HealthSample`) | gleich für alle |
| Belastung | Dauer × Anstrengung (sRPE), Herzfrequenz-Zonen, wo vorhanden | Lauf 45 min, Krafteinheit 60 min, Gartenarbeit 2 h |
| Erholung | Ruhepuls, HRV, Schlaf relativ zum persönlichen Normalband | nach Fußballspiel, nach Nachtschicht, nach Wanderung |
| Kontexttagebuch (`ContextEvent`) | freie Ereignisse mit Zeit, Stichworten und optional Sprachnotiz | „Intervalllauf, Kaffee spät“, „Umzug, kaum geschlafen“, „Hufschmied, Ausritt kurz“ |
| Ziele | frei wählbar, auch ohne Sport | „5 km unter 30 min“, „Kniebeuge 80 kg“, „vor 23 Uhr schlafen“, „Alpencross im Juli“ |
| Rückblicke | Woche, Monat, Jahr mit Datenlücken | „3 Läufe, 2 Krafteinheiten, Schlaf stabil“ |
| Experimente (N-of-1) | eigene Selbstversuche mit Plan und ehrlicher Auswertung | „Abends kein Bildschirm“, „Krafttraining morgens statt abends“, „Kaffee nur bis 14 Uhr“ |
| Sessionbericht | eine Einheit beliebiger Art: Dauer, Puls-Verlauf, sportartspezifische Werte, Notiz | Lauf, Ausfahrt, Training, Ritt, Spiel |

## 3. Sportmodule (konfigurierbar, freiwillig)

Ein Modul legt nur fest: Eingaben, passende Metriken, Sensoren, Sessionbericht-Felder, Ergänzungsübungen. Es nutzt den Kern und ändert ihn nicht.

| Modul | Fachlich passende Metriken | Eingaben / Sensoren | Hinweis |
|---|---|---|---|
| Laufen | Distanz, Pace (min/km), Herzfrequenz-Zonen, Kadenz, Höhenmeter | iPhone-GPS, Health-Workouts, H10/R03 | Pace nur mit GPS oder Workout-Distanz |
| Radfahren | Distanz, Geschwindigkeit, **Watt**, **Kadenz**, Höhenmeter | GPS, Leistungsmesser/Trittfrequenzsensor (BLE-Standardprofile), H10 | Watt nur mit Leistungsmesser, nie geschätzt als Messwert |
| Krafttraining | Übung, **kg, Sätze, Wiederholungen**, Volumen, RPE/RIR | manuelle Eingabe, Übungskatalog (`COACH-ENGINE-SPEC.md`) | Puls nur ergänzend |
| Rudern | **500-m-Pace**, **Schlagzahl** (Schläge/min), Distanz, Watt (Ergometer) | Ergometer-BLE (FTMS) oder manuell, H10 | Boot und Ergometer getrennt kennzeichnen |
| Fußball / Teamsport | Spielzeit, Sprints (wenn GPS), Belastung (sRPE), Erholung | manuell, GPS optional, H10 | keine Positionsdaten anderer Spieler |
| Wandern / Outdoor | Distanz, Höhenmeter, Dauer, Puls-Zonen | GPS, Health-Workouts | Höhe aus GPS ungenau, so kennzeichnen |
| Reiten | Dauer, Gangarten-Anteile (nur wenn erkannt), Puls Reiter | GPS, iPhone-Bewegungssensoren, H10 | Pferdedaten getrennt, siehe §4 |
| Weitere / eigene | Dauer, sRPE, freie Felder (Name, Einheit) | manuell | z. B. Yoga, Schwimmen, Klettern, Tanzen |
| Ohne Sport | Schlaf, Alltag, Erholung, Schritte | R03, Health | vollwertige Nutzung, kein „unvollständiges“ Profil |

**Typen, die später erweitert werden (keine neue Infrastruktur):**
- `SportPreferences` im Profil: gewählte Module.
- `ContextEvent` mit `activityKind`.
- `SampleKind` für neue Messarten (z. B. Watt, Kadenz, Schlagzahl), jeweils mit eigener kanonischer Einheit und eigenem Plausibilitätsbereich.

Gebaut wird nur, was ein freigegebenes Modul braucht.

## 4. Tiere als eigenständige betreute Lebewesen (P1-004-N1)

### 4.1 Modell

- **Tierprofil = eigenes Subjekt.** Es ist kein menschliches `UserProfile` mit anderem Namen. Geplanter Typ: `AnimalProfile` neben dem Personenprofil, beide als „betreutes Lebewesen“ adressierbar (`SubjectID`).
- **Art offen erweiterbar:** Hund, Katze, Pferd, Kaninchen, Meerschweinchen, Geflügel sowie weitere Arten und Kleinvieh. Als Datenkatalog geführt (`AnimalSpecies`), nicht als feste Aufzählung im Code. „Andere Art“ mit freiem Namen ist immer möglich.
- **Felder:** Art, bei Bedarf Rasse, Geburtsdatum oder geschätztes Alter, Lebensphase (jung, erwachsen, Senior; je Art definiert), individuelle Ziele (z. B. „Gewicht halten“, „ruhiger beim Tierarzt“), Halter- und Betreuungszuordnung.
- **Beziehungen:** Ein Tier kann mehrere Betreuer haben, ein Mensch mehrere Tiere. Die Zuordnung ist zeitlich gültig, wie bei Geräten (`DeviceAssignment`-Muster). Datenströme je Subjekt bleiben getrennt. Geteilte Betreuung ist konzeptionell möglich, **ohne** soziale Cloud-Funktionen jetzt vorauszusetzen. Daten bleiben auf dem Gerät.
- **Drei getrennte Schichten:**
  - **Art:** welche Felder und Werkzeuge passen.
  - **Individuum:** dieses eine Tier.
  - **Geräteadapter:** welcher Sensor liefert was.
  - Keine Schicht leitet Annahmen für eine andere ab.

### 4.2 Gemeinsame Werkzeuge (für alle Arten, auch ohne Wearable)

| Werkzeug | Inhalt | Ohne Sensor nutzbar |
|---|---|---|
| Aktivitäts-/Ruheverlauf | Spaziergänge, Spielzeit, Ruhephasen; nur bei passendem Sensor gemessen, sonst eingetragen | ja (manuell) |
| Gewicht | Verlauf mit Datum und Waage/Quelle | ja |
| Ernährung / Fütterung | Futter, Menge, Zeit, Änderungen als Notiz; **kein** Kalorienmodell aus der Humanernährung | ja |
| Verhalten | freie Beobachtungen mit Stichworten | ja |
| Tagebuch | Ereignisse wie Tierarzt, Impfung, Hufschmied, Krallen, Fellwechsel, Umzug | ja |
| Termine | Impfungen, Entwurmung, Kontrollen als Erinnerung | ja |
| Herkunft und Zeitstempel | jede Beobachtung mit Wer/Wann/Woher (Betreuer, Gerät, manuell) | ja |

Felder und Inhalte erscheinen **nur, wenn sie für die Art passen.** Hufschmied gibt es nur beim Pferd, Krallenpflege nicht beim Huhn, Eierzahl nur beim Geflügel.

### 4.3 Grenzen (nicht verhandelbar)

- **Keine Übertragung menschlicher Modelle:** keine menschlichen Referenzbereiche oder Normalbänder, keine HRV- oder Erholungsscores, keine Kalorienmodelle, keine Stress- oder Krankheitsdeutung. Tierbezogene Bereiche erst mit art- und gerätespezifischem Nachweis.
- **Ein menschlicher Ring ist kein Tiersensor.** Die Eignung wird je Gerät, Trageweise, Tierart und Messart einzeln nachgewiesen. Bis dahin steht dort „Unterstützung unbekannt“.
  - Beispiel: R03 am Hundehalsband für die Herzfrequenz ist unbekannt.
  - Beispiel: Polar H10 im Equine-Gurt am stehenden Pferd ist laut Studie gut, aber für PULSE ONE unbestätigt.
- **Kein pauschales Versprechen:** Nicht alle Arten bekommen dieselben Messungen. Arten und Geräte mit unbekannter Unterstützung werden in der App ausdrücklich so gekennzeichnet.
- **Apple Health bleibt ausschließlich am menschlichen iPhone-Besitzerprofil.** Keine Tierdaten nach HealthKit schreiben, nichts aus HealthKit als Tierdaten importieren.
- **Gleichlauf mehrerer Sensorströme** (Mensch–Tier, Mensch–Mensch) ist ein allgemeines Analysewerkzeug für zeitliche Nähe. Stress, Ursache oder „wer reagiert zuerst“ wird daraus **nicht** behauptet (H1, H4, H6, P18 bleiben ungeprüfte Hypothesen).
- Keine tiermedizinischen Aussagen. Bei Auffälligkeiten nur „mit Tierärztin oder Tierarzt besprechen“.

### 4.4 Kurze Szenarien

- **Hund:** Lena trägt zwei Spaziergänge am Tag ein (Dauer, Strecke per iPhone-GPS, wenn sie es mitnimmt), das Gewicht monatlich und Futterwechsel als Notiz. Der Wochenrückblick zeigt „9 Spaziergänge, 6,5 h, Gewicht stabil“. Ihr eigener Schlaf und Puls laufen getrennt in ihrem Profil. Ein Halsband-Sensor wäre ein eigener Adapter mit Eignung „unbekannt“, bis er nachgewiesen ist.
- **Katze:** Ohne Wearable. Fütterungszeiten, Trinkmenge geschätzt, Verhaltensnotizen („versteckt sich seit Umzug“) und Tierarzttermine mit Erinnerung. Zwei Betreuer im Haushalt tragen ein; jede Notiz zeigt, wer sie wann gemacht hat.
- **Hühner (Kleinvieh, Gruppe):** Haltungsjournal für die Gruppe und einzelne Tiere: Eierzahl je Tag, Futter, Gewicht einzelner Tiere bei Kontrolle, Stalltemperatur über einen Raumsensor (Xiaomi-Adapter, falls vorhanden). Keine Einzeltier-Messung vorausgesetzt.
- **Pferd (optional):** Ritt als Sessionbericht des Reiters, Pferdedaten im Pferdeprofil getrennt, Hufschmied und Entwurmung als Termine, H10 am Pferd nur nach Eignungsnachweis.

## 5. Kennzeichnung der Ideen

Jede Idee aus den Kreativlaboren gehört zu genau einer Ebene:

| Ebene | Bedeutung | Beispiele (IDs) |
|---|---|---|
| **Kern-Produktidee** | sportneutral, auf dem Kern baubar | Kontexttagebuch (CL1-4, H5 verallgemeinert), Sessionbericht (H3 verallgemeinert), Experimente (CL1-3), Rückblicke (CL1-12) |
| **Sportmodul-Idee** | an eine Sportart gebunden, fachlich passend | Gangarten-Erkennung (H2), Kraft-Volumen-Verlauf, Watt-Profil, Ruder-Split |
| **Laboridee** | Prognose, Deutung, Grenzgänger: experimentell | P-, G-Ideen, Prognose-Turnier (P17) |
| **Allgemeine Forschung** | erst nach Validierung | RF-01 … RF-12 in `ROADMAP.md` |
| **Tier-/sportartspezifische Hypothese** | nur als ungeprüfte Recherche | H1, H4, H6, P18 |
| **Tier-Werkzeug (Scope)** | artübergreifend, manuell nutzbar, ohne medizinische Deutung | Tiertagebuch (H5 verallgemeinert), Gewicht, Fütterung, Termine (§4.2) |

Die Forschungsetiketten A–D aus den alten Laboren bleiben **ungeprüfte Recherchehinweise**, keine Abnahme (`ROADMAP.md`, Spielregeln).

## 6. Abnahmematrix (sechs Sportarten plus Alltag)

Eine Ausgabe gilt als „belegbar“ nur, wenn ihre Eingaben vorhanden sind. Fehlt etwas, zeigt die App die Lücke statt eines Werts.

| Profil | Ziel (Beispiel) | Eingaben / Sensoren | Belegbare Ausgaben | Fehlende Voraussetzungen heute |
|---|---|---|---|---|
| Alltag ohne Sport | besser schlafen, ruhiger werden | R03 (Schlaf, Puls), Health (Schritte), Kontexttagebuch | Schlafdauer und Ruhepuls im Normalband, Wochenrückblick mit Lücken, Experiment „Bildschirm aus um 22 Uhr“ | R03-Messnachweis am iPhone; `ContextEvent`; Profil/Onboarding |
| Laufen | 10 km unter 60 min | Health-Workouts/GPS, Puls R03 oder H10 | Distanz, Pace, Zonenzeit je Lauf; Erholung am Folgetag | GPS-Aufzeichnung; Workout-Details (heute nur Dauer); H10-Adapter |
| Radfahren | 100-km-Ausfahrt | GPS, Leistungsmesser, Kadenzsensor, H10 | Watt, Kadenz, Distanz, Höhenmeter je Ausfahrt | BLE-Adapter Cycling Power/Speed & Cadence; Messarten Watt/Kadenz |
| Krafttraining | Kniebeuge 80 kg × 5 | manuelle Eingabe (Übung, kg, Sätze, Wdh.) | Volumen je Einheit, Verlauf je Übung, Erholung danach | Eingabemaske und Übungskatalog (`COACH-ENGINE-SPEC.md`) |
| Rudern | 2000 m unter 8 min | Ergometer (FTMS) oder manuell, H10 | 500-m-Pace, Schlagzahl, Distanz, Watt (Ergometer) | FTMS-Adapter; Messarten Pace/Schlagzahl |
| Fußball | fit durch die Saison | Spielzeit manuell, sRPE, GPS optional | Belastung je Woche (sRPE × Dauer), Erholung nach Spielen | Kontexttagebuch mit `activityKind`; sRPE-Eingabe |
| Reiten (freiwillig) | entspannter Ausritt | Puls Reiter (R03/H10), GPS; optional H10 am Pferd | Dauer, Puls-Verlauf Reiter, Route; Pferdedaten getrennt | Tier-Subjekt; Zwei-Geräte-BLE; Gangarten-Erkennung unvalidiert |

**Ergänzung Tiere (P1-004-N1):**

| Profil | Ziel (Beispiel) | Eingaben / Sensoren | Belegbare Ausgaben | Fehlende Voraussetzungen heute |
|---|---|---|---|---|
| Hund | Gewicht halten, genug Bewegung | manuell (Spaziergang, Gewicht, Futter), iPhone-GPS des Menschen | Spaziergänge je Woche, Gewichtsverlauf, Termine | `AnimalProfile`, Tiertagebuch; Halsband-Sensor: Eignung unbekannt |
| Katze | Ruhe nach Umzug, Gewicht | manuell (Fütterung, Verhalten, Gewicht) | Verlauf der Notizen und Gewicht, Erinnerungen | `AnimalProfile`, Mehrbetreuer-Zuordnung |
| Hühner / Kleinvieh | Haltungsjournal | manuell (Eier, Futter, Gewicht), Raumsensor optional | Tages- und Wochenwerte der Gruppe | Gruppen-/Einzeltier-Modell, Raumsensor-Adapter |

Allen Zeilen gemeinsam (Menschen) fehlt heute: der reale R03-Pulsnachweis am iPhone sowie Profil, Onboarding und HEUTE-Anzeige (nächster Produktauftrag).

## 7. Reihenfolge

Keine konkurrierende Implementierung. Priorität bleiben:
1. die grüne Review-CI (PR #18),
2. der reale R03-Messnachweis,
3. dann Profil, fortsetzbares Onboarding und HEUTE.

Sportmodule und Tierprofile folgen danach einzeln und nur auf Freigabe. Laufen und Krafttraining sind die naheliegenden ersten, weil sie ohne neue Hardware auskommen.
