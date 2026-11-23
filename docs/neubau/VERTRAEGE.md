# Gemeinsame Verträge (Besitzer: 00 Leitstand)

Code: `apps/PulseOne/Packages/PulseCore/Sources/PulseCore/Contracts/`, Tests: `Tests/PulseCoreTests/ContractsTests.swift`.
Änderungswunsch: im eigenen PR nur benutzen, nie ändern; Wunsch mit Begründung an den Leitstand (über Johannes/Koordinator oder im PR-Text „Vertragsänderung nötig: …“).

| Datei | Typen | Regeln |
|---|---|---|
| `MeasurementContracts.swift` | `MeasurementPoint` (= „Measurement“), `SleepPhase`, `SleepSegment`, `SleepNight` | `MeasurementPoint` ist nur eine Sicht auf `HealthSample` (eine Datenwelt). `receivedAt` fällt auf `importedAt` zurück, bis 01 sie speichert. Unbekannte Schlafcodes bleiben `unknown`. Zeit im Bett (`inBed`) ≠ Schlaf (`asleep`). Lücken (`gaps`) werden gezeigt, nie gefüllt. |
| `TimelineContracts.swift` | `TimelineTrack`, `TimelineRange`, `TimelineState`, `NarrationCue` | Alle Spuren nutzen dasselbe absolute Zeitfenster `visible`. Cursor in einer Lücke wählt keinen Punkt (`nearest(…, tolerance:)`). Über 2 Tagen Spanne wird aggregiert (kenntlich), darunter Originalpunkte. `NarrationCue.anchor` bewegt beim Sprechen den Cursor. |
| `CoachContracts.swift` | `CoachInsight`, `EvidenceRef`, `CoachDirection`, `CoachAction`, `UserCorrection`, `CoachRevision`, `RookPresence` | Sichtbar ist `interpretation` (≤3 Sätze) + `action`; `observation` und `evidence` gehören hinter „Warum?“. Korrektur über `revise(…)`: alte Deutung bleibt als Revision. `RookPresence` ist alles, was die Figur zeigen darf. |
| `WorkoutContracts.swift` | `WorkoutSession`, `WorkoutStep`, `WorkoutPhase`, `WorkoutRunState`, `AnnouncementState` | Zeiten nur aus Zeitstempeln/Pausen (`remaining(at:)`, `scheduledPhaseEnd`, `catchUp(to:)`). Pause und Überspringen setzen die Ansage auf `silent`. Bildschirm, Stimme, Mitteilung und Live Activity lesen dieselbe Session. |
| `DashboardContracts.swift` | `DashboardLayout`, `DashboardTile`, `DashboardTileSize` | IDs stabil (`metric.<kind>`, `sleep`, `training`); doppelte IDs fallen beim Anlegen weg; neue Geräte hängen Kacheln hinten an (`appendMissing`), die Reihenfolge des Nutzers bleibt. |
