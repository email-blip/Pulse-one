# PULSE ONE – Acceptance Matrix

Stand: 2026-11-20. Nachweisstufen (5.0 Teil XIII): **G** Geplant · **I** Implementiert · **B** Gebaut (CI grün) · **S** Simulatorgetestet · **H** auf echter Hardware getestet · **A** funktional abgenommen (Johannes).
Eine Stufe gilt nur mit Beleg (CI-Lauf, Screenshot, Mitschnitt, Nachricht von Johannes). Ein grüner CI-Lauf ist keine Abnahme.

## Release 1 – Functional Recovery

| ID | Funktion | Abnahmekriterium | Stufe | Beleg |
|---|---|---|---|---|
| R1.01 | R03 finden und verbinden | Ring erscheint, Verbindung steht, Status „Verbunden“ | **H** | Johannes, Build 4 |
| R1.02 | Akku und Firmware | Werte entsprechen QRing-App | **H** | 100 %, RY03_3.00.21_241028 |
| R1.03 | Messzustände | „läuft“ erst nach Ring-Antwort; Fehler mit Grund; Zeitablauf 10 s / 30 s | I | PR #9 |
| R1.04 | Live-Puls | Wert mit Einheit, Uhrzeit, Quelle; gespeichert; im Verlauf sichtbar | I (fehlgeschlagen in Build 4) | Mitschnitt nötig |
| R1.05 | BLE-Diagnose | Export als .txt ohne Geräte-ID; enthält alle Dienste und Pakete | I | PR #9 |
| R1.06 | Ringuhr Ortszeit | Ringzeit = iPhone-Uhrzeit (QRing-Anzeige oder Verlaufszeitstempel) | G | R1-3 |
| R1.07 | Persistenz sicher | Kein stiller Speicherverlust; Schema versioniert | G | R1-5 |
| R1.08 | Apple Health Einrichtung | Jeder Typ mit Zweck; Import-Status je Typ; letzter Import | G | R1-6 |
| R1.09 | Apple Health Import | Werte der letzten 30 Tage sichtbar, Anzahl je Typ stimmt grob mit Health-App | I (ohne Anzeige) | iPhone offen |
| R1.10 | Hintergrund-Aktualisierung | Neue Health-Werte erscheinen ohne manuelles Synchronisieren nach App-Öffnen | G | R1-7 |
| R1.11 | Datenquellen-Ansicht | Jede Quelle mit Stufe, letzter Synchronisierung, Datenarten | I (Geräte-Screen) | R1-8 |
| R1.12 | Grunddiagramme | 6 Messarten, 4 Zeiträume, Punkt antippen zeigt Wert/Zeit/Quelle | G | R1-9 |
| R1.13 | Heart Chamber ehrlich | ohne Puls kein Schlag; Haptik und Ton auf iPhone spürbar/hörbar | S | R1-10 |
| R1.14 | Keine Scheinfunktionen | Jeder sichtbare Button löst eine echte Aktion aus | I | Button-Audit SANIERUNG-4.0 §3 |

## Release 2 – Health Analytics
| ID | Funktion | Abnahmekriterium | Stufe |
|---|---|---|---|
| R2.01 | Aggregate | Tages-/Wochen-/Monatswerte stimmen mit Rohdaten (Test mit festen Daten) | G |
| R2.02 | Basislinien | Median/MAD, „entsteht“ bei zu wenig Daten | G |
| R2.03 | SpO₂-Referenz | Statistik, Tiefstwerte, Nacht, Abdeckung, Quellenvergleich; jeder Wert nachrechenbar | G |
| R2.04 | Puls/Ruhepuls/HRV/Schlaf/Aktivität | je Analyse mit dokumentierter Formel und Test | G |
| R2.05 | Mehrjahresdaten | 3 Jahre Testdaten: Diagramm Jahr < 1 s auf iPhone | G |
| R2.06 | Export/Wiederherstellung/Löschung | Export → Löschen → Import ergibt gleiche Anzahl | G |

## Release 3 – Claude Intelligence
| ID | Funktion | Abnahmekriterium | Stufe |
|---|---|---|---|
| R3.01 | Schlüssel | nur Keychain; nicht in Logs, Diagnose, Screenshots | G |
| R3.02 | Freigabe | Vorschau der Kategorien vor jedem Senden; Ablehnen sendet nichts | G |
| R3.03 | Strukturierte Antwort | Schema-Validierung; ungültige Antwort wird nicht angezeigt | G |
| R3.04 | Belegprüfung | jede Zahl mit Beleg-ID, Abweichung → „nicht belegt“ | G |
| R3.05 | Ohne Schlüssel | lokale Analyse vollständig nutzbar | G |
| R3.06 | Kosten | Token und Kosten je Analyse sichtbar | G |

## Release 4–8
Kriterien kommen aus den Fachkonzepten (COACH-ENGINE-SPEC, NUTRITION-SPEC, CLINICAL-CONTEXT-SPEC, DESIGN-SYSTEM-5.0) und werden hier nach deren Merge ergänzt.

## Szenarien (4.0 §13)
- **A Ring:** verbinden → messen → Wert sehen → im Verlauf und Diagramm finden → Diagnose teilen.
- **B Apple Health:** freigeben → Import-Status je Typ → Werte im Diagramm mit Quelle „Apple Health“.
- **C Claude:** Schlüssel eingeben → Test → Analyse mit Vorschau → Bericht mit geprüften Belegen.
- **D Alltag:** App am nächsten Morgen öffnen → neue Werte ohne Zutun, Heute zeigt Stand und Quelle.
