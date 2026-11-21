# QRing-Abgleich: Was der Ring kann und was PULSE ONE davon nutzt

Stand 2026-11-21. Nur Prüfung, kein Code geändert. Verantwortlich: Claude Code.

## Quellen

- Gadgetbridge, Geräteseite Yawell/Colmi (gelesen 2026-11-21): <https://gadgetbridge.org/gadgets/rings/yawell/>. Gadgetbridge ist eine freie Android-App, die dieselben Ringe ohne QRing ausliest. Was dort steht, ist am echten Ring nachgewiesen (Firmware 3.00.06/10/17 am R02).
- tahnok/colmi_r02_client und Befehlsübersicht in `/mnt/project-files/konzept/RING-AUSWERTUNGEN.md` §2 (aus dem Gadgetbridge-Quellcode).
- QRing selbst: App-Store-Seite war nicht abrufbar (HTTP 429), Codeberg blockierte automatisierte Abrufe. QRing-Angaben unten stammen aus Händlerseiten und Testberichten (z. B. Galaxus-Test, Händlerdatenblätter) und sind als **„Händler“** markiert, wenn Gadgetbridge sie nicht bestätigt.
- PULSE ONE: `docs/colmi-protokoll.md`, `ColmiProtocol.swift`, `ColmiModel.swift`, `Capability.swift`, `VitalReading.swift`, `Connect/SyncCoordinator.swift`, `Coach/RecoverySignals.swift`, `Coach/TrainingLoad.swift`, `HEALTH-DATA-SPEC.md`, `IMPLEMENTATION-ROADMAP.md`, `ROADMAP.md`, `PRODUCT-ARCHITECTURE-5.0.md`, `DESIGN-SYSTEM-5.0.md`, `STATUS.md`.

Stufen für PULSE ONE: **gebaut** = Code vorhanden; **iPhone** = am R03 nachgewiesen; **geplant** = in Roadmap/Spec; **fehlt** = nirgends geplant.

## 1. Datenarten und Ringfunktionen

| Datenart / Funktion | QRing / Ring (R03, R09) | PULSE ONE heute / geplant | Lücke |
|---|---|---|---|
| Akku | ja (GB) | **iPhone** (0x03, 0x73) | – |
| Firmware/Hardware lesen | ja | **iPhone** (RY03_3.00.21_241028) | `TestedFirmware` noch leer |
| Uhr stellen | ja | gebaut (Ortszeit-Fix) | – |
| Puls live (Einzelmessung) | ja (GB, QRing) | gebaut, **am R03 gescheitert**, Variante B in Build 8 | Realtest offen |
| Puls-Verlauf (5-min-Slots, Intervall 5–60 min) | ja, ~7 Tage im Ring (GB) | Parser gebaut, **nicht angebunden**; R2-2 | Ring-Daten älter als ~7 Tage gehen ohne regelmäßigen Sync verloren |
| Puls-Intervall einstellen (0x16) | ja (GB) | nur lesen geplant | **fehlt: schreiben** |
| SpO₂ live | ja (QRing) | Typ 3 im Protokoll, nicht in `Metric` | **fehlt** in `Metric` |
| SpO₂ ganztägig (Big Data 0x2A, Min/Max je Stunde) + Schalter 0x2C | ja (GB) | R2-2 „nur nach Mitschnitt“; Schalter nur lesen | **fehlt: Schalter setzen** |
| HRV live | ja (QRing, Gegenprobe 34 ms) | Typ 10 im Protokoll, nicht in `Metric` | **fehlt** in `Metric` |
| HRV-Verlauf (30-min-Slots, 0x39) + Schalter 0x38 | ja ab FW 3.0.0.10 (GB); R03 hat 3.00.21 | in HEALTH-DATA-SPEC unter `hrv_sdnn` eingetragen | **falsch zugeordnet:** Methode unbekannt, braucht eigene Art (z. B. `hrv_ring`), sonst Methodenmischung mit Apple-SDNN; Schalter setzen fehlt |
| RR-Abstände (Live-Typ 0x05) | im Protokoll (OPEN-SOURCE-REVIEW) | „Kandidat“ | offen, nur nach Mitschnitt |
| Stress (30-min-Index 0x37) + Schalter 0x36 | ja (GB, QRing zeigt Tagesmittel/Spanne) | **„nicht anzeigen“** (HEALTH-DATA-SPEC) | **Widerspruch** zu RING-AUSWERTUNGEN B4 (Tagesmuster). Vorschlag: Rohwert speichern, nur als Herstellerindex-Muster zeigen |
| Schlaf mit Phasen (Big Data 0x27: tief/leicht/REM/wach) | ja; REM ab FW 3.0.0.10 (GB) | R2-2 „nur nach Mitschnitt“, Phasen in Spec | Mitschnitt fehlt |
| Schritte, Kalorien, Distanz (15-min, 0x43) | ja (GB) | R2-2 geplant | – |
| Temperatur | nur R05/R09 (GB); R03 **nein** | `ColmiModel.hasTemperature` für R09; Spec „R09 Big Data“; Deutungen im Forschungsbacklog | Befehl/Format unbekannt bis R09-Test |
| Gesten (R09) | ja (GB: vorhanden, in GB **nicht umgesetzt**) | fehlt | **fehlt**; Protokoll unbekannt |
| Kamera-Auslöser per Geste | QRing ja (Händler); GB fehlt | fehlt | **fehlt**, braucht Mitschnitt |
| Ring finden (grüne LED 10 s) | ja (GB) | fehlt | **fehlt** (klein, Befehl bekannt) |
| Ring ausschalten | ja (GB) | fehlt | **fehlt** (klein) |
| Firmware-Update | QRing ja; GB nein | bewusst über QRing (erlaubt) | keine Lücke |
| Sport-/Trainingsmodus mit Aufzeichnung | QRing ja (Händler) | R2-9 Bewegungsaufzeichnung (iPhone-GPS + Ring-Puls), Sportmodule RM-23 | gleichwertig geplant |
| Ziele (Schritte, Schlaf) | QRing ja (Händler) | Profil-Ziele M3, Coach-Ziele | – |
| Apple-Health-Abgleich | QRing ja (Händler) | R2-8 (Puls, SpO₂, Schlaf schreiben) | – |
| Blutdruck, Blutzucker, „EKG“, „Müdigkeit“ (Live-Typen 2/4/7/9) | Ring bietet sie an | bewusst nicht | richtig so: PPG-Ring kann das nicht messen |
| Display-Einstellungen | nur R12 | – | betrifft uns nicht |

**Kurz:** Am iPhone belegt sind heute nur Akku und Firmware. Puls live scheitert noch. Fast alle Datenarten sind geplant, aber erst nach dem nächsten Realtest und je einem Mitschnitt. Echte Lücken ohne Plan: Ring-Einstellungen schreiben (Messung einschalten), Stress, SpO₂/HRV in `Metric`, HRV-Zuordnung, Gesten/Kamera, Ring finden/ausschalten.

## 2. Abgeleitete Kennzahlen

| Kennzahl | QRing | PULSE ONE | Stand |
|---|---|---|---|
| Ruhepuls | Tageswert (Händler) | eigene Berechnung aus Ruhe-/Schlafphasen (R2-5, RING-AUSWERTUNGEN A1) | geplant |
| Nacht-HRV | Tageswert | Median im Schlaffenster (A2) | geplant |
| Schlafdauer, Zeiten, Regelmäßigkeit | Dauer + Phasen | A3/A4, R2-6 | geplant |
| Schlafscore | QRing zeigt Bewertung (Händler) | **bewusst kein Score** | Entscheidung, keine Lücke |
| Erholung | – | 4 Signale (Ruhepuls, HRV, Schlaf, Empfinden) gegen eigenes 30-Tage-Band, **ohne Gesamtscore** | **gebaut** (`RecoverySignals`, Swift Testing), noch ohne echte Ringdaten |
| Trainingsbelastung, Monotonie | – | aus Abend-Rückblick (RPE × Dauer) | **gebaut** (`TrainingLoad`) |
| Persönliches Normalband + Trend | – | A6, 28/30 Tage | gebaut im Coach-Kern, geplant für Diagramme (R1-9) |
| Datenqualität / Tragezeit | – | A7, Abdeckung je Tag (HEALTH-DATA-SPEC) | geplant |
| SpO₂-Nachtbild | – | B5 mit Arzt-Hinweis | geplant |
| Stress-Tagesmuster | Tagesmittel | B4 in RING-AUSWERTUNGEN | entschieden 2026-11-21: speichern + Tagesmuster |
| Wochenbericht | – | FC-1 „Deine Woche“ | geplant (R2) |

## 3. Ist die Oberfläche individualisierbar?

**Nein, bisher nicht geplant.** DESIGN-SYSTEM-5.0 legt TODAY fest auf Kopf, Coach-Block, 4–6 `MetricCard`s, Ernährung, Heart-Kachel. Die Master-Directive nennt ein „personalisiertes Dashboard“ nach dem Onboarding, aber keine Spec beschreibt, wie. Vorhanden oder geplant sind nur: Designprofil Dark/Light, Ton und Haptik an/aus, Sportmodule freiwillig, Tabs erscheinen erst mit echter Funktion.

**Lücke:** Kacheln auf TODAY ein/aus, Reihenfolge per Ziehen, Auswahl der Kennzahlen je Profil, Standard aus Onboarding-Zielen, ausgeblendete Datenarten trotzdem weiter speichern. Gehört in DESIGN-SYSTEM-5.0 (Komponente) und M3 (Profil/Onboarding).

## 4. Empfohlene Aufnahme in Backlog/Roadmap

1. **Ring-Einstellungen schreiben** (0x16 Puls-Intervall, 0x2C SpO₂, 0x38 HRV, 0x36 Stress) als Messprofile Standard/Akku sparen/Minimal (RING-AUSWERTUNGEN §5.1). Ohne das zeichnet der Ring HRV/SpO₂ evtl. gar nicht auf. Erst lesen, dann nach Realtest schreiben.
2. `Metric`/`SampleKind` um SpO₂, HRV (Ring, eigene Methode), Stress-Index, Schlafphasen, Schritte/kcal/Distanz erweitern; HRV 0x39 aus `hrv_sdnn` lösen.
3. Stress: **entschieden 2026-11-21 (Johannes): speichern + Tagesmuster zeigen**, als Herstellerwert markiert.
4. Sync-Pflicht: Ringspeicher ~7 Tage; Hinweis nach 4 Tagen ohne Sync (RING-AUSWERTUNGEN R6).
5. Kleine Gerätefunktionen: Ring finden (LED), ausschalten.
6. R09: Temperatur und Gesten/Kamera per Mitschnitt mit QRing ermitteln (Forschung, kein Versprechen).
7. Individualisierbares TODAY (Kacheln ein/aus, Reihenfolge, je Profil).
