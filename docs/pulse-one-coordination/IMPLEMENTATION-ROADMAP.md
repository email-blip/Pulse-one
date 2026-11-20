# PULSE ONE – Implementation Roadmap (Master Directive 5.0)

Stand: 2026-11-20. Verantwortlich: Claude Code. Jede Zeile ist ein eigener, kleiner PR mit Tests und Abnahmekriterium, bewertet in `ACCEPTANCE-MATRIX.md`. Die Reihenfolge innerhalb eines Release ist verbindlich, über Releases hinweg nur grob. Fachkonzepte: `CLAUDE-INTELLIGENCE-SPEC.md`, `COACH-ENGINE-SPEC.md`, `NUTRITION-SPEC.md`, `CLINICAL-CONTEXT-SPEC.md`, `DESIGN-SYSTEM-5.0.md`; Expertenrat: `EXPERT-COUNCIL-REVIEW.md`, `OPEN-SOURCE-TECHNICAL-AUDIT.md` (alle gemergt). Release 3–8 folgen deren Vorgaben; Abweichungen werden hier begründet.

Build-Regeln: Jeder Push auf `apps/**` kostet einen CI-Lauf (≈ 20 Gratis-Minuten), deshalb werden Änderungen gebündelt. Ein TestFlight-Build kommt am Ende jedes Release und zusätzlich, wenn ein Hardwaretest nötig ist.

## Release 1 – Functional Recovery (laufend)
Abnahme: echter Datenfluss auf Johannes' iPhone (Ring **und** Apple Health), sichtbar in Diagrammen.

| PR | Inhalt | Status |
|---|---|---|
| #8 | Sanierungsplan 4.0 | gemergt |
| #9 | Messzustände (angefordert → läuft → Wert/fehlgeschlagen), BLE-Diagnose-Export | CI läuft |
| R1-3 | Ringuhr auf Ortszeit, Akku-Meldung `0x73`, Open-Source-Review, 5.0-Steuerdokumente; **TestFlight-Build für den Ringtest** | als Nächstes |
| R1-4 | Auswertung des Mitschnitts von Johannes: Pulsmessung reparieren (falls nötig), getestete Firmware eintragen | wartet auf Mitschnitt |
| R1-5 | Persistenz: `VersionedSchema` V1, sichtbarer Fehler statt stillem Speicherverlust | |
| R1-6 | HealthKit: Typ-Status (letzter Import, Anzahl, Fehler), Anker nach Speichern, neue Typen (Atemfrequenz, Ruheenergie, VO₂max, Gewicht, Größe, Training), Einrichtungsscreen mit Zweck je Typ | |
| R1-7 | HealthKit-Beobachter + Background Delivery mit Bündelung | |
| R1-8 | Tab-Struktur (Heute, Gesundheit, Geräte & Einstellungen), Datenquellen-Ansicht | |
| R1-9 | Grunddiagramme (Swift Charts): Puls, Ruhepuls, HRV, SpO₂, Schritte, Schlafdauer; Zeiträume Tag/7/30/90; Punkt antippen → Wert, Zeit, Quelle | |
| R1-10 | Heart Chamber: ehrlicher Zustand ohne Puls, Prototyp-Kennzeichnung, Test-Knopf für Haptik und Ton | |
| R1-11 | TestFlight-Build „Release 1“, Abnahme nach Szenarien A/B/D | |

Hinweis: Johannes hat keine Apple Watch (HEALTH-DATA-SPEC §0). Szenario B prüft deshalb iPhone-Daten (Schritte, Strecke, Gewicht, Trainings).

## Release 2 – Health Analytics
| PR | Inhalt |
|---|---|
| R2-1 | `StoredAggregate` (Stunde/Tag/Woche/Monat) + Abdeckung + Lücken, Migration V2 |
| R2-2 | Ring-Verlauf: Puls-Log `0x15`, Schritte `0x43`; Big-Data-Dienst für SpO₂ `0x2A` und Schlaf `0x27` **nur nach Mitschnitt-Beleg** |
| R2-3 | HealthAnalytics-Kern: Basislinie (Median/MAD ohne letzte 21 Tage), Trend, Abweichung, Zustand „Basislinie entsteht“ |
| R2-4 | **SpO₂ vertikal** (Referenz 4.2): Tages-/Monatsstatistik, niedrige Einzelwerte, Nachtwerte, Messhäufigkeit, Abdeckung, Quellenvergleich, Diagramm |
| R2-5 | Puls und Ruhepuls (eigene Berechnung aus Ruhephasen), Zonen |
| R2-6 | HRV (SDNN aus HealthKit, RMSSD aus RR, nicht vermischt), Schlaf (Sitzungen, Phasen, Regelmäßigkeit), Aktivität |
| R2-7 | Langzeitdiagramme (Jahr, Gesamt, frei), Export/Wiederherstellung/Löschung |
| R2-8 | Ringwerte nach Apple Health schreiben (Puls, SpO₂, Schlaf; nicht Schritte/HRV), mit Erkennung eigener Werte |
| R2-9 | Bewegungsaufzeichnung: Sporttypen, GPS optional, Ring-Puls entlang der Route, Karte mit Farbverlauf, Splits, GPX, Privatzonen |

## Release 3 – Claude Intelligence
| PR | Inhalt |
|---|---|
| R3-1 | Einstellungen → KI-Anbieter → Anthropic Claude: Keychain, Verbindungstest (`GET /v1/models`), Modellwahl, Schlüssel entfernen |
| R3-2 | HealthEvidence: Belegkatalog-IDs, `HealthAnalysisContext` v1, Freigabe je Kategorie, Vorschau vor dem Senden |
| R3-3 | Messages-API-Client (URLSession), strukturierte Ausgabe per JSON-Schema, Zahlenprüfer, Kostenanzeige je Analyse |
| R3-4 | Analysearten (Tag … Langzeit, Schlaf, Herz-Kreislauf, Belastung), 15-Abschnitte-Bericht, anklickbare Belege |
| R3-5 | Gespräch mit Rückfragen, Analysehistorie, Vergleich |

## Release 4–8
Diese Releases werden nach Merge der Fachkonzepte in PRs zerlegt. Grobe Reihenfolge:
- **R4 Coach:** Onboarding, Übungsbibliothek (Lizenzen geprüft), Tagesplan, Programme, regelbasierte Belastungsgrenzen.
- **R5 Ernährung:** Lebensmitteldatenbank, Barcode, Fotoanalyse mit Bestätigung, Ziele, Planung.
- **R6 Unified Coach:** gemeinsamer Kontext, Coach-Gedächtnis (einsehbar, löschbar), Monats- und Jahresberichte.
- **R7 Klinischer Kontext:** freiwillige Diagnosen, ICD-Suche, Gesprächsvorbereitung. Das Forschungsmodul ist im Release-Build nicht enthalten.
- **R8 Premium Experience:** Designsystem 5.0, Heart Chamber 3D, Living Twin, Sound, Haptik, Performance, Barrierefreiheit.

## Abhängigkeiten von Johannes
1. Nach R1-3: Build installieren, eine Pulsmessung machen und die Diagnose teilen (Anleitung kommt mit dem Build).
2. Ab R3-1: den eigenen Anthropic-Schlüssel **in der App** eingeben.
