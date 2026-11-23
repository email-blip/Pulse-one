# Auftrag 01 – Daten / R03 / HealthKit / Schlaf

Du bist Team **01 Daten** im PULSE-ONE-Neubau. Zuerst `docs/neubau/auftraege/00-GEMEINSAM.md` lesen und befolgen.
Dieser Auftrag erweitert die laufende Arbeit „Ring dauerhaft verbunden halten“ (Hintergrundverbindung, AccessorySetupKit-Prüfung nach TN3115): die bleibt Teil von 01, aber nach M1.

**Deine Dateien:** `Sources/Bluetooth/*`, `Sources/Connect/*`, `Sources/Persistence/*` (außer `PulseSchema.swift`), PulseCore `Colmi*`, `RingHistorySync`, `RingSettings`, `RingSnapshot`, `Connect/*`, `Scores/*`, `Insights/PersonalBaseline*`, `Day/*`, neu `PulseCore/Timeline/*`.

**M1-Lieferung (Reihenfolge):**
1. Schlafsegmente: `BC 27`-Phasen als `SleepSegment` (Vertrag) mit echten Beginn-/Endzeiten speichern. Neues SwiftData-Modell `StoredSleepSegment` (Modell-Datei in Persistence von dir; Eintrag in `PulseSchema.swift` als kleiner Patch, 00 merged). Rohcode immer mitspeichern, unbekannte Codes = `unknown`. Keine Phasen aus `stageSummary`-Text zurückraten. Tageswechsel/Sommerzeit/Ringzeit korrekt. Gadgetbridge-Parser und `docs/colmi-protokoll.md` gegenprüfen; REM nicht pauschal ausschließen.
2. Abfragen für Spuren in `PulseCore/Timeline/`: `MeasurementPoint`s je `TimelineTrack` und Zeitfenster (Originalpunkte bis 2 Tage Spanne, darüber Aggregation mit min/max/Mittel, kenntlich), `SleepNight`s je Fenster, „letzter gültiger Wert“ je Messart mit Zeit. Lücken bleiben Lücken.
3. `receivedAt` (Empfangszeit) speichern, wo sie anfällt.
4. Scores: Erholung ab Tag 1 (Startwerte aus Erfahrungswerten, mit jeder Nacht persönlicher); keine „lernt noch“-/„Noch X Tage“-Texte mehr nach außen.
5. Testdaten-Szenarien (nur `-uiTesting`): volle Nacht, Nacht mit Lücke, unbekannter Phasencode, doppelter Sync, falsches Profil, veralteter Wert, unregelmäßige Abstände, Sommerzeitwechsel. Diese nutzen 03, 04, 06.

**Abnahme:** PulseCore-Tests für jedes Szenario; Schema-Wächter aktualisiert; vorhandene Daten bleiben erhalten (Migration nur additiv in M1); PR „[01] Schlafsegmente und Zeitspur-Abfragen“.
**Danach (M2):** Schlaf Ende-zu-Ende am echten R03, Hintergrund/State Restoration/HealthKit-Änderungshinweise, Getrennt-Prüfung verbunden/synchronisiert/neue Messung/Live-Stream.
